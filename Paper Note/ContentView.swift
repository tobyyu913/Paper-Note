//
//  ContentView.swift
//  Paper Note
//
//  Routes between the shelf (Library) and an open notebook.
//

import SwiftUI

struct ContentView: View {
    @State private var library = Library()

    var body: some View {
        Group {
            if let id = library.openID,
               library.notebooks.contains(where: { $0.id == id }) {
                NotebookView(notebook: library.binding(for: id),
                             onClose: { library.openID = nil })
                .id(id)   // fresh state per notebook
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
