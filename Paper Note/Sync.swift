//
//  Sync.swift
//  Paper Note
//
//  Account + sync through Firebase (Google), using its REST APIs directly so
//  no SDK is needed: Firebase Authentication for email/password sign-in and
//  Cloud Firestore for storage. Sign in on any device and the same notebooks
//  appear everywhere.
//
//  Each notebook carries an `updatedAt` stamp. A sync reads the user's
//  notebooks from Firestore, pushes any local copy (or deletion) that is
//  newer, and applies anything remote that is newer. Last write wins, per
//  notebook. Documents live at users/{uid}/notebooks/{id} with fields
//  updatedAt (int), deleted (bool) and data (the notebook as a JSON string).
//

import Foundation

/// One notebook as the sync store sees it.
struct SyncRow: Codable {
    var id: String
    var updatedAt: Int
    var deleted: Bool
    var data: Notebook?
}

enum SyncError: LocalizedError {
    case notSignedIn, server(String), http(Int)
    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in"
        case .server(let msg): return msg
        case .http(let code): return "Server returned HTTP \(code)"
        }
    }
}

enum Firebase {
    static let apiKey = "AIzaSyCt7U0F5HRbL55B9B00L70lkzoksar4dTo"
    static let projectID = "paper-note-73a4d"
    static let auth = "https://identitytoolkit.googleapis.com/v1/accounts"
    static let token = "https://securetoken.googleapis.com/v1/token"
    static let firestore = "https://firestore.googleapis.com/v1/projects/\(projectID)/databases/(default)/documents"
}

@Observable
final class SyncAccount {
    var email: String = UserDefaults.standard.string(forKey: "PaperNoteSyncEmail") ?? "" {
        didSet { UserDefaults.standard.set(email, forKey: "PaperNoteSyncEmail") }
    }
    private(set) var uid: String = UserDefaults.standard.string(forKey: "PaperNoteSyncUID") ?? "" {
        didSet { UserDefaults.standard.set(uid, forKey: "PaperNoteSyncUID") }
    }
    private var refreshToken: String = UserDefaults.standard.string(forKey: "PaperNoteSyncRefresh") ?? "" {
        didSet { UserDefaults.standard.set(refreshToken, forKey: "PaperNoteSyncRefresh") }
    }
    private var idToken = ""
    private var idTokenExpiry = Date.distantPast

    var isSignedIn: Bool { !refreshToken.isEmpty && !uid.isEmpty }

    /// Human-readable state for the account sheet.
    var status: String = ""
    var lastSync: Date?
    var syncing = false

    // MARK: - HTTP

    private func request(_ url: String, method: String = "POST", json: Any? = nil, bearer: String? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let json { req.httpBody = try JSONSerialization.data(withJSONObject: json) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (200..<300).contains(code) else {
            if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
                throw SyncError.server(Firebase.friendly(msg))
            }
            throw SyncError.http(code)
        }
        return obj
    }

    // MARK: - Auth

    @MainActor
    func signIn(email: String, password: String, create: Bool) async throws {
        let r = try await request("\(Firebase.auth):\(create ? "signUp" : "signInWithPassword")?key=\(Firebase.apiKey)",
                                  json: ["email": email, "password": password, "returnSecureToken": true])
        guard let token = r["idToken"] as? String, let refresh = r["refreshToken"] as? String,
              let id = r["localId"] as? String else { throw SyncError.server("Unexpected sign-in response") }
        self.email = (r["email"] as? String) ?? email
        self.uid = id
        self.refreshToken = refresh
        self.idToken = token
        self.idTokenExpiry = Date().addingTimeInterval(3300)
        status = "Signed in as \(self.email)"
    }

    @MainActor
    func signOut() {
        refreshToken = ""; idToken = ""; uid = ""
        status = "Signed out"
        lastSync = nil
    }

