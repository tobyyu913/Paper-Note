//
//  Models.swift
//  Paper Note
//
//  A Library of Notebooks, persisted as JSON in Application Support.
//

import SwiftUI
import LocalAuthentication

/// A run of characters on a page that has been "listed" — marked as a to-do
/// style item that a click crosses out with a pen line.
struct MarkRange: Codable, Equatable {
    var location: Int
    var length: Int
    var struck: Bool

    var range: NSRange { NSRange(location: location, length: length) }
    func contains(_ index: Int) -> Bool { index >= location && index < location + length }
}

struct Notebook: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String = "Untitled"
    var writer: String = ""
    var dateText: String = ""
    /// Index into Notebook.leathers for the cover color.
    var leather: Int = 0
    var pages: [String] = [""]
    /// List marks per page, parallel to `pages`. Optional so libraries saved
    /// by older versions (no such key) still decode — never risk the notes.
    var pageMarks: [[MarkRange]]? = []
    /// Milliseconds since 1970 of the last edit — used to merge across
    /// devices. Optional so older libraries still decode.
    var updatedAt: Int? = nil

    var pageCount: Int { max(1, pages.count) }

    /// Equal apart from the sync stamp.
    func sameContent(as other: Notebook) -> Bool {
        var a = self, b = other
        a.updatedAt = nil; b.updatedAt = nil
        return a == b
    }

    func marks(for page: Int) -> [MarkRange] {
        guard let pm = pageMarks, pm.indices.contains(page) else { return [] }
        return pm[page]
    }

    mutating func setMarks(_ marks: [MarkRange], for page: Int) {
        var pm = pageMarks ?? []
        while pm.count <= page { pm.append([]) }
        pm[page] = marks
        pageMarks = pm
    }

    /// Leather cover palettes: (base, highlight, stitch).
    static let leathers: [(base: Color, high: Color, stitch: Color)] = [
        (Color(red: 0.40, green: 0.20, blue: 0.12), Color(red: 0.55, green: 0.30, blue: 0.18), Color(red: 0.85, green: 0.74, blue: 0.55)), // brown
        (Color(red: 0.13, green: 0.22, blue: 0.18), Color(red: 0.20, green: 0.33, blue: 0.26), Color(red: 0.80, green: 0.78, blue: 0.60)), // forest
        (Color(red: 0.20, green: 0.16, blue: 0.32), Color(red: 0.30, green: 0.24, blue: 0.45), Color(red: 0.82, green: 0.78, blue: 0.62)), // plum
        (Color(red: 0.38, green: 0.10, blue: 0.12), Color(red: 0.52, green: 0.16, blue: 0.18), Color(red: 0.86, green: 0.76, blue: 0.56)), // oxblood
        (Color(red: 0.10, green: 0.10, blue: 0.12), Color(red: 0.20, green: 0.20, blue: 0.22), Color(red: 0.70, green: 0.70, blue: 0.72)), // charcoal
    ]

    var palette: (base: Color, high: Color, stitch: Color) {
        Notebook.leathers[min(max(0, leather), Notebook.leathers.count - 1)]
    }
}

@Observable
final class Library {
    var notebooks: [Notebook] = [] { didSet { save() } }
    var openID: Notebook.ID?

    let account = SyncAccount()

