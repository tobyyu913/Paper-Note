//
//  ContentView.swift
//  Paper Note
//
//  Routes between the shelf (Library) and an open notebook.
//

import SwiftUI

struct ContentView: View {
    @State private var library = Library()
    /// The notebook whose lock has been cleared this session. Cleared on close
    /// so re-opening always asks for Touch ID / passcode again.
    @State private var unlockedID: Notebook.ID?

    var body: some View {
        Group {
            if let id = library.openID,
               let nb = library.notebooks.first(where: { $0.id == id }) {
                if unlockedID == id {
                    NotebookView(notebook: library.binding(for: id),
                                 onClose: { library.openID = nil; unlockedID = nil })
                    .id(id)   // fresh state per notebook
                } else {
                    UnlockView(
                        title: nb.title,
                        passcode: library.passcode,
                        useBiometrics: library.useBiometrics,
                        onUnlock: { unlockedID = id },
                        onCancel: { library.openID = nil }
                    )
                }
            } else {
                LibraryView(library: library)
            }
        }
        .frame(minWidth: 820, minHeight: 920)
    }
}

#Preview {
    ContentView()
}
