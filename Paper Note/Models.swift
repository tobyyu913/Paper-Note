//
//  Models.swift
//  Paper Note
//
//  A Library of Notebooks, persisted as JSON in Application Support.
//

import SwiftUI
import LocalAuthentication

struct Notebook: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String = "Untitled"
    var writer: String = ""
    var dateText: String = ""
    /// Index into Notebook.leathers for the cover color.
    var leather: Int = 0
    var pages: [String] = [""]

    var pageCount: Int { max(1, pages.count) }

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
        notebooks = saved
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(notebooks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
