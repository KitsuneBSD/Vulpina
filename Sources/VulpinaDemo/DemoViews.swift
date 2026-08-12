import Vulpina
import Foundation

// MARK: - Background view

/// Fills the window with a dark gradient-like background using two overlapping rects.
final class BackgroundView: VNView {
    override func draw(_ context: VNGraphicsContext) {
        context.fill(VNPath.rect(bounds),
                     color: VNColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1))
    }
}

// MARK: - Color swatch card

final class SwatchCard: VNView {
    private let fillColor: VNColor
    private let label: String

    init(frame: VNRect, fillColor: VNColor, label: String) {
        self.fillColor = fillColor
        self.label     = label
        super.init(frame: frame)
    }

    override func draw(_ context: VNGraphicsContext) {
        // Drop-shadow simulation: dark offset rect behind the card.
        let shadow = VNPath.roundedRect(
            VNRect(x: 3, y: -3, width: bounds.width - 2, height: bounds.height - 2),
            cornerRadius: 10)
        context.fill(shadow, color: VNColor(red: 0, green: 0, blue: 0, alpha: 0.35))

        // Card body.
        let card = VNPath.roundedRect(
            VNRect(x: 0, y: 0, width: bounds.width - 4, height: bounds.height - 4),
            cornerRadius: 10)
        context.fill(card, color: fillColor)

        // Lighter top-half tint for a slight glossy feel.
        let gloss = VNPath.roundedRect(
            VNRect(x: 0, y: (bounds.height - 4) * 0.5,
                   width: bounds.width - 4, height: (bounds.height - 4) * 0.5),
            cornerRadius: 10)
        context.fill(gloss, color: VNColor(red: 1, green: 1, blue: 1, alpha: 0.12),
                     blendMode: .sourceOver)

        // Stroke border.
        context.stroke(card,
                       color: VNColor(red: 1, green: 1, blue: 1, alpha: 0.25),
                       lineWidth: 1.5)
    }
}

// MARK: - Header bar

final class HeaderBar: VNView {
    override func draw(_ context: VNGraphicsContext) {
        // Semi-transparent dark bar.
        context.fill(VNPath.rect(bounds),
                     color: VNColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 0.85))

        // Accent line at the bottom of the bar.
        let line = VNPath.rect(VNRect(x: 0, y: 0, width: bounds.width, height: 2))
        context.fill(line, color: VNColor(red: 0.35, green: 0.6, blue: 1, alpha: 0.9))
    }
}

// MARK: - Circle cluster view

final class CircleClusterView: VNView {
    override func draw(_ context: VNGraphicsContext) {
        let cx = bounds.width  * 0.5
        let cy = bounds.height * 0.5
        let r  = min(bounds.width, bounds.height) * 0.38

        let colors: [(VNColor, Double)] = [
            (VNColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 0.85),   0),
            (VNColor(red: 0.25, green: 0.85, blue: 0.4,  alpha: 0.85), 120),
            (VNColor(red: 0.25, green: 0.55, blue: 1.0,  alpha: 0.85), 240),
        ]

        for (color, angleDeg) in colors {
            let angle = angleDeg * .pi / 180
            let ox = cx + r * 0.45 * cos(angle)
            let oy = cy + r * 0.45 * sin(angle)
            let d  = r * 0.65
            let circle = VNPath.ellipse(in: VNRect(x: ox - d*0.5, y: oy - d*0.5,
                                                   width: d, height: d))
            context.beginTransparencyLayer()
            context.fill(circle, color: color)
            context.endTransparencyLayer()
        }

        // White center dot.
        let dot = VNPath.ellipse(in: VNRect(x: cx - 6, y: cy - 6, width: 12, height: 12))
        context.fill(dot, color: VNColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    }
}

// MARK: - Grid of stroked shapes

final class StrokeSamplerView: VNView {
    override func draw(_ context: VNGraphicsContext) {
        context.fill(VNPath.roundedRect(bounds, cornerRadius: 8),
                     color: VNColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 1))

        let cols = 3, rows = 2
        let cellW = bounds.width  / Double(cols)
        let cellH = bounds.height / Double(rows)
        let pad   = 6.0

        let shapes: [VNPath] = [
            VNPath.ellipse(in: VNRect(x: pad, y: pad,
                                      width: cellW - pad*2, height: cellH - pad*2)),
            VNPath.roundedRect(VNRect(x: pad, y: pad,
                                      width: cellW - pad*2, height: cellH - pad*2),
                               cornerRadius: 6),
            VNPath.rect(VNRect(x: pad, y: pad,
                               width: cellW - pad*2, height: cellH - pad*2)),
            .diagonal(in: VNRect(x: pad, y: pad,
                                 width: cellW - pad*2, height: cellH - pad*2)),
            VNPath.ellipse(in: VNRect(x: pad, y: pad,
                                      width: cellW - pad*2, height: cellH - pad*2)),
            VNPath.roundedRect(VNRect(x: pad, y: pad,
                                      width: cellW - pad*2, height: cellH - pad*2),
                               cornerRadius: 12),
        ]
        let colors: [VNColor] = [
            VNColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1),
            VNColor(red: 0.4, green: 1.0, blue: 0.5, alpha: 1),
            VNColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1),
            VNColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 1),
            VNColor(red: 0.9, green: 0.4, blue: 1.0, alpha: 1),
            VNColor(red: 0.2, green: 1.0, blue: 0.9, alpha: 1),
        ]
        let widths: [Double] = [1.5, 2.0, 2.5, 1.5, 3.0, 2.0]

        for row in 0..<rows {
            for col in 0..<cols {
                let idx = row * cols + col
                let ox = Double(col) * cellW
                let oy = Double(row) * cellH
                context.saveGraphicsState()
                context.translateCTM(tx: ox, ty: oy)
                context.stroke(shapes[idx], color: colors[idx], lineWidth: widths[idx])
                context.restoreGraphicsState()
            }
        }
    }
}

// MARK: - VNPath helper for the diagonal demo shape

private extension VNPath {
    static func diagonal(in rect: VNRect) -> VNPath {
        var p = VNPath()
        p.move(to: VNPoint(x: rect.minX, y: rect.minY))
        p.line(to: VNPoint(x: rect.maxX, y: rect.maxY))
        p.move(to: VNPoint(x: rect.maxX, y: rect.minY))
        p.line(to: VNPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}