    /// Whether Touch ID may be used to unlock notebooks. When off, only the
    /// passcode is accepted. Persisted across launches; defaults to on.
    var useBiometrics: Bool = (UserDefaults.standard.object(forKey: "PaperNoteUseBiometrics") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(useBiometrics, forKey: "PaperNoteUseBiometrics") }
    }

    /// True only when this Mac actually has Touch ID hardware available.
    var biometricsAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    init() { load() }

    @discardableResult
    func newNotebook() -> Notebook.ID {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        var nb = Notebook()
        nb.title = "Untitled"
        nb.dateText = formatter.string(from: Date())
        nb.leather = notebooks.count % Notebook.leathers.count
        notebooks.append(nb)
        return nb.id
    }

    func delete(_ id: Notebook.ID) {
        tombstones[id.uuidString.lowercased()] = Library.nowMs()
        saveTombstones()
        notebooks.removeAll { $0.id == id }
        if openID == id { openID = nil }
    }

    // MARK: - Lock

    /// The passcode that unlocks a notebook when Touch ID is unavailable or
    /// declined. Defaults to "paper note"; the owner can change it.
    static let defaultPasscode = "paper note"

    var passcode: String {
        get { UserDefaults.standard.string(forKey: "PaperNotePasscode") ?? Library.defaultPasscode }
        set { UserDefaults.standard.set(newValue, forKey: "PaperNotePasscode") }
    }

    func binding(for id: Notebook.ID) -> Binding<Notebook> {
        Binding(
            get: { self.notebooks.first(where: { $0.id == id }) ?? Notebook() },
            set: { newValue in
                if let i = self.notebooks.firstIndex(where: { $0.id == id }) {
                    self.notebooks[i] = newValue
                }
            }
        )
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperNote", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("library.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? JSONDecoder().decode([Notebook].self, from: data) else { return }
        lastSaved = saved
        notebooks = saved
    }

    /// The library as last written to disk, with sync stamps. `notebooks` in
    /// memory is compared against this on every save so only notebooks that
    /// actually changed get a fresh `updatedAt`.
    private var lastSaved: [Notebook] = []
    private var applyingRemote = false

    /// The library file is kept "locked" (the Finder lock / immutable flag) so
    /// other apps and editors can't change it. Saving unlocks it just long
    /// enough to write, then locks it again.
    private func save() {
        let stamped = applyingRemote ? notebooks : stampChanges(notebooks)
        lastSaved = stamped
        guard let data = try? JSONEncoder().encode(stamped) else { return }
        let url = fileURL
        setLocked(false, url)
        try? data.write(to: url, options: .atomic)
        setLocked(true, url)
        if !applyingRemote { scheduleSync() }
    }

    private func stampChanges(_ current: [Notebook]) -> [Notebook] {
        let previous = Dictionary(lastSaved.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let now = Library.nowMs()
        return current.map { nb in
            var out = nb
            if let old = previous[nb.id], old.sameContent(as: nb) {
                out.updatedAt = old.updatedAt
            } else {
                out.updatedAt = now
            }
            return out
        }
    }

    private func setLocked(_ locked: Bool, _ url: URL) {
        try? FileManager.default.setAttributes([.immutable: locked], ofItemAtPath: url.path)
    }

    // MARK: - Sync

    static func nowMs() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    /// Deleted notebook ids (lower-cased) → when, so a deletion here also
    /// deletes on other devices instead of the notebook coming back.
    private var tombstones: [String: Int] = {
        guard let data = UserDefaults.standard.data(forKey: "PaperNoteTombstones"),
              let t = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return t
    }()

    private func saveTombstones() {
        UserDefaults.standard.set(try? JSONEncoder().encode(tombstones), forKey: "PaperNoteTombstones")
    }

    private var syncWork: DispatchWorkItem?

    /// Sync shortly after the last edit (edits come in bursts while typing).
    func scheduleSync(after seconds: Double = 2) {
        guard account.isSignedIn else { return }
        syncWork?.cancel()
        let work = DispatchWorkItem { [weak self] in Task { @MainActor in await self?.syncNow() } }
        syncWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    @MainActor
    func syncNow() async {
        guard account.isSignedIn, !account.syncing else { return }
        account.syncing = true
        defer { account.syncing = false }

        var rows = lastSaved.map {
            SyncRow(id: $0.id.uuidString.lowercased(), updatedAt: $0.updatedAt ?? 0, deleted: false, data: $0)
        }
        for (id, when) in tombstones {
            rows.append(SyncRow(id: id, updatedAt: when, deleted: true, data: nil))
        }

        do {
            let merged = try await account.sync(rows: rows)
            apply(merged)
            tombstones = [:]
            saveTombstones()
            account.lastSync = Date()
            account.status = "Synced"
        } catch {
            account.status = "Sync failed: \(error.localizedDescription)"
        }
    }

    /// Merges the server's set into the local library: newer wins per notebook.
    private func apply(_ rows: [SyncRow]) {
        var result = lastSaved
        var changed = false
        for row in rows {
            guard let uuid = UUID(uuidString: row.id) else { continue }
            let i = result.firstIndex { $0.id == uuid }
            let localStamp = i.map { result[$0].updatedAt ?? 0 } ?? -1
            if row.deleted {
                if let i, localStamp <= row.updatedAt {
                    result.remove(at: i); changed = true
                    if openID == uuid { openID = nil }
                }
            } else if var nb = row.data {
                nb.id = uuid
                nb.updatedAt = row.updatedAt
                if let i {
                    if row.updatedAt > localStamp { result[i] = nb; changed = true }
                } else if tombstones[row.id] == nil {
                    result.append(nb); changed = true
                }
            }
        }
        guard changed else { return }
        applyingRemote = true
        notebooks = result
        applyingRemote = false
    }
}