    /// A valid ID token, refreshed when it is about to expire.
    private func freshToken() async throws -> String {
        guard isSignedIn else { throw SyncError.notSignedIn }
        if !idToken.isEmpty && idTokenExpiry > Date() { return idToken }
        do {
            let r = try await request("\(Firebase.token)?key=\(Firebase.apiKey)",
                                      json: ["grant_type": "refresh_token", "refresh_token": refreshToken])
            guard let token = r["id_token"] as? String else { throw SyncError.server("Couldn’t refresh sign-in") }
            idToken = token
            if let rt = r["refresh_token"] as? String { refreshToken = rt }
            idTokenExpiry = Date().addingTimeInterval(3300)
            return token
        } catch SyncError.server(let msg) where msg.contains("TOKEN_EXPIRED") || msg.contains("USER_NOT_FOUND") || msg.contains("INVALID_REFRESH_TOKEN") {
            await MainActor.run { signOut() }
            throw SyncError.notSignedIn
        }
    }

    // MARK: - Firestore

    private var collection: String { "\(Firebase.firestore)/users/\(uid)/notebooks" }

    /// Pushes newer local rows, pulls newer remote rows, returns the merged set.
    func sync(rows local: [SyncRow]) async throws -> [SyncRow] {
        let token = try await freshToken()

        // 1. Everything the store has for this user.
        var remote: [String: SyncRow] = [:]
        var pageToken: String?
        repeat {
            var url = "\(collection)?pageSize=300"
            if let pageToken { url += "&pageToken=\(pageToken)" }
            let r = try await request(url, method: "GET", bearer: token)
            for doc in (r["documents"] as? [[String: Any]]) ?? [] {
                if let row = Firebase.row(from: doc) { remote[row.id] = row }
            }
            pageToken = r["nextPageToken"] as? String
        } while pageToken != nil

        // 2. Push whatever is newer here.
        var merged = remote
        for row in local {
            let theirs = remote[row.id]?.updatedAt ?? -1
            guard row.updatedAt > theirs else { continue }
            _ = try await request("\(collection)/\(row.id)", method: "PATCH",
                                  json: Firebase.document(for: row), bearer: token)
            merged[row.id] = row
        }
        return Array(merged.values)
    }

}

private extension Firebase {
    static func document(for row: SyncRow) -> [String: Any] {
        var fields: [String: Any] = [
            "updatedAt": ["integerValue": String(row.updatedAt)],
            "deleted": ["booleanValue": row.deleted],
        ]
        if let nb = row.data, let data = try? JSONEncoder().encode(nb) {
            fields["data"] = ["stringValue": String(decoding: data, as: UTF8.self)]
        } else {
            fields["data"] = ["stringValue": ""]
        }
        return ["fields": fields]
    }

    static func row(from doc: [String: Any]) -> SyncRow? {
        guard let name = doc["name"] as? String, let fields = doc["fields"] as? [String: Any] else { return nil }
        let id = String(name.split(separator: "/").last ?? "").lowercased()
        let updatedAt = Int((fields["updatedAt"] as? [String: Any])?["integerValue"] as? String ?? "0") ?? 0
        let deleted = (fields["deleted"] as? [String: Any])?["booleanValue"] as? Bool ?? false
        var notebook: Notebook?
        if !deleted, let json = (fields["data"] as? [String: Any])?["stringValue"] as? String, !json.isEmpty {
            notebook = try? JSONDecoder().decode(Notebook.self, from: Data(json.utf8))
        }
        return SyncRow(id: id, updatedAt: updatedAt, deleted: deleted, data: notebook)
    }

    /// Turns Firebase's SHOUTING_CASE error codes into sentences.
    static func friendly(_ code: String) -> String {
        switch code.split(separator: " ").first.map(String.init) ?? code {
        case "EMAIL_EXISTS": return "That email already has an account — sign in instead"
        case "EMAIL_NOT_FOUND", "INVALID_PASSWORD", "INVALID_LOGIN_CREDENTIALS": return "Wrong email or password"
        case "INVALID_EMAIL": return "Enter a valid email address"
        case "WEAK_PASSWORD": return "Password must be at least 6 characters"
        case "TOO_MANY_ATTEMPTS_TRY_LATER": return "Too many attempts — try again later"
        default: return code
        }
    }
}
