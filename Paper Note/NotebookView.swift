//
//  NotebookView.swift
//  Paper Note
//
//  An open notebook: leather cover, ruled pages, page-curl flipping with the
//  next page already waiting underneath, a side view of the page thickness,
//  and ⌘← / ⌘→ navigation. The cover opens with a press-stud snap.
//

import SwiftUI
import AppKit

struct NotebookView: View {
    @Binding var notebook: Notebook
    var onClose: () -> Void

    @State private var sound = PaperSound()
    @State private var index = 0

    // Cover state.
    @State private var coverShowing = true
    @State private var coverAngle: Double = 0          // 0 closed, -168 open

    // Page-turn state.
    @State private var turning = false
    @State private var turnForward = true
    @State private var turnProgress: CGFloat = 0
    @State private var topIndex = 0
    @State private var bottomIndex = 0

    @State private var keyMonitor: Any?
    @State private var toast: String?

    // Full screen shows an open two-page spread; the window shows one page.
    @State private var isFullScreen = false
    @State private var fsObservers: [NSObjectProtocol] = []

    private let pageW = Theme.pageWidth
    private let pageH = Theme.pageHeight

    /// Two pages side by side, only once the cover is open and we're full screen.
    private var spread: Bool { isFullScreen }

    var body: some View {
        ZStack {
            // Desk. Tapping blank space here dismisses the text cursor.
            LinearGradient(
                colors: [Color(red: 0.30, green: 0.22, blue: 0.16),
                         Color(red: 0.18, green: 0.13, blue: 0.09)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { endEditing() }

            Group {
                if spread { spreadBook } else { book }
            }
            .shadow(color: .black.opacity(0.5), radius: 26, x: 0, y: 16)

            topBar

            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(.black.opacity(0.7), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 44)
                    .transition(.opacity)
            }
        }
        .onAppear {
            installKeyMonitor()
            installFullScreenObservers()
        }
        .onDisappear {
            removeKeyMonitor()
            removeFullScreenObservers()
        }
    }

    // MARK: - Full screen

    private func installFullScreenObservers() {
        guard fsObservers.isEmpty else { return }
        let center = NotificationCenter.default
        // If the app is already full screen when this notebook opens, start in
        // the spread. keyWindow can be nil mid-transition, so scan all windows.
        if NSApp.windows.contains(where: { $0.styleMask.contains(.fullScreen) }) {
            enterSpread()
        }
        let enter = center.addObserver(forName: NSWindow.didEnterFullScreenNotification,
                                       object: nil, queue: .main) { _ in
            enterSpread()
        }
        let exit = center.addObserver(forName: NSWindow.didExitFullScreenNotification,
                                      object: nil, queue: .main) { _ in
            isFullScreen = false
        }
        fsObservers = [enter, exit]
    }

    private func enterSpread() {
        isFullScreen = true
        // Spreads pair pages (0,1), (2,3)… so the left page must be even.
        if index % 2 != 0 { index -= 1 }
    }

    private func removeFullScreenObservers() {
        let center = NotificationCenter.default
        fsObservers.forEach(center.removeObserver)
        fsObservers = []
    }

    // MARK: - The book

    private var book: some View {
        let before = index
        let after = max(0, notebook.pages.count - 1 - index)
        return ZStack {
            // Thickness on each side.
            BookEdge(pageCount: after, height: pageH, trailing: true)
                .offset(x: pageW / 2 + BookEdge.thickness(for: after) / 2 - 1)
            if coverOpen {
                BookEdge(pageCount: before, height: pageH, trailing: false)
                    .offset(x: -(pageW / 2 + BookEdge.thickness(for: before) / 2 - 1))
            }

            pageStack

            if coverShowing {
                CoverView(notebook: $notebook, onOpenStud: goForward)
                    .rotation3DEffect(.degrees(coverAngle),
                                      axis: (x: 0, y: 1, z: 0),
                                      anchor: .leading,
                                      perspective: 0.55)
                    .opacity(coverAngle < -90 ? 0 : 1)
                    .shadow(color: .black.opacity(0.4), radius: 18, x: 8, y: 10)
            }
        }
        .frame(width: pageW, height: pageH)
    }

    private var coverOpen: Bool { !coverShowing }

    private var pageLabel: String {
        guard coverOpen else { return "Cover" }
        let n = notebook.pages.count
        if spread {
            let right = min(index + 2, n)
            return "Pages \(index + 1)–\(right) of \(n)"
        }
        return "Page \(index + 1) of \(n)"
    }

    private var pageStack: some View {
        ZStack {
            if turning {
                pageSurface(bottomIndex, editable: false)          // waiting page
                pageSurface(topIndex, editable: false)             // turning page
                    .modifier(PageCurl(progress: turnProgress, forward: turnForward))
            } else {
                pageSurface(index, editable: coverOpen)
            }
        }
    }

    private func pageSurface(_ i: Int, editable: Bool) -> some View {
        ZStack {
            LinedPaper()
            RuledTextEditor(text: pageBinding(i), editable: editable)
        }
        .frame(width: pageW, height: pageH)
        .background(Theme.paperTop)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.12), lineWidth: 1))
        .overlay(alignment: .leading) {
            LinearGradient(colors: [.black.opacity(0.16), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 24)
                .allowsHitTesting(false)
        }
    }

    // MARK: - The spread (full screen)

    /// Open two-page layout: left page = `index`, right page = `index + 1`,
    /// joined at a central spine. While the cover is closed it shows the same
    /// single, centered cover as the windowed book.
    private var spreadBook: some View {
        let leftCount = index
        let rightCount = max(0, notebook.pages.count - 1 - (index + 1))
        let open = coverOpen
        return ZStack {
            if open {
                BookEdge(pageCount: rightCount, height: pageH, trailing: true)
                    .offset(x: pageW + BookEdge.thickness(for: rightCount) / 2 - 1)
                BookEdge(pageCount: leftCount, height: pageH, trailing: false)
                    .offset(x: -(pageW + BookEdge.thickness(for: leftCount) / 2 - 1))

                spreadPageStack
            }

            if coverShowing {
                CoverView(notebook: $notebook, onOpenStud: goForward)
                    .rotation3DEffect(.degrees(coverAngle),
                                      axis: (x: 0, y: 1, z: 0),
                                      anchor: .leading,
                                      perspective: 0.55)
                    .opacity(coverAngle < -90 ? 0 : 1)
                    .shadow(color: .black.opacity(0.4), radius: 18, x: 8, y: 10)
            }
        }
        .frame(width: open ? pageW * 2 : pageW, height: pageH)
    }

    private var spreadPageStack: some View {
        ZStack {
            if turning {
                if turnForward {
                    // The whole next spread waits underneath; the right leaf
                    // (front = old right, back = new left) flips left onto it.
                    pageSurface(index, editable: false).offset(x: -pageW / 2)         // old left, until covered
                    pageSurface(bottomIndex, editable: false).offset(x: pageW / 2)    // new right, waiting
                    spreadLeaf(front: topIndex, back: topIndex + 1, forward: true)
                        .offset(x: pageW / 2)
                } else {
                    pageSurface(index + 1, editable: false).offset(x: pageW / 2)      // old right, until covered
                    pageSurface(bottomIndex, editable: false).offset(x: -pageW / 2)   // new left, waiting
                    spreadLeaf(front: topIndex, back: topIndex - 1, forward: false)
                        .offset(x: -pageW / 2)
                }
            } else {
                pageSurface(index, editable: coverOpen).offset(x: -pageW / 2)
                pageSurface(index + 1, editable: coverOpen).offset(x: pageW / 2)
            }
        }
    }

    /// A single leaf flipping about the spine, with content on both faces.
    /// `front` shows for the first half of the turn, `back` (the new facing
    /// page) for the second half, so the page lands already showing its
    /// content instead of snapping in afterwards. Forward turns pivot on the
    /// leading edge (right leaf → left); backward turns on the trailing edge.
    private func spreadLeaf(front: Int, back: Int, forward: Bool) -> some View {
        let angle = (forward ? -180.0 : 180.0) * turnProgress
        let t = abs(angle) / 180                       // 0 flat … 1 fully turned
        let edge = 1 - abs(t - 0.5) * 2                 // 0 flat … 1 edge-on
        let showingBack = abs(angle) > 90
        return ZStack {
            pageSurface(front, editable: false)
                .opacity(showingBack ? 0 : 1)
            pageSurface(back, editable: false)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))   // pre-mirror the reverse side
                .opacity(showingBack ? 1 : 0)
        }
        .overlay(
            LinearGradient(
                colors: [.black.opacity(0.28 * edge), .clear, .white.opacity(0.10 * edge)],
                startPoint: .leading, endPoint: .trailing
            )
            .allowsHitTesting(false)
        )
        .rotation3DEffect(.degrees(angle),
                          axis: (x: 0, y: 1, z: 0),
                          anchor: forward ? .leading : .trailing,
                          perspective: 0.5)
        .shadow(color: .black.opacity(0.25 * edge),
                radius: 12, x: (forward ? -10 : 10) * t, y: 6)
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack {
            HStack {
                Button(action: onClose) {
                    Label("Shelf", systemImage: "books.vertical")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))

                Spacer()

                // Leather color swatches.
                HStack(spacing: 6) {
                    ForEach(Notebook.leathers.indices, id: \.self) { idx in
                        Circle()
                            .fill(Notebook.leathers[idx].base)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white.opacity(notebook.leather == idx ? 0.9 : 0.2),
                                                     lineWidth: notebook.leather == idx ? 2 : 1))
                            .onTapGesture { notebook.leather = idx }
                    }
                }

                Spacer()

                Button(action: capturePage) {
                    Image(systemName: "camera")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
                .help("Save this page as a PNG in Documents/note book")
                .disabled(!coverOpen || turning)

                Button(action: exportPDF) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
                .help("Export the whole notebook as a PDF in Documents/note book")
                .disabled(turning)

                Text(pageLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 130, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Spacer()

            Text("⌘←  /  ⌘→  to turn pages")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 14)
        }
    }

    // MARK: - Navigation

    private func goForward() {
        guard !turning else { return }
        if coverShowing { openCover() } else { turn(forward: true) }
    }

    private func goBackward() {
        guard !turning else { return }
        if coverShowing { return }
        if index == 0 { closeCover() } else { turn(forward: false) }
    }

    private func openCover() {
        guard coverAngle == 0 else { return }
        sound.stud()
        withAnimation(.easeIn(duration: 0.5)) {
            coverAngle = -168
        } completion: {
            coverShowing = false
        }
    }

    private func closeCover() {
        coverShowing = true            // re-enter at the open angle (-168)…
        withAnimation(.easeOut(duration: 0.5)) {
            coverAngle = 0             // …and swing shut.
        } completion: {
            sound.stud()               // snap as it seats.
        }
    }

    private func turn(forward: Bool) {
        let step = spread ? 2 : 1
        if forward {
            // Make sure the pages the next spread/page reveals exist.
            while notebook.pages.count < index + step + (spread ? 2 : 1) {
                notebook.pages.append("")
            }
            if spread {
                topIndex = index + 1          // right leaf flipping left
                bottomIndex = index + 3       // right page of the next spread
            } else {
                topIndex = index
                bottomIndex = index + 1
            }
        } else {
            if spread {
                topIndex = index              // left leaf flipping right
                bottomIndex = index - 2       // left page of the previous spread
            } else {
                topIndex = index - 1
                bottomIndex = index
            }
        }
        turnForward = forward
        turnProgress = 0
        turning = true
        sound.flip()
        withAnimation(.easeInOut(duration: 0.55)) {
            turnProgress = 1
        } completion: {
            index += forward ? step : -step
            turning = false
        }
    }

    // MARK: - Capture & editing

    private func endEditing() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    @MainActor private func capturePage() {
        let text = notebook.pages.indices.contains(index) ? notebook.pages[index] : ""
        let renderer = ImageRenderer(content: PageSnapshot(text: text))
        renderer.scale = 3
        guard let cg = renderer.cgImage else { show("Couldn’t render page"); return }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }

        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleanTitle = notebook.title
            .components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleanTitle.isEmpty ? "Untitled" : cleanTitle
        let name = "\(title)-P\(index + 1).png"

        do {
            let docs = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = docs.appendingPathComponent("note book", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            try data.write(to: url)
            show("Saved \(name)")
        } catch {
            show("Save failed: \(error.localizedDescription)")
        }
    }

    /// Renders every page of the notebook into one multi-page PDF saved as
    /// "<title>.pdf" in Documents/note book.
    ///
    /// Rather than drawing the SwiftUI view straight into the PDF context
    /// (which rendered with a black background), this "photographs" each page
    /// the same way the camera button does — ImageRenderer.cgImage — and then
    /// draws those images into the PDF, one per page.
    @MainActor private func exportPDF() {
        let pageSize = CGSize(width: Theme.pageWidth, height: Theme.pageHeight)
        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { show("Couldn’t create PDF"); return }

        for text in notebook.pages {
            let renderer = ImageRenderer(content: PageSnapshot(text: text))
            renderer.scale = 3
            guard let cg = renderer.cgImage else { continue }
            var pageBox = CGRect(origin: .zero, size: pageSize)
            ctx.beginPage(mediaBox: &pageBox)
            ctx.draw(cg, in: pageBox)
            ctx.endPage()
        }
        ctx.closePDF()

        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleanTitle = notebook.title
            .components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleanTitle.isEmpty ? "Untitled" : cleanTitle
        let name = "\(title).pdf"

        do {
            let docs = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = docs.appendingPathComponent("note book", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            try pdfData.write(to: url)
            show("Saved \(name) (\(notebook.pages.count) page\(notebook.pages.count == 1 ? "" : "s"))")
        } catch {
            show("PDF save failed: \(error.localizedDescription)")
        }
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if toast == message { withAnimation { toast = nil } }
        }
    }

    private func pageBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { notebook.pages.indices.contains(i) ? notebook.pages[i] : "" },
            set: { if notebook.pages.indices.contains(i) { notebook.pages[i] = $0 } }
        )
    }

    // MARK: - Keyboard (⌘← / ⌘→) — the fix: arrow keys carry .function/.numericPad,
    // so check for .command with contains() rather than an exact modifier match.

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            switch event.keyCode {
            case 123: goBackward(); return nil   // ⌘←
            case 124: goForward();  return nil   // ⌘→
            default:  return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

// MARK: - Page curl

/// Rotates the turning page around the spine (leading edge) with perspective,
/// and darkens it as it lifts so it reads as paper curving up off the page
/// that is waiting beneath it.
struct PageCurl: ViewModifier, Animatable {
    var progress: CGFloat
    var forward: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let angle = forward ? -105 * progress : -105 * (1 - progress)
        let lift = abs(angle) / 105                       // 0 flat … 1 edge-on
        return content
            .overlay(
                LinearGradient(
                    colors: [.black.opacity(0.28 * lift), .clear, .white.opacity(0.10 * lift)],
                    startPoint: .leading, endPoint: .trailing
                )
                .allowsHitTesting(false)
            )
            .rotation3DEffect(.degrees(Double(angle)),
                              axis: (x: 0, y: 1, z: 0),
                              anchor: .leading,
                              perspective: 0.5)
            .shadow(color: .black.opacity(0.25 * lift), radius: 12, x: -10 * lift, y: 6)
    }
}
