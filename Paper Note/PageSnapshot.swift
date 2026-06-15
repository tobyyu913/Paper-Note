//
//  PageSnapshot.swift
//  Paper Note
//
//  A pure-SwiftUI rendering of a page (ruled paper + text) used only for
//  exporting a PNG. The live page is an NSTextView, which ImageRenderer
//  can't snapshot, so this mirrors its layout with the same Ruling metrics.
//

import SwiftUI

struct PageSnapshot: View {
    var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinedPaper()

            Text(text)
                .font(.custom(Ruling.fontName, size: Ruling.fontSize))
                .foregroundStyle(Theme.ink)
                .lineSpacing(Ruling.lineSpacing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, Ruling.leftInset)
                .padding(.trailing, Ruling.leftInset)
                .padding(.top, Ruling.topInset)
        }
        .frame(width: Theme.pageWidth, height: Theme.pageHeight)
        .background(Theme.paperTop)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
