//
//  LinedPaper.swift
//  Paper Note
//
//  Warm cream ruled page. Rules are drawn at the exact text baselines
//  (Ruling.ruleY) so written letters sit on the line and descenders dip
//  below it. Includes a red left margin and a soft vignette.
//

import SwiftUI

struct LinedPaper: View {
    var body: some View {
        Canvas { context, size in
            // Warm paper base with gentle shading.
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [Theme.paperTop, Theme.paperBottom]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            // Horizontal rules at each baseline.
            let ruleColor = Theme.rule.opacity(0.45)
            var i = 0
            while Ruling.ruleY(line: i) < size.height - 6 {
                let y = Ruling.ruleY(line: i)
                if y > Ruling.topInset {
                    var line = Path()
                    line.move(to: CGPoint(x: 10, y: y))
                    line.addLine(to: CGPoint(x: size.width - 10, y: y))
                    context.stroke(line, with: .color(ruleColor), lineWidth: 1)
                }
                i += 1
            }

            // Red double left margin.
            let red = Theme.margin.opacity(0.7)
            for (dx, w) in [(Ruling.leftInset - 12, 0.8), (Ruling.leftInset - 9, 1.4)] {
                var margin = Path()
                margin.move(to: CGPoint(x: dx, y: 6))
                margin.addLine(to: CGPoint(x: dx, y: size.height - 6))
                context.stroke(margin, with: .color(red), lineWidth: w)
            }

            // Soft vignette.
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [.clear, Color.black.opacity(0.06)]),
                    center: CGPoint(x: size.width / 2, y: size.height / 2),
                    startRadius: min(size.width, size.height) * 0.35,
                    endRadius: max(size.width, size.height) * 0.7
                )
            )
        }
        .background(Theme.paperTop)
    }
}

#Preview {
    LinedPaper().frame(width: Theme.pageWidth, height: Theme.pageHeight)
}
