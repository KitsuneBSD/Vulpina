import Testing
import Foundation
@testable import Vulpina

// MARK: - Helpers

private final class CaptureSurface: VNSurface {
    var lastFramebuffer: VNFramebuffer?
    var onNeedsRedraw: (@MainActor () -> Void)? = nil
    @MainActor func present(_ fb: VNFramebuffer) { lastFramebuffer = fb }
}

/// Saves `fb` composited over a white background to a PPM file in /tmp.
/// Transparent pixels become white. Files are for visual inspection only.
private func savePPM(_ fb: VNFramebuffer, name: String) {
    let dir = "/tmp/vulpina_integration"
    try? FileManager.default.createDirectory(atPath: dir,
                                             withIntermediateDirectories: true)
    var data = "P6\n\(fb.widthPixels) \(fb.heightPixels)\n255\n"
        .data(using: .utf8)!
    let count = fb.widthPixels * fb.heightPixels
    var rgb = [UInt8](repeating: 0, count: count * 3)
    for i in 0..<count {
        let o = i * 4
        let r = Int(fb.bytes[o]), g = Int(fb.bytes[o+1])
        let b = Int(fb.bytes[o+2]), a = Int(fb.bytes[o+3])
        // Composite premultiplied RGBA over white.
        rgb[i*3]   = UInt8(r + (255 - a))
        rgb[i*3+1] = UInt8(g + (255 - a))
        rgb[i*3+2] = UInt8(b + (255 - a))
    }
    data.append(contentsOf: rgb)
    let path = "\(dir)/\(name).ppm"
    try? data.write(to: URL(fileURLWithPath: path))
}

/// Returns RGBA of pixel (x, y) as floats in [0, 1] (straight alpha, over white).
private func pixel(_ fb: VNFramebuffer, x: Int, y: Int)
    -> (r: Double, g: Double, b: Double, a: Double)
{
    let p = fb.pixel(x: x, y: y)
    let a = Double(p.a) / 255
    guard a > 0 else { return (1, 1, 1, 0) }   // transparent → white
    return (Double(p.r) / 255 / a,
            Double(p.g) / 255 / a,
            Double(p.b) / 255 / a, a)
}

// MARK: - Demo scenes

/// Creates a VNWindow with the given size (scale 1) backed by a CaptureSurface.
@MainActor
private func makeWindow(width: Double, height: Double) -> (VNWindow, CaptureSurface) {
    let surface = CaptureSurface()
    let win = VNWindow(surface: surface,
                       sizePoints: VNSize(width: width, height: height),
                       backingScale: 1)
    return (win, surface)
}

// MARK: - Integration suite

@Suite("Integration — render demos")
struct IntegrationTests {

    // MARK: Scene 1: layered color blocks

    @Test @MainActor func colorBlocksLayout() {
        // 60×40 window, three non-overlapping horizontal bands:
        // top    band (y 20..40): red    — frame (0, 20, 60, 20) bottom-left
        // middle band (y 10..20): green  — frame (0, 10, 60, 10)
        // bottom band (y  0..10): blue   — frame (0,  0, 60, 10)
        let (win, surface) = makeWindow(width: 60, height: 40)

        final class Band: VNView {
            let c: VNColor
            init(frame: VNRect, color: VNColor) { c = color; super.init(frame: frame) }
            override func draw(_ ctx: VNGraphicsContext) {
                ctx.fill(VNPath.rect(bounds), color: c)
            }
        }

        win.contentView.addSubview(Band(frame: VNRect(x: 0, y: 20, width: 60, height: 20),
                                       color: VNColor(red: 1, green: 0, blue: 0, alpha: 1)))
        win.contentView.addSubview(Band(frame: VNRect(x: 0, y: 10, width: 60, height: 10),
                                       color: VNColor(red: 0, green: 1, blue: 0, alpha: 1)))
        win.contentView.addSubview(Band(frame: VNRect(x: 0, y: 0,  width: 60, height: 10),
                                       color: VNColor(red: 0, green: 0, blue: 1, alpha: 1)))
        win.display()

        let fb = surface.lastFramebuffer!
        savePPM(fb, name: "01_color_blocks")

        // Pixel-space: window height 40, y-down.
        // Red band   y=20..40 → pixel row 0..19   → sample at pixel row 5, x=30
        // Green band y=10..20 → pixel row 20..29  → sample at pixel row 25, x=30
        // Blue band  y=0..10  → pixel row 30..39  → sample at pixel row 35, x=30

        let red   = pixel(fb, x: 30, y: 5)
        let green = pixel(fb, x: 30, y: 25)
        let blue  = pixel(fb, x: 30, y: 35)

        #expect(red.r   > 0.9 && red.g   < 0.1, "top band should be red")
        #expect(green.g > 0.9 && green.r < 0.1, "middle band should be green")
        #expect(blue.b  > 0.9 && blue.r  < 0.1, "bottom band should be blue")
    }

