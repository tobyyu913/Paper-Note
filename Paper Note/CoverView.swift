//
//  CoverView.swift
//  Paper Note
//
//  The leather front cover. Title, writer and date are editable. A metallic
//  press stud sits on the right edge; tapping it (or flipping forward) opens
//  the notebook. The leather look is a Canvas-drawn grain + a stitched border.
//

import SwiftUI

struct CoverView: View {
    @Binding var notebook: Notebook
    /// Called when the press stud is tapped.
    var onOpenStud: () -> Void

    var body: some View {
        let p = notebook.palette
        ZStack {
            leather(base: p.base, high: p.high)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    // Stitched border.
                    RoundedRectangle(cornerRadius: 9)
                        .inset(by: 16)
                        .stroke(style: StrokeStyle(lineWidth: 1.6, dash: [6, 5]))
                        .foregroundStyle(p.stitch.opacity(0.8))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.black.opacity(0.35), lineWidth: 1)
                )

            // Embossed label area.
            VStack(spacing: 18) {
                Spacer()
                embossedField(text: $notebook.title, size: 40, placeholder: "Title", weight: .bold)
                    .padding(.horizontal, 40)

                Rectangle()
                    .frame(width: 120, height: 1)
                    .foregroundStyle(p.stitch.opacity(0.5))

                embossedField(text: $notebook.writer, size: 20, placeholder: "Writer", weight: .regular)
                    .padding(.horizontal, 40)
                embossedField(text: $notebook.dateText, size: 17, placeholder: "Date", weight: .regular)
                    .padding(.horizontal, 40)
                Spacer()
                Text("⌘→  or tap the stud to open")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.bottom, 22)
            }

            // Press stud on the right edge.
            pressStud(stitch: p.stitch)
                .frame(width: 60)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: 26)
        }
        .frame(width: Theme.pageWidth, height: Theme.pageHeight)
    }

    // MARK: - Pieces

    private func embossedField(text: Binding<String>, size: CGFloat, placeholder: String, weight: Font.Weight) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.custom(Ruling.fontName, size: size).weight(weight))
            .foregroundStyle(.white.opacity(0.92))
            .shadow(color: .black.opacity(0.6), radius: 0.5, x: 0, y: 1)   // engraved
            .shadow(color: .white.opacity(0.12), radius: 0.5, x: 0, y: -1)
            .tint(.white)
    }

    private func leather(base: Color, high: Color) -> some View {
        Canvas { context, size in
            // Base gradient.
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [high, base, base.opacity(0.85)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
            )
            // Grain: many faint short strokes seeded deterministically.
            var seed: UInt64 = 0x51ED
            func rnd() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(UInt32.max)
            }
            for _ in 0..<1400 {
                let x = rnd() * size.width
                let y = rnd() * size.height
                let len = 2 + rnd() * 5
                let bright = rnd() > 0.5
                var dot = Path()
                dot.move(to: CGPoint(x: x, y: y))
                dot.addLine(to: CGPoint(x: x + len, y: y + (rnd() - 0.5) * 2))
                context.stroke(dot,
                               with: .color(bright ? .white.opacity(0.04) : .black.opacity(0.06)),
                               lineWidth: 0.8)
            }
            // Edge shading for a padded look.
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [.clear, .black.opacity(0.25)]),
                    center: CGPoint(x: size.width / 2, y: size.height / 2),
                    startRadius: min(size.width, size.height) * 0.3,
                    endRadius: max(size.width, size.height) * 0.75
                )
            )
        }
    }

    private func pressStud(stitch: Color) -> some View {
        Button(action: onOpenStud) {
            ZStack {
                // Strap loop coming off the cover edge.
                Capsule()
                    .fill(LinearGradient(colors: [stitch.opacity(0.5), .black.opacity(0.4)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 30, height: 58)
                    .overlay(Capsule().stroke(.black.opacity(0.4), lineWidth: 1))
                    .shadow(color: .black.opacity(0.4), radius: 3, x: 1, y: 2)

                // The metal stud.
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(white: 0.95), Color(white: 0.65), Color(white: 0.35)],
                        center: .init(x: 0.35, y: 0.3),
                        startRadius: 1, endRadius: 16))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 0.8))
                    .overlay(Circle().fill(.white.opacity(0.5)).frame(width: 4, height: 4).offset(x: -3, y: -3))
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
            }
        }
        .buttonStyle(.plain)
        .help("Open notebook")
    }
}
