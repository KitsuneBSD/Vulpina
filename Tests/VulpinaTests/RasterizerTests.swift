import Testing
@testable import Vulpina

// MARK: - Helpers

private func ctx(w: Int, h: Int, scale: Double = 1) -> VNGraphicsContext {
    VNGraphicsContext(widthPixels: w, heightPixels: h, backingScale: scale)
}

// Alpha channel of pixel (x, y).
private func alpha(_ fb: VNFramebuffer, _ x: Int, _ y: Int) -> UInt8 {
    fb.pixel(x: x, y: y).a
}

// Red channel (for color checks).
private func red(_ fb: VNFramebuffer, _ x: Int, _ y: Int) -> UInt8 {
    fb.pixel(x: x, y: y).r
}

// MARK: - VNBlendMode

@Suite("VNBlendMode")
struct VNBlendModeTests {
    @Test func sourceOverOpaque() {
        // Opaque red over opaque blue → red (src wins fully).
        let (r, g, b, a) = VNPorterDuffBlitter.blend(
            srcR: 1, srcG: 0, srcB: 0, srcA: 1,
            dstR: 0, dstG: 0, dstB: 1, dstA: 1,
            coverage: 1, mode: .sourceOver)
        #expect(r == 1); #expect(g == 0); #expect(b == 0); #expect(a == 1)
    }

    @Test func sourceOverTransparent() {
        // Transparent src over blue → blue unchanged.
        let (r, _, b, a) = VNPorterDuffBlitter.blend(
            srcR: 1, srcG: 0, srcB: 0, srcA: 0,
            dstR: 0, dstG: 0, dstB: 1, dstA: 1,
            coverage: 1, mode: .sourceOver)
        #expect(r == 0); #expect(b == 1); #expect(a == 1)
    }

    @Test func clear() {
        let (r, g, b, a) = VNPorterDuffBlitter.blend(
            srcR: 1, srcG: 1, srcB: 1, srcA: 1,
            dstR: 1, dstG: 1, dstB: 1, dstA: 1,
            coverage: 1, mode: .clear)
        #expect(r == 0 && g == 0 && b == 0 && a == 0)
    }

    @Test func copy() {
        let (r, _, _, a) = VNPorterDuffBlitter.blend(
            srcR: 0.5, srcG: 0, srcB: 0, srcA: 0.5,
            dstR: 1, dstG: 1, dstB: 1, dstA: 1,
            coverage: 1, mode: .copy)
        // coverage 1, srcA=0.5 → premultiplied src: r=0.25
        #expect(abs(r - 0.25) < 0.001)
        #expect(abs(a - 0.5)  < 0.001)
    }

    @Test func halfCoverage() {
        // 50% coverage should act like 50% alpha.
        let (_, _, _, a) = VNPorterDuffBlitter.blend(
            srcR: 1, srcG: 0, srcB: 0, srcA: 1,
            dstR: 0, dstG: 0, dstB: 0, dstA: 0,
            coverage: 0.5, mode: .sourceOver)
        #expect(abs(a - 0.5) < 0.001)
    }
}

// MARK: - VNAffineTransform

@Suite("VNAffineTransform")
struct VNAffineTransformTests {
    @Test func identity() {
        let p = VNPoint(x: 3, y: 4)
        #expect(VNAffineTransform.identity.applying(to: p) == p)
    }

    @Test func translation() {
        let t = VNAffineTransform.translation(x: 10, y: -5)
        let p = t.applying(to: VNPoint(x: 1, y: 2))
        #expect(p.x == 11 && p.y == -3)
    }

    @Test func scale() {
        let t = VNAffineTransform.scale(x: 2, y: 3)
        let p = t.applying(to: VNPoint(x: 4, y: 5))
        #expect(p.x == 8 && p.y == 15)
    }

    @Test func concatenation() {
        // Translate then scale.
        let t = VNAffineTransform.translation(x: 1, y: 0)
            .concatenating(.scale(x: 2, y: 2))
        let p = t.applying(to: VNPoint(x: 0, y: 0))
        // translate → (1,0) → scale → (2,0)
        #expect(p.x == 2 && p.y == 0)
    }
}

// MARK: - VNFramebuffer