    // MARK: Scene 2: nested subviews + z-order

    @Test @MainActor func nestedSubviewsZOrder() {
        // 40×40 window.
        // Layer 0 (back): white background filling the whole window.
        // Layer 1: red  20×20 square at (0, 20) — top-left in point space.
        // Layer 2: blue 20×20 square at (20, 20) — top-right.
        // Layer 3 (top): yellow 40×10 strip at (0, 15) — overlaps both.
        // Expected: yellow wins at y=15..25 (pixel rows 15..25 flipped).
        let (win, surface) = makeWindow(width: 40, height: 40)

        final class Solid: VNView {
            let c: VNColor
            init(frame: VNRect, color: VNColor) { c = color; super.init(frame: frame) }
            override func draw(_ ctx: VNGraphicsContext) {
                ctx.fill(VNPath.rect(bounds), color: c)
            }
        }

        let white  = VNColor(red: 1, green: 1, blue: 1, alpha: 1)
        let red    = VNColor(red: 1, green: 0, blue: 0, alpha: 1)
        let blue   = VNColor(red: 0, green: 0, blue: 1, alpha: 1)
        let yellow = VNColor(red: 1, green: 1, blue: 0, alpha: 1)

        win.contentView.addSubview(Solid(frame: VNRect(x:  0, y:  0, width: 40, height: 40), color: white))
        win.contentView.addSubview(Solid(frame: VNRect(x:  0, y: 20, width: 20, height: 20), color: red))
        win.contentView.addSubview(Solid(frame: VNRect(x: 20, y: 20, width: 20, height: 20), color: blue))
        win.contentView.addSubview(Solid(frame: VNRect(x:  0, y: 15, width: 40, height: 10), color: yellow))
        win.display()

        let fb = surface.lastFramebuffer!
        savePPM(fb, name: "02_nested_zorder")

        // Yellow strip: y=15..25 in points → pixel rows 15..24 (y-flipped: row = 40-y-1 roughly).
        // Center of yellow strip → pixel row ~17, x=20.
        let yp = pixel(fb, x: 20, y: 17)
        #expect(yp.r > 0.9 && yp.g > 0.9 && yp.b < 0.1, "yellow strip on top: \(yp)")

        // Above yellow (red quadrant): pixel row ~5, x=10.
        let rp = pixel(fb, x: 10, y: 5)
        #expect(rp.r > 0.9 && rp.b < 0.1, "red quadrant: \(rp)")

        // Above yellow (blue quadrant): pixel row ~5, x=30.
        let bp = pixel(fb, x: 30, y: 5)
        #expect(bp.b > 0.9 && bp.r < 0.1, "blue quadrant: \(bp)")
    }

    // MARK: Scene 3: circles and strokes

