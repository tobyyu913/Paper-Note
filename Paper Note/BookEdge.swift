//
//  BookEdge.swift
//  Paper Note
//
//  The stacked edge of the remaining (or already-read) pages, seen from the
//  side. Thickness grows with the page count so you can tell how far through
//  the notebook you are. `trailing` edges sit to the right of the page,
//  `leading` edges to the left.
//

import SwiftUI

struct BookEdge: View {
    var pageCount: Int
    var height: CGFloat
    var trailing: Bool

    static let perPage: CGFloat = 0.55
    static let maxThickness: CGFloat = 22

    static func thickness(for count: Int) -> CGFloat {
        min(maxThickness, CGFloat(max(0, count)) * perPage)
    }

    var thickness: CGFloat { BookEdge.thickness(for: pageCount) }

    var body: some View {
        Canvas { context, size in
            guard size.width > 0.5 else { return }
            // Cream block.
            context.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size),
                     cornerRadius: trailing ? 3 : 0),
                with: .color(Theme.paperBottom)
            )
            // Individual page edges as fine vertical lines.
            var x: CGFloat = trailing ? 0 : size.width
            let step: CGFloat = 0.9
            var k = 0
            while x >= 0 && x <= size.width {
                let shade = k % 3 == 0 ? 0.14 : 0.06
                var line = Path()
                line.move(to: CGPoint(x: x, y: 1))
                line.addLine(to: CGPoint(x: x, y: size.height - 1))
                context.stroke(line, with: .color(.black.opacity(shade)), lineWidth: 0.5)
                x += trailing ? step : -step
                k += 1
            }
            // Outer-edge shading for roundness.
            let outer = trailing
                ? Gradient(colors: [.clear, .black.opacity(0.22)])
                : Gradient(colors: [.black.opacity(0.22), .clear])
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(outer,
                                      startPoint: .zero,
                                      endPoint: CGPoint(x: size.width, y: 0))
            )
        }
        .frame(width: thickness, height: height - 10)
    }
}