@Suite("VNFramebuffer")
struct VNFramebufferTests {
    @Test func initiallyTransparent() {
        let fb = VNFramebuffer(widthPixels: 4, heightPixels: 4)
        for y in 0..<4 { for x in 0..<4 { #expect(fb.pixel(x: x, y: y).a == 0) } }
    }

    @Test func setAndGetPixel() {
        var fb = VNFramebuffer(widthPixels: 2, heightPixels: 2)
        fb.setPixel(x: 1, y: 1, r: 255, g: 128, b: 64, a: 255)
        let p = fb.pixel(x: 1, y: 1)
        #expect(p.r == 255 && p.g == 128 && p.b == 64 && p.a == 255)
    }

    @Test func clear() {
        var fb = VNFramebuffer(widthPixels: 2, heightPixels: 2)
        fb.setPixel(x: 0, y: 0, r: 255, g: 255, b: 255, a: 255)
        fb.clear()
        #expect(fb.pixel(x: 0, y: 0).a == 0)
    }
}

// MARK: - VNPath

@Suite("VNPath")
struct VNPathTests {
    @Test func rectHelper() {
        let path = VNPath.rect(VNRect(x: 0, y: 0, width: 10, height: 10))
        // move + 3 lineTo + close = 5 elements
        #expect(path.elements.count == 5)
    }

    @Test func windingRule() {
        var p = VNPath(windingRule: .evenOdd)
        #expect(p.windingRule == .evenOdd)
        p.move(to: .zero)
        p.line(to: VNPoint(x: 1, y: 0))
        #expect(p.elements.count == 2)
    }
}

// MARK: - VNRasterizer (per-pixel coverage)

@Suite("VNRasterizer")
struct VNRasterizerTests {
    // ── Filled axis-aligned rectangle ──────────────────────────────────────

    @Test func filledRectInteriorPixels() {
        // Fill a 4×4 rect in an 8×8 framebuffer. Interior pixels must be fully opaque.
        let c = ctx(w: 8, h: 8)
        c.fill(.rect(VNRect(x: 1, y: 1, width: 6, height: 6)), color: .white)
        // In point space y-up, rect rows 1-7 map to pixel rows 1-7 (y-down flip).
        // Interior pixel (4, 4):
        #expect(alpha(c.framebuffer, 4, 4) > 250)
        // Corners outside the rect must be transparent.
        #expect(alpha(c.framebuffer, 0, 0) == 0)
        #expect(alpha(c.framebuffer, 7, 7) == 0)
    }

    @Test func filledRectCorrectColor() {
        let c = ctx(w: 4, h: 4)
        c.fill(.rect(VNRect(x: 0, y: 0, width: 4, height: 4)), color: .red)
        // Interior pixel should be red (premultiplied red with full alpha).
        let p = c.framebuffer.pixel(x: 2, y: 2)
        #expect(p.r > 250)
        #expect(p.g == 0)
        #expect(p.a > 250)
    }

    @Test func filledRectTransparentOutside() {
        let c = ctx(w: 8, h: 8)
        c.fill(.rect(VNRect(x: 2, y: 2, width: 4, height: 4)), color: .white)
        // Pixel (0,0) is outside.
        #expect(alpha(c.framebuffer, 0, 0) == 0)
        // Pixel (7,7) is outside.
        #expect(alpha(c.framebuffer, 7, 7) == 0)
    }

    // ── Right triangle (AA at hypotenuse) ──────────────────────────────────

    @Test func triangleHypotenuseCoverage() {
        // Triangle: (0,8)→(8,8)→(0,0)→close in an 8×8 buffer.
        // The pixel (1,6) in pixel space lies near the hypotenuse.
        var path = VNPath()
        path.move(to: VNPoint(x: 0, y: 0))
        path.line(to: VNPoint(x: 8, y: 0))
        path.line(to: VNPoint(x: 0, y: 8))
        path.close()
        let c = ctx(w: 8, h: 8)
        c.fill(path, color: .white)

        // The pixel at (0,0) in pixel space corresponds to point space (0, 7..8).
        // Deep interior pixel: (0, 7) in pixel space → should be fully covered.
        #expect(alpha(c.framebuffer, 0, 7) > 200)

        // Along the hypotenuse: partial coverage, between 0 and 255.
        let diagAlpha = alpha(c.framebuffer, 3, 3)
        #expect(diagAlpha > 0 && diagAlpha < 255)
    }

    // ── Source-over compositing ─────────────────────────────────────────────

    @Test func sourceOverCompositesCorrectly() {
        let c = ctx(w: 4, h: 4)
        // Fill blue first.
        c.fill(.rect(VNRect(x: 0, y: 0, width: 4, height: 4)), color: .blue)
        // Then source-over with 50% transparent white.
        c.fill(.rect(VNRect(x: 0, y: 0, width: 4, height: 4)),
               color: VNColor(red: 1, green: 1, blue: 1, alpha: 0.5))
        let p = c.framebuffer.pixel(x: 2, y: 2)
        // Should be a blend of blue and white — green channel > 0.
        #expect(p.g > 100)
        #expect(p.a > 250)
    }

    // ── HiDPI backing scale ─────────────────────────────────────────────────

    @Test func hiDPIScaleDoublesPixelCoverage() {
        // At 2× scale a 1-point rect maps to a 2×2 pixel area.
        let c = ctx(w: 8, h: 8, scale: 2)
        c.fill(.rect(VNRect(x: 1, y: 1, width: 2, height: 2)), color: .white)
        // Expected interior pixel at (3,3) in a 8×8 @2× context: points (1-3)×(1-3)
        // → pixels (2-6)×(2-6). Pixel (3,3) should be inside.
        #expect(alpha(c.framebuffer, 3, 3) > 200)
    }

    // ── Save / restore state ────────────────────────────────────────────────

    @Test func saveRestorePreservesTransform() {
        let c = ctx(w: 8, h: 8)
        c.saveGraphicsState()
        c.translateCTM(tx: 100, ty: 100)  // crazy translate
        c.restoreGraphicsState()
        // After restore, drawing at (0,0) should hit pixel (0, h-1).
        c.fill(.rect(VNRect(x: 0, y: 0, width: 2, height: 2)), color: .white)
        // At scale=1, point (0,0)=(bottom-left) → pixel (0, h-1)=top... wait.
        // point (0,7)→pixel(0,0); point(0,0)→pixel(0,8). Rect (0,0)→(2,2) in points
        // → pixels x[0,2), y[6,8). Pixel (0,6) or (1,7) should be covered.
        #expect(alpha(c.framebuffer, 0, 7) > 0)
    }
}