    @Test @MainActor func circlesAndStrokes() {
        // 80×80 window.
        // Dark background + red filled circle at center + white stroke outline.
        let (win, surface) = makeWindow(width: 80, height: 80)

        final class CircleScene: VNView {
            override func draw(_ ctx: VNGraphicsContext) {
                // Dark background
                ctx.fill(VNPath.rect(bounds),
                         color: VNColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
                // Red filled circle at (40, 40) r=25
                ctx.fill(VNPath.ellipse(in: VNRect(x: 15, y: 15, width: 50, height: 50)),
                         color: VNColor(red: 0.9, green: 0.15, blue: 0.1, alpha: 1))
                // White stroke around circle
                ctx.stroke(VNPath.ellipse(in: VNRect(x: 15, y: 15, width: 50, height: 50)),
                           color: VNColor(red: 1, green: 1, blue: 1, alpha: 1),
                           lineWidth: 2)
            }
        }

        win.contentView.addSubview(CircleScene(frame: VNRect(x: 0, y: 0, width: 80, height: 80)))
        win.display()

        let fb = surface.lastFramebuffer!
        savePPM(fb, name: "03_circles_strokes")

        // Center pixel should be red (inside filled circle).
        let center = pixel(fb, x: 40, y: 40)
        #expect(center.r > 0.7 && center.g < 0.3, "center should be red: \(center)")
        #expect(center.a > 0.9, "center should be opaque")

        // Corner pixel should be dark background.
        let corner = pixel(fb, x: 2, y: 2)
        #expect(corner.r < 0.3 && corner.a > 0.9, "corner should be dark: \(corner)")
    }

    // MARK: Scene 4: transparency group compositing

    @Test @MainActor func transparencyGroupCompositing() {
        // 40×40 window.
        // A view that uses beginTransparencyLayer to blend a semi-transparent
        // green overlay over a red background.
        let (win, surface) = makeWindow(width: 40, height: 40)

        final class GroupScene: VNView {
            override func draw(_ ctx: VNGraphicsContext) {
                // Red base
                ctx.fill(VNPath.rect(bounds),
                         color: VNColor(red: 1, green: 0, blue: 0, alpha: 1))
                // Semi-transparent green in an isolated group
                ctx.beginTransparencyLayer()
                ctx.fill(VNPath.rect(VNRect(x: 10, y: 10, width: 20, height: 20)),
                         color: VNColor(red: 0, green: 1, blue: 0, alpha: 0.5))
                ctx.endTransparencyLayer()
            }
        }

        win.contentView.addSubview(GroupScene(frame: VNRect(x: 0, y: 0, width: 40, height: 40)))
        win.display()

        let fb = surface.lastFramebuffer!
        savePPM(fb, name: "04_transparency_group")

        // Center (20, 20) in bounds → pixel (20, 19) flipped in 40-px window.
        // Over red, 50% green → blended: r ≈ 0.5, g ≈ 0.5.
        let center = pixel(fb, x: 20, y: 20)
        #expect(center.r > 0.3 && center.r < 0.7, "mixed red: \(center.r)")
        #expect(center.g > 0.3 && center.g < 0.7, "mixed green: \(center.g)")

        // Corner stays pure red.
        let corner = pixel(fb, x: 2, y: 2)
        #expect(corner.r > 0.9 && corner.g < 0.1, "corner is pure red: \(corner)")
    }

    // MARK: Scene 5: HiDPI @2x scale

    @Test @MainActor func hiDPIScale() {
        // 20×20 points, @2x → 40×40 pixels.
        // Blue view fills the right half in points (x=10..20).
        // In pixels, right half = columns 20..39.
        let surface = CaptureSurface()
        let win = VNWindow(surface: surface,
                           sizePoints: VNSize(width: 20, height: 20),
                           backingScale: 2)

        final class Half: VNView {
            override func draw(_ ctx: VNGraphicsContext) {
                ctx.fill(VNPath.rect(bounds),
                         color: VNColor(red: 0, green: 0, blue: 1, alpha: 1))
            }
        }

        win.contentView.addSubview(Half(frame: VNRect(x: 10, y: 0, width: 10, height: 20)))
        win.display()

        let fb = surface.lastFramebuffer!
        savePPM(fb, name: "05_hidpi_2x")

        // fb is 40×40 pixels.
        #expect(fb.widthPixels == 40 && fb.heightPixels == 40)

        // Left half (columns 0..19) transparent.
        #expect(fb.pixel(x: 10, y: 20).a == 0, "left half transparent")

        // Right half (columns 20..39) blue.
        let p = fb.pixel(x: 30, y: 20)
        #expect(p.b > 200 && p.a > 200, "right half blue: b=\(p.b) a=\(p.a)")
    }

    // MARK: Scene 6: rounded rect + compositing

    @Test @MainActor func roundedRectCard() {
        // 60×60 window. A "card" UI element: white rounded rect on dark background.
        let (win, surface) = makeWindow(width: 60, height: 60)

        final class Card: VNView {
            override func draw(_ ctx: VNGraphicsContext) {
                // Dark background
                ctx.fill(VNPath.rect(bounds),
                         color: VNColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1))
                // White card with rounded corners
                ctx.fill(VNPath.roundedRect(VNRect(x: 8, y: 8, width: 44, height: 44),
                                            cornerRadius: 8),
                         color: VNColor(red: 1, green: 1, blue: 1, alpha: 0.9))
                // Accent stroke
                ctx.stroke(VNPath.roundedRect(VNRect(x: 8, y: 8, width: 44, height: 44),
                                              cornerRadius: 8),
                           color: VNColor(red: 0.4, green: 0.6, blue: 1, alpha: 1),
                           lineWidth: 1.5)
            }
        }

        win.contentView.addSubview(Card(frame: VNRect(x: 0, y: 0, width: 60, height: 60)))
        win.display()

        let fb = surface.lastFramebuffer!
        savePPM(fb, name: "06_rounded_card")

        // Center of card should be near-white.
        let center = pixel(fb, x: 30, y: 30)
        #expect(center.r > 0.85 && center.g > 0.85 && center.b > 0.85,
                "card center should be white: \(center)")

        // Corner of window should be dark background (outside the rounded rect).
        let corner = pixel(fb, x: 2, y: 2)
        #expect(corner.r < 0.4 && corner.a > 0.9,
                "window corner should be dark: \(corner)")
    }
}
