//
//  RuledTextEditor.swift
//  Paper Note
//
//  A thin NSTextView wrapper. Using AppKit directly (instead of SwiftUI's
//  TextEditor) lets us pin the font metrics and insets so each line's
//  baseline matches the printed rule in LinedPaper. Non-editable instances
//  are used as the static "pages" shown during a flip, so the live page and
//  the flipping page have identical layout.
//

import SwiftUI
import AppKit

struct RuledTextEditor: NSViewRepresentable {
    @Binding var text: String
    var editable: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextView {
        let tv = PadTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textColor = NSColor(Theme.ink)
        tv.insertionPointColor = NSColor(Theme.ink)
        tv.textContainerInset = NSSize(width: Ruling.leftInset, height: Ruling.topInset)
        tv.textContainer?.lineFragmentPadding = 0
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = true
        tv.font = Ruling.nsFont
        tv.defaultParagraphStyle = Self.paragraph
        tv.typingAttributes = Self.attributes
        tv.string = text
        Self.applyAttributes(tv)
        return tv
    }

    func updateNSView(_ tv: NSTextView, context: Context) {
        tv.isEditable = editable
        tv.isSelectable = editable
        if tv.string != text {
            tv.string = text
            Self.applyAttributes(tv)
        }
        // No forced focus: clicking the page focuses it (native NSTextView
        // behavior); clicking blank space outside dismisses it.
    }

    // MARK: - Shared attributes

    private static var paragraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = Ruling.lineSpacing
        return p
    }

    private static var attributes: [NSAttributedString.Key: Any] {
        [.font: Ruling.nsFont,
         .foregroundColor: NSColor(Theme.ink),
         .paragraphStyle: paragraph]
    }

    private static func applyAttributes(_ tv: NSTextView) {
        let range = NSRange(location: 0, length: (tv.string as NSString).length)
        tv.textStorage?.setAttributes(attributes, range: range)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RuledTextEditor
        init(_ parent: RuledTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

/// A text view where clicking empty space places the cursor *there* — padding
/// the page with blank lines and spaces as needed — so you can write anywhere
/// on the page like real paper instead of spacing text down by hand.
final class PadTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        guard isEditable, let storage = textStorage else {
            super.mouseDown(with: event); return
        }

        // Click location relative to where text actually starts.
        let local = convert(event.locationInWindow, from: nil)
        let x = local.x - textContainerInset.width
        let y = local.y - textContainerInset.height

        let rowHeight = max(1, Ruling.rowHeight)
        let targetLine = max(0, Int(y / rowHeight))

        let f = font ?? Ruling.nsFont
        let spaceW = max(1, (" " as NSString).size(withAttributes: [.font: f]).width)
        let targetCol = max(0, Int(x / spaceW))

        var lines = string.components(separatedBy: "\n")
        let beyondLines = targetLine >= lines.count
        while lines.count <= targetLine { lines.append("") }

        var beyondCol = false
        let lineLen = (lines[targetLine] as NSString).length
        if lineLen < targetCol {
            beyondCol = true
            lines[targetLine] += String(repeating: " ", count: targetCol - lineLen)
        }

        // If the click landed on existing text, use normal cursor placement.
        guard beyondLines || beyondCol else {
            super.mouseDown(with: event); return
        }

        let newString = lines.joined(separator: "\n")
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        guard shouldChangeText(in: fullRange, replacementString: newString) else { return }
        storage.replaceCharacters(
            in: fullRange,
            with: NSAttributedString(string: newString, attributes: typingAttributes)
        )
        didChangeText()

        var offset = 0
        for i in 0..<targetLine { offset += (lines[i] as NSString).length + 1 }
        offset += targetCol
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: offset, length: 0))
    }
}
