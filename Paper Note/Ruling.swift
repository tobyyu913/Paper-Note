//
//  Ruling.swift
//  Paper Note
//
//  Shared layout metrics and colors. The ruled background and the text
//  editor both read from here so that the baseline of every line of text
//  sits exactly on a printed rule (descenders like g, y, f drop below it).
//

import SwiftUI
import AppKit

enum Theme {
    // Page geometry.
    static let pageWidth: CGFloat = 560
    static let pageHeight: CGFloat = 760

    // Ink and paper.
    static let ink = Color(red: 0.13, green: 0.19, blue: 0.45)
    static let paperTop = Color(red: 0.98, green: 0.95, blue: 0.86)
    static let paperBottom = Color(red: 0.96, green: 0.91, blue: 0.78)
    static let rule = Color(red: 0.42, green: 0.55, blue: 0.78)
    static let margin = Color(red: 0.82, green: 0.28, blue: 0.30)
}

enum Ruling {
    static let fontName = "Bradley Hand"
    static let fontSize: CGFloat = 16          // small handwriting
    static let leftInset: CGFloat = 70         // text starts past the red margin
    static let topInset: CGFloat = 26
    static let lineSpacing: CGFloat = 18        // extra gap so rows are roomy

    static var nsFont: NSFont {
        NSFont(name: fontName, size: fontSize)
            ?? NSFont(name: "Noteworthy", size: fontSize)
            ?? .systemFont(ofSize: fontSize)
    }

    /// Natural line height of the font (no extra spacing).
    static var naturalLineHeight: CGFloat {
        let f = nsFont
        return f.ascender - f.descender + f.leading
    }

    /// Vertical distance from one baseline to the next.
    static var rowHeight: CGFloat { naturalLineHeight + lineSpacing }

    /// Distance from the top of a line fragment down to its baseline.
    /// NSLayoutManager places the baseline at ascent below the fragment top.
    static var firstBaseline: CGFloat { topInset + nsFont.ascender }

    /// Y of the rule (baseline) for visible line `i`, in top-origin coords.
    static func ruleY(line i: Int) -> CGFloat {
        firstBaseline + CGFloat(i) * rowHeight
    }

    /// How many ruled lines fit on one page (the editor insets top and bottom).
    static var linesPerPage: Int {
        max(1, Int((Theme.pageHeight - topInset * 2) / rowHeight))
    }

    /// Page text with its list marks styled — a faint dotted underline for a
    /// listed item, a pen stroke straight through it once crossed out. Used by
    /// the static pages (flips, PNG, PDF) so they match the live editor.
    static func styledText(_ text: String, marks: [MarkRange]) -> AttributedString {
        var attr = AttributedString(text)
        let length = (text as NSString).length
        for m in marks {
            guard m.location >= 0, m.location + m.length <= length,
                  let r = Range(m.range, in: attr) else { continue }
            if m.struck {
                attr[r].strikethroughStyle = Text.LineStyle(pattern: .solid, color: Theme.ink)
            } else {
                attr[r].underlineStyle = Text.LineStyle(pattern: .dot, color: Theme.ink.opacity(0.35))
            }
        }
        return attr
    }
}
