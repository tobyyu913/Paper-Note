//
//  LibraryView.swift
//  Paper Note
//
//  A shelf of notebooks. Pick one to open, or make a new one.
//

import SwiftUI

struct LibraryView: View {
    @Bindable var library: Library

    @State private var pendingDelete: Notebook?
    @State private var showPasscodeSheet = false

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 28)]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.22, green: 0.16, blue: 0.11),
                         Color(red: 0.14, green: 0.10, blue: 0.07)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("My Notebooks")
                        .font(.custom(Ruling.fontName, size: 34).weight(.bold))
                        .foregroundStyle(.white.opacity(0.92))

                    Spacer()

                    Button { showPasscodeSheet = true } label: {
                        Label("Passcode", systemImage: "lock.rotation")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.8))
                    .help("Change the passcode used to unlock notebooks")
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 18)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 30) {
                        ForEach(library.notebooks) { nb in
                            spine(for: nb)
                        }
                        newButton
                    }
                    .padding(32)
                }
            }
        }
        .alert("Delete this notebook?", isPresented: deleteAlertBinding, presenting: pendingDelete) { nb in
            Button("Delete", role: .destructive) { library.delete(nb.id) }
            Button("Cancel", role: .cancel) { }
        } message: { nb in
            Text("“\(nb.title.isEmpty ? "Untitled" : nb.title)” and all \(nb.pages.count) page\(nb.pages.count == 1 ? "" : "s") will be permanently deleted. This can’t be undone.")
        }
        .sheet(isPresented: $showPasscodeSheet) {
            PasscodeSheet(library: library)
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func spine(for nb: Notebook) -> some View {
        let p = nb.palette
        return VStack {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [p.high, p.base],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5).inset(by: 8)
                            .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                            .foregroundStyle(p.stitch.opacity(0.7))
                    )
                    .overlay(alignment: .leading) {
                        // Binding shading.
                        LinearGradient(colors: [.black.opacity(0.35), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: 14)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 6)

                VStack(spacing: 8) {
                    Text(nb.title.isEmpty ? "Untitled" : nb.title)
                        .font(.custom(Ruling.fontName, size: 20).weight(.bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    if !nb.writer.isEmpty {
                        Text(nb.writer)
                            .font(.custom(Ruling.fontName, size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(14)

                // Delete button (hover).
                deleteButton(nb)
            }
            .frame(width: 160, height: 210)
            .contentShape(Rectangle())
            .onTapGesture { library.openID = nb.id }

            Text("\(nb.pages.count) page\(nb.pages.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func deleteButton(_ nb: Notebook) -> some View {
        VStack {
            HStack {
                Spacer()
                Menu {
                    Button(role: .destructive) { pendingDelete = nb } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .frame(width: 22, height: 22)
            }
            Spacer()
        }
        .padding(8)
    }

    private var newButton: some View {
        Button {
            library.openID = library.newNotebook()
        } label: {
            VStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(width: 160, height: 210)
                    .overlay(
                        VStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 30, weight: .light))
                            Text("New Notebook")
                                .font(.system(size: 13))
                        }
                        .foregroundStyle(.white.opacity(0.55))
                    )
                Text(" ").font(.system(size: 11))
            }
        }
        .buttonStyle(.plain)
    }
}
