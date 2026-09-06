import Testing
@testable import Vulpina

// MARK: - Isolated transparency group tests (M3c, W3C Compositing-1 §9.2)
//
// An isolated group starts with a transparent black backdrop.
// Backdrop-dependent operators applied as the first operation in a group
// therefore yield transparent results (no backdrop to interact with).
// The completed group is then composited onto the parent using the group's
// blend mode (sourceOver by default).

@Suite("TransparencyLayer")
struct TransparencyLayerTests {

    // 1×1 context helpers.
    private func ctx() -> VNGraphicsContext {
        VNGraphicsContext(widthPixels: 1, heightPixels: 1, backingScale: 1)
    }

    private func pixel(_ ctx: VNGraphicsContext) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        ctx.framebuffer.pixel(x: 0, y: 0)
    }

    // Tolerance for premultiplied round-trip (±1 LSB).
    private func near(_ a: UInt8, _ b: UInt8) -> Bool { abs(Int(a) - Int(b)) <= 1 }
    private func near(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8),
                      r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> Bool {
        near(p.r, r) && near(p.g, g) && near(p.b, b) && near(p.a, a)
    }

    // MARK: - Basic group pass-through

    @Test("Empty group leaves parent unchanged")
    func emptyGroupNoChange() {
        let c = ctx()
        // Paint the parent red (fully opaque).
        var rect = VNPath(windingRule: .nonZero)
        rect.move(to: VNPoint(x: 0, y: 0))
        rect.line(to: VNPoint(x: 1, y: 0))
        rect.line(to: VNPoint(x: 1, y: 1))
        rect.line(to: VNPoint(x: 0, y: 1))
        rect.close()
        c.fill(rect, color: VNColor(red: 1, green: 0, blue: 0, alpha: 1))

        c.beginTransparencyLayer()
        // Draw nothing in the layer.
        c.endTransparencyLayer()

        let p = pixel(c)
        // sourceOver of transparent layer onto opaque red → still red.
        #expect(near(p, r: 255, g: 0, b: 0, a: 255), "empty group changed parent pixel: \(p)")
    }

    @Test("Group with solid fill composites sourceOver onto parent")
    func solidFillSourceOver() {
        // Parent: opaque blue (0,0,255,255 premultiplied).
        // Group: opaque green (0,255,0,255) composited over blue → green wins.
        let c = ctx()
        var rect = VNPath(windingRule: .nonZero)
        rect.move(to: .zero); rect.line(to: VNPoint(x: 1, y: 0))
        rect.line(to: VNPoint(x: 1, y: 1)); rect.line(to: VNPoint(x: 0, y: 1)); rect.close()

        c.fill(rect, color: VNColor(red: 0, green: 0, blue: 1, alpha: 1))

        c.beginTransparencyLayer()
        c.fill(rect, color: VNColor(red: 0, green: 1, blue: 0, alpha: 1))
        c.endTransparencyLayer()

        let p = pixel(c)
        #expect(near(p, r: 0, g: 255, b: 0, a: 255), "sourceOver group failed: \(p)")
    }

    // MARK: - Isolated backdrop: backdrop-dependent operators

    @Test("sourceIn in empty group yields transparent (no backdrop)")
    func sourceInOnEmptyGroup() {
        // sourceIn = src × dstA. Inside an isolated group dstA=0, so result = 0.
        let c = ctx()
        var rect = VNPath(windingRule: .nonZero)
        rect.move(to: .zero); rect.line(to: VNPoint(x: 1, y: 0))
        rect.line(to: VNPoint(x: 1, y: 1)); rect.line(to: VNPoint(x: 0, y: 1)); rect.close()

        c.beginTransparencyLayer()
        c.fill(rect, color: VNColor(red: 1, green: 0, blue: 0, alpha: 1), blendMode: .sourceIn)
        c.endTransparencyLayer()

        // Layer is transparent → sourceOver of transparent onto parent → parent unchanged (0).
        let p = pixel(c)
        #expect(p.a == 0, "sourceIn on empty group should produce transparent layer, got alpha=\(p.a)")
    }

    @Test("destinationIn in empty group yields transparent (no backdrop)")
    func destinationInOnEmptyGroup() {
        let c = ctx()
        var rect = VNPath(windingRule: .nonZero)
        rect.move(to: .zero); rect.line(to: VNPoint(x: 1, y: 0))
        rect.line(to: VNPoint(x: 1, y: 1)); rect.line(to: VNPoint(x: 0, y: 1)); rect.close()

        c.beginTransparencyLayer()
        c.fill(rect, color: VNColor(red: 0, green: 1, blue: 0, alpha: 1), blendMode: .destinationIn)
        c.endTransparencyLayer()

        let p = pixel(c)
        #expect(p.a == 0, "destinationIn on empty group should yield transparent, got alpha=\(p.a)")
    }

    // MARK: - Group blend mode propagation

    @Test("Group composited with .copy replaces parent entirely")
    func groupBlendModeCopy() {
        let c = ctx()
        var rect = VNPath(windingRule: .nonZero)
        rect.move(to: .zero); rect.line(to: VNPoint(x: 1, y: 0))
        rect.line(to: VNPoint(x: 1, y: 1)); rect.line(to: VNPoint(x: 0, y: 1)); rect.close()

        // Parent: opaque red.
        c.fill(rect, color: VNColor(red: 1, green: 0, blue: 0, alpha: 1))

        // Group with .copy blend mode: half-alpha blue.
        // .copy ignores parent → output is just the layer pixel.
        // Layer has half-alpha blue (premultiplied): r=0, g=0, b=128, a=128.
        c.beginTransparencyLayer(blendMode: .copy)
        c.fill(rect, color: VNColor(red: 0, green: 0, blue: 1, alpha: 0.5))
        c.endTransparencyLayer()

        let p = pixel(c)
        // Premultiplied half-alpha blue: r≈0, g≈0, b≈128, a≈128.
        #expect(near(p, r: 0, g: 0, b: 127, a: 127), ".copy group blend failed: \(p)")
    }

    // MARK: - Nested groups

    @Test("Nested groups compose correctly")
    func nestedGroups() {
        // Outer group: sourceOver onto transparent parent.
        // Inner group: sourceOver onto outer's transparent start.
        // Inner draws opaque white → inner layer = white.
        // Inner composited into outer (sourceOver) → outer = white.
        // Outer composited into parent (sourceOver) → parent = white.
        let c = ctx()
        var rect = VNPath(windingRule: .nonZero)
        rect.move(to: .zero); rect.line(to: VNPoint(x: 1, y: 0))
        rect.line(to: VNPoint(x: 1, y: 1)); rect.line(to: VNPoint(x: 0, y: 1)); rect.close()

        c.beginTransparencyLayer()
            c.beginTransparencyLayer()
            c.fill(rect, color: VNColor(red: 1, green: 1, blue: 1, alpha: 1))
            c.endTransparencyLayer()
        c.endTransparencyLayer()

        let p = pixel(c)
        #expect(near(p, r: 255, g: 255, b: 255, a: 255), "nested group result wrong: \(p)")
    }

    // MARK: - Pixel values verified against W3C formula

    @Test("Half-alpha layer over opaque parent matches W3C sourceOver formula")
    func halfAlphaLayerPixelValue() {
        // Parent: opaque red (r=255, g=0, b=0, a=255) premultiplied.
        // Layer: half-alpha green (straight: r=0,g=1,b=0,a=0.5)
        //        premultiplied in layer: r=0, g=128, b=0, a=128.
        // sourceOver premultiplied:
        //   out.r = 0   + 255*(1-128/255) ≈ 255*(127/255) ≈ 127
        //   out.g = 128 + 0               = 128
        //   out.b = 0                     = 0
        //   out.a = 128 + 255*(127/255)   ≈ 128+127 = 255
        let c = ctx()
        var rect = VNPath(windingRule: .nonZero)
        rect.move(to: .zero); rect.line(to: VNPoint(x: 1, y: 0))
        rect.line(to: VNPoint(x: 1, y: 1)); rect.line(to: VNPoint(x: 0, y: 1)); rect.close()

        c.fill(rect, color: VNColor(red: 1, green: 0, blue: 0, alpha: 1))

        c.beginTransparencyLayer()
        c.fill(rect, color: VNColor(red: 0, green: 1, blue: 0, alpha: 0.5))
        c.endTransparencyLayer()

        let p = pixel(c)
        #expect(near(p, r: 127, g: 128, b: 0, a: 255),
                "half-alpha sourceOver pixel wrong: \(p)")
    }
}
