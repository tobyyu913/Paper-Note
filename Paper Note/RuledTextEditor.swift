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
//  It also carries the page's list marks: marked words get a faint dotted
//  underline, clicking them draws a pen line through (or lifts it again),
//  and pressing return on the page's last ruled line hands off to the next
//  page instead of writing past the bottom edge.
//

import SwiftUI
import AppKit

struct RuledTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var marks: [MarkRange]
    var editable: Bool = true
    var pageIndex: Int = 0
    /// Called when return is pressed on the last ruled line of the page.
    var onPageOverflow: (() -> Void)? = nil

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
        tv.pageIndex = pageIndex
        tv.onClickMark = { [weak coordinator = context.coordinator] index in
            coordinator?.toggleMark(at: index) ?? false
        }
        tv.string = text
        context.coordinator.apply(to: tv)
        return tv
    }

    func updateNSView(_ tv: NSTextView, context: Context) {
        context.coordinator.parent = self
        (tv as? PadTextView)?.pageIndex = pageIndex
        tv.isEditable = editable
        tv.isSelectable = editable
        if tv.string != text {
            tv.string = text
            context.coordinator.apply(to: tv)
        } else if context.coordinator.appliedMarks != marks {
            context.coordinator.apply(to: tv)
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

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RuledTextEditor
        var appliedMarks: [MarkRange] = []
        init(_ parent: RuledTextEditor) { self.parent = parent }

        /// Base attributes for the whole page, then the mark styling on top.
        func apply(to tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let length = (tv.string as NSString).length
            storage.setAttributes(RuledTextEditor.attributes,
                                  range: NSRange(location: 0, length: length))
            for m in parent.marks {
                guard m.location >= 0, m.location + m.length <= length else { continue }
                if m.struck {
                    storage.addAttributes([
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .strikethroughColor: NSColor(Theme.ink),
                    ], range: m.range)
                } else {
                    storage.addAttributes([
                        .underlineStyle: NSUnderlineStyle.patternDot.union(.single).rawValue,
                        .underlineColor: NSColor(Theme.ink).withAlphaComponent(0.35),
                    ], range: m.range)
                }
            }
            appliedMarks = parent.marks
        }

        func toggleMark(at charIndex: Int) -> Bool {
            guard let i = parent.marks.firstIndex(where: { $0.contains(charIndex) })
            else { return false }
            var marks = parent.marks
            let m = marks[i]

            // A mark spanning several words (saved by an older version) is
            // split so only the clicked word toggles, not the whole run.
            var words: [NSRange] = []
            (parent.text as NSString).enumerateSubstrings(in: m.range, options: .byWords) {
                _, wordRange, _, _ in words.append(wordRange)
            }
            if words.count > 1 {
                marks.remove(at: i)
                for r in words {
                    var word = MarkRange(location: r.location, length: r.length, struck: m.struck)
                    if word.contains(charIndex) { word.struck.toggle() }
                    marks.append(word)
                }
            } else {
                marks[i].struck.toggle()
            }
            parent.marks = marks
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        /// Keep mark offsets in step with edits so a listed item stays under
        /// the same words as text before it changes.
        func textView(_ tv: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString repl: String?) -> Bool {
            let delta = ((repl ?? "") as NSString).length - range.length
            guard delta != 0 || range.length > 0, !parent.marks.isEmpty else { return true }
            var updated: [MarkRange] = []
            for var m in parent.marks {
                let end = m.location + m.length
                if range.location >= end {
                    updated.append(m)                            // edit is after the mark
                } else if range.location + range.length <= m.location {
                    m.location += delta                          // edit is before: shift
                    updated.append(m)
                } else if range.location >= m.location && range.location + range.length <= end {
                    m.length += delta                            // edit inside: grow/shrink
                    if m.length > 0 { updated.append(m) }
                } else {
                    // Edit straddles an edge of the mark: keep whichever part survives.
                    let keptFront = max(0, range.location - m.location)
                    let keptBack = max(0, end - (range.location + range.length))
                    if keptFront > 0 {
                        m.length = keptFront
                        updated.append(m)
                    } else if keptBack > 0 {
                        m.location = range.location + ((repl ?? "") as NSString).length
                        m.length = keptBack
                        updated.append(m)
                    }
                }
            }
            if updated != parent.marks { parent.marks = updated }
            return true
        }

        /// Return on the last ruled line turns the page instead of writing
        /// off the bottom edge.
        func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)),
                  let lm = tv.layoutManager else { return false }
            let ns = tv.string as NSString
            let loc = tv.selectedRange().location
            var line = 0
            if ns.length > 0 {
                let charIndex = min(loc, ns.length - 1)
                let glyph = lm.glyphIndexForCharacter(at: charIndex)
                let fragment = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                line = Int(round(fragment.minY / Ruling.rowHeight))
                // Cursor sitting past a trailing newline is on the next line.
                if loc >= ns.length && ns.hasSuffix("\n") { line += 1 }
            }
            if line >= Ruling.linesPerPage - 1 {
                parent.onPageOverflow?()
                return true
            }
            return false
        }
    }
}

/// A text view where clicking empty space places the cursor *there* — padding
/// the page with blank lines and spaces as needed — so you can write anywhere
/// on the page like real paper instead of spacing text down by hand.
/// Clicking a listed word instead crosses it out (or uncrosses it).
final class PadTextView: NSTextView {
    var pageIndex: Int = 0
    /// Returns true when the click landed on a mark and was handled.
    var onClickMark: ((Int) -> Bool)?

    override func mouseDown(with event: NSEvent) {
        guard isEditable, let storage = textStorage else {
            super.mouseDown(with: event); return
        }

        // Click location relative to where text actually starts.
        let local = convert(event.locationInWindow, from: nil)
        let x = local.x - textContainerInset.width
        let y = local.y - textContainerInset.height

        // A click directly on a listed word toggles its cross-out line.
        if let lm = layoutManager, let tc = textContainer, storage.length > 0 {
            let pt = NSPoint(x: x, y: y)
            var fraction: CGFloat = 0
            let glyph = lm.glyphIndex(for: pt, in: tc, fractionOfDistanceThroughGlyph: &fraction)
            let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
            if rect.insetBy(dx: -2, dy: -2).contains(pt) {
                let charIndex = lm.characterIndexForGlyph(at: glyph)
                if onClickMark?(charIndex) == true { return }
            }
        }

        let rowHeight = max(1, Ruling.rowHeight)
        let targetLine = min(max(0, Int(y / rowHeight)), Ruling.linesPerPage - 1)

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

        // Replace only the span that actually changed (padding is pure
        // insertion), so list-mark offsets on the rest of the page survive.
        let old = string as NSString
        let new = lines.joined(separator: "\n") as NSString
        var prefix = 0
        while prefix < old.length && prefix < new.length
                && old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < old.length - prefix && suffix < new.length - prefix
                && old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) {
            suffix += 1
        }
        let changed = NSRange(location: prefix, length: old.length - prefix - suffix)
        let inserted = new.substring(with: NSRange(location: prefix,
                                                   length: new.length - prefix - suffix))
        guard shouldChangeText(in: changed, replacementString: inserted) else { return }
        storage.replaceCharacters(
            in: changed,
            with: NSAttributedString(string: inserted, attributes: typingAttributes)
        )
        didChangeText()

        var offset = 0
        for i in 0..<targetLine { offset += (lines[i] as NSString).length + 1 }
        offset += targetCol
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: offset, length: 0))
    }
}
