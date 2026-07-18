// FaceMatrixView — the retro LED dot-matrix face, drawn with SwiftUI
// Canvas inside a TimelineView(.animation) so it animates at display
// cadence. Port of the dot-grid pass in face3d.js.
//
// Perf note: the JS renderer uses per-dot shadowBlur for glow; a per-dot
// GraphicsContext shadow filter would be far too expensive, so each lit
// dot instead gets a larger low-alpha halo circle behind it — visually
// equivalent at LED scale.

import KindaliveKit
import SwiftUI

struct FaceMatrixView: View {
    let model: FaceRenderModel

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let geometry = model.update(time: time)
                let coverage = model.coverage(for: geometry)

                let cols = FaceGrid.cols
                let rows = FaceGrid.rows
                let gridAspect = CGFloat(cols) / CGFloat(rows)

                // Letterbox the fixed-aspect panel into the view.
                let margin: CGFloat = 0.94
                var panelW = size.width * margin
                var panelH = panelW / gridAspect
                if panelH > size.height * margin {
                    panelH = size.height * margin
                    panelW = panelH * gridAspect
                }
                let cell = panelW / CGFloat(cols)
                let ox = (size.width - panelW) / 2
                let oy = (size.height - panelH) / 2

                let r = cell * 0.42
                let glow = (0.55 + 0.6 * model.moodIntensity) * model.breath
                let mood = model.moodCurrent
                let moodColor = Color(
                    red: mood.red / 255, green: mood.green / 255, blue: mood.blue / 255
                )

                for y in 0..<rows {
                    for x in 0..<cols {
                        let lit = coverage[y * cols + x]
                        let px = ox + (CGFloat(x) + 0.5) * cell
                        let py = oy + (CGFloat(y) + 0.5) * cell
                        if lit > 0.06 {
                            let alpha = 0.22 + 0.78 * min(1.0, lit) * glow
                            let radius = r * (0.72 + 0.42 * lit)
                            // Halo (stands in for the JS shadowBlur glow).
                            let haloRadius = radius * 1.9
                            context.fill(
                                Path(ellipseIn: CGRect(
                                    x: px - haloRadius, y: py - haloRadius,
                                    width: 2 * haloRadius, height: 2 * haloRadius
                                )),
                                with: .color(moodColor.opacity(0.18 * lit * glow))
                            )
                            context.fill(
                                Path(ellipseIn: CGRect(
                                    x: px - radius, y: py - radius,
                                    width: 2 * radius, height: 2 * radius
                                )),
                                with: .color(moodColor.opacity(alpha))
                            )
                        } else {
                            // Unlit dot — faint, so the panel reads as a grid.
                            context.fill(
                                Path(ellipseIn: CGRect(
                                    x: px - r * 0.5, y: py - r * 0.5,
                                    width: r, height: r
                                )),
                                with: .color(.white.opacity(0.035))
                            )
                        }
                    }
                }
            }
        }
        .background(Color.black)
        .aspectRatio(CGFloat(FaceGrid.cols) / CGFloat(FaceGrid.rows), contentMode: .fit)
        .accessibilityLabel("Robot face")
    }
}
