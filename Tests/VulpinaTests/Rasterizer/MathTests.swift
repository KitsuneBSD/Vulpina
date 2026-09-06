// Mathematical invariance tests for the Vulpina rasterizer.
//
// These verify quantitative properties: coverage sums, area conservation,
// Porter-Duff identities, winding accumulation, and transform correctness.

import Testing
import Foundation
@testable import Vulpina

// MARK: - Helpers

/// Sum of all alpha values in the framebuffer, normalised to [0, 1] per pixel.
private func totalCoverage(_ fb: VNFramebuffer) -> Double {
    var sum = 0.0
    for i in stride(from: 3, to: fb.bytes.count, by: 4) {
        sum += Double(fb.bytes[i]) / 255.0
    }
    return sum
}

/// Sum of alpha for a single row of pixels (y in pixel-space).
private func rowCoverage(_ fb: VNFramebuffer, y: Int) -> Double {
    var sum = 0.0
    for x in 0..<fb.widthPixels {
        sum += Double(fb.pixel(x: x, y: y).a) / 255.0
    }
    return sum
}

/// Sum of alpha for a single column of pixels.
private func colCoverage(_ fb: VNFramebuffer, x: Int) -> Double {
    var sum = 0.0
    for y in 0..<fb.heightPixels {
        sum += Double(fb.pixel(x: x, y: y).a) / 255.0
    }
    return sum
}

/// Alpha of pixel (x, y) normalised to [0, 1].
private func alpha(_ fb: VNFramebuffer, _ x: Int, _ y: Int) -> Double {
    Double(fb.pixel(x: x, y: y).a) / 255.0
}

private func ctx(_ w: Int, _ h: Int, scale: Double = 1) -> VNGraphicsContext {
    VNGraphicsContext(widthPixels: w, heightPixels: h, backingScale: scale)
}

// MARK: - areaToLeft (internal, unit-tested directly)

@Suite("areaToLeft formula")
struct AreaToLeftTests {
    // Edge at pixel's left boundary (u=0): no area to the left.
    @Test func edgeAtLeftBoundary() {
        let area = VNAnalyticScanConverter._areaToLeft(u0: 0, u1: 0, H: 1)
        #expect(area == 0)
    }

    // Edge at pixel's right boundary (u=1): full area to the left.
    @Test func edgeAtRightBoundary() {
        let area = VNAnalyticScanConverter._areaToLeft(u0: 1, u1: 1, H: 1)
        #expect(abs(area - 1) < 1e-12)
    }

    // Edge at pixel's center (u=0.5): half area.
    @Test func edgeAtCenter() {
        let area = VNAnalyticScanConverter._areaToLeft(u0: 0.5, u1: 0.5, H: 1)
        #expect(abs(area - 0.5) < 1e-12)
    }

    // Edge entirely to the left (u < 0): zero area.
    @Test func edgeLeftOfPixel() {
        let area = VNAnalyticScanConverter._areaToLeft(u0: -2, u1: -2, H: 1)
        #expect(area == 0)
    }

    // Edge entirely to the right (u > 1): full area.
    @Test func edgeRightOfPixel() {
        let area = VNAnalyticScanConverter._areaToLeft(u0: 3, u1: 3, H: 1)
        #expect(abs(area - 1) < 1e-12)
    }

    // Diagonal from left to right (u0=0, u1=1): triangle = 0.5.
    @Test func diagonalLeftToRight() {
        let area = VNAnalyticScanConverter._areaToLeft(u0: 0, u1: 1, H: 1)
        #expect(abs(area - 0.5) < 1e-12)
    }

    // Diagonal from right to left (u0=1, u1=0): same triangle = 0.5.
    @Test func diagonalRightToLeft() {
        let area = VNAnalyticScanConverter._areaToLeft(u0: 1, u1: 0, H: 1)
        #expect(abs(area - 0.5) < 1e-12)
    }

    // Partial crossing: u0=-0.5, u1=0.5 (edge enters from left, exits at centre).
    // Integral of clamp(−0.5 + v, 0, 1) from v=0 to v=1:
    //   u=0 at v=0.5 → integral from 0.5 to 1 of (v − 0.5) dv = [v²/2 − 0.5v]_0.5^1
    //   = (0.5 − 0.5) − (0.125 − 0.25) = 0 − (−0.125) = 0.125
    @Test func partialCrossFromLeft() {
        let area = VNAnalyticScanConverter._areaToLeft(u0: -0.5, u1: 0.5, H: 1)
        #expect(abs(area - 0.125) < 1e-12)
    }

    // Partial crossing: u0=0.5, u1=1.5 (edge enters at centre, exits right).
    // Integral of clamp(0.5 + v × 1, 0, 1) from 0 to 1, where u(v) = 0.5 + v*0.5... wait:
    // u(v) = 0.5 + v*(1.5-0.5)/1 = 0.5 + v. At v=0.5: u=1.
    // ∫₀¹ clamp(0.5+v, 0, 1) dv = ∫₀^0.5 (0.5+v)dv + ∫₀.₅¹ 1 dv
    //   = [0.5v + v²/2]_0^0.5 + 0.5 = (0.25 + 0.125) + 0.5 = 0.875
    @Test func partialCrossToRight() {
        let area = VNAnalyticScanConverter._areaToLeft(u0: 0.5, u1: 1.5, H: 1)
        #expect(abs(area - 0.875) < 1e-12)
    }

    // Zero height: no area regardless of u.
    @Test func zeroHeight() {
        #expect(VNAnalyticScanConverter._areaToLeft(u0: 0.5, u1: 0.5, H: 0) == 0)
    }
}

// MARK: - Area conservation (fill)

@Suite("Area conservation")
struct AreaConservationTests {
    // Pixel-aligned filled rect: total coverage must equal exact geometric area.
    @Test func pixelAlignedRectExact() {
        let c = ctx(16, 16)
        // Rect from (2,2) to (14,14) in point space = 12×12 = 144 px area.
        c.fill(.rect(VNRect(x: 2, y: 2, width: 12, height: 12)), color: .white)
        let total = totalCoverage(c.framebuffer)
        #expect(abs(total - 144) < 0.5, "Expected ≈144, got \(total)")
    }

    // Half-pixel offset: total coverage must still be ≈ geometric area.
    @Test func halfPixelOffsetRectArea() {
        let c = ctx(16, 16)
        // Rect from (1.5, 1.5) to (14.5, 14.5) = 13×13 = 169 px.
        c.fill(.rect(VNRect(x: 1.5, y: 1.5, width: 13, height: 13)), color: .white)
        let total = totalCoverage(c.framebuffer)
        #expect(abs(total - 169) < 1.0, "Expected ≈169, got \(total)")
    }

    // Thin 1px-wide horizontal strip at half-pixel boundary: coverage ≈ width.
    @Test func thinHorizontalStripArea() {
        let c = ctx(32, 8)
        // Strip from x=0..32, y=3.5..4.5 (1 point tall, crossing pixel boundary)
        c.fill(.rect(VNRect(x: 0, y: 3.5, width: 32, height: 1)), color: .white)
        // Each of the two pixel rows that the strip spans gets ~0.5 coverage per pixel.
        // Total ≈ 32 * 1 = 32.
        let total = totalCoverage(c.framebuffer)
        #expect(abs(total - 32) < 1.0, "Expected ≈32, got \(total)")
    }

    // Ellipse area ≈ π·r² (end-to-end, not just flattener test).
    @Test func ellipseFillArea() {
        let r = 30.0
        let c = ctx(80, 80)
        c.fill(.ellipse(in: VNRect(x: 10, y: 10, width: 2*r, height: 2*r)), color: .white)
        let total = totalCoverage(c.framebuffer)
        let expected = Double.pi * r * r
        let error = abs(total - expected) / expected
        #expect(error < 0.01, "Ellipse area error \(error*100)% > 1%")
    }

    // HiDPI @2x: same point-space rect should cover 4× as many pixel-area units.
    @Test func hiDPIAreaScales() {
        let c1 = ctx(32, 32, scale: 1)
        let c2 = ctx(64, 64, scale: 2)
        c1.fill(.rect(VNRect(x: 4, y: 4, width: 8, height: 8)), color: .white)
        c2.fill(.rect(VNRect(x: 4, y: 4, width: 8, height: 8)), color: .white)
        let a1 = totalCoverage(c1.framebuffer)
        let a2 = totalCoverage(c2.framebuffer)
        // @2x covers 4× the pixels.
        #expect(abs(a2 / a1 - 4) < 0.1, "HiDPI ratio \(a2/a1) ≠ 4")
    }
}

// MARK: - Anti-aliasing edge correctness

@Suite("AA edge coverage")
struct AAEdgeCoverageTests {
    // A rect shifted by 0.5px should make two edge pixel rows each have ≈0.5 total.
    @Test func halfPixelEdgeCoverage() {
        let c = ctx(8, 8)
        // Fill points y ∈ [2.5, 5.5] (height 3).
        // Pixel space (y-down, height=8): py = 8 - y_point.
        //   point y=5.5 → py=2.5  →  top edge is mid-way through pixel row 2
        //   point y=2.5 → py=5.5  →  bottom edge is mid-way through pixel row 5
        // Row py=2 (top boundary, half-covered): row total ≈ 4
        // Rows py=3,4 (interior):               row total ≈ 8
        // Row py=5 (bottom boundary, half-covered): row total ≈ 4
        c.fill(.rect(VNRect(x: 0, y: 2.5, width: 8, height: 3)), color: .white)
        #expect(abs(rowCoverage(c.framebuffer, y: 2) - 4) < 0.5)
        #expect(abs(rowCoverage(c.framebuffer, y: 3) - 8) < 0.2)
        #expect(abs(rowCoverage(c.framebuffer, y: 4) - 8) < 0.2)
        #expect(abs(rowCoverage(c.framebuffer, y: 5) - 4) < 0.5)
        #expect(rowCoverage(c.framebuffer, y: 6) < 0.1)
    }

    // A 45° right-triangle: coverage per row increases linearly toward the full base.
    @Test func diagonalEdgeCoverageMonotone() {
        // Triangle (0,0)→(8,0)→(0,8) in point space (y-up).
        // In pixel space (y-down, height=8):
        //   (0,0)→py=8, (8,0)→py=8, (0,8)→py=0
        //   → pixel-space vertices: (0,8),(8,8),(0,0) — lower-left triangle.
        // Row py=0 has a tiny sliver near (0,0); row py=7 spans almost the full width.
        // Coverage INCREASES from top (py=0) to bottom (py=7).
        var path = VNPath()
        path.move(to: VNPoint(x: 0, y: 0))
        path.line(to: VNPoint(x: 8, y: 0))
        path.line(to: VNPoint(x: 0, y: 8))
        path.close()
        let c = ctx(8, 8)
        c.fill(path, color: .white)
        var prevRow = rowCoverage(c.framebuffer, y: 0)
        for py in 1..<8 {
            let r = rowCoverage(c.framebuffer, y: py)
            #expect(r >= prevRow - 0.1, "Row \(py) coverage \(r) decreased unexpectedly from \(prevRow)")
            prevRow = r
        }
    }

    // A vertical edge at x=4.5 should split neighbouring pixels ~50/50.
    @Test func verticalEdgeHalfSplit() {
        let c = ctx(8, 8)
        // Rect from x=0..4.5, full height.
        c.fill(.rect(VNRect(x: 0, y: 0, width: 4.5, height: 8)), color: .white)
        // Column 4 (px=[4,5]): 0.5 coverage per pixel → total col ≈ 4.
        #expect(abs(colCoverage(c.framebuffer, x: 4) - 4) < 0.3)
        // Column 3 (px=[3,4]): fully inside → total col ≈ 8.
        #expect(abs(colCoverage(c.framebuffer, x: 3) - 8) < 0.2)
        // Column 5: fully outside → 0.
        #expect(colCoverage(c.framebuffer, x: 5) < 0.1)
    }
}

// MARK: - Winding rule mathematics

@Suite("Winding rule")
struct WindingRuleTests {
    // Two overlapping same-winding rects with non-zero: overlap is NOT double-counted.
    @Test func nonZeroOverlapNotDoubled() {
        let c = ctx(16, 16)
        var path = VNPath(windingRule: .nonZero)
        // Two identical rects → winding=2 in interior, but coverage clamps to 1.
        path.appendPath(.rect(VNRect(x: 2, y: 2, width: 12, height: 12)))
        path.appendPath(.rect(VNRect(x: 2, y: 2, width: 12, height: 12)))
        c.fill(path, color: .white)
        // Interior pixel must be exactly 1.0, not 2.0.
        #expect(alpha(c.framebuffer, 8, 8) > 0.99)
        // Same total area as a single rect (no double-fill through 8-bit clamping).
        let total = totalCoverage(c.framebuffer)
        #expect(abs(total - 144) < 0.5, "Expected ≈144, got \(total)")
    }

    // Even-odd: two overlapping same-winding rects → overlap gets 0 coverage.
    @Test func evenOddOverlapCancels() {
        let c = ctx(16, 16)
        var path = VNPath(windingRule: .evenOdd)
        // Outer rect 12×12, inner rect 6×6 centred (same winding, overlap = inner).
        path.appendPath(.rect(VNRect(x: 2, y: 2, width: 12, height: 12)))
        path.appendPath(.rect(VNRect(x: 5, y: 5, width: 6,  height: 6)))
        c.fill(path, color: .white)
        // Center of inner rect: even-odd → winding 2 → coverage 0.
        #expect(alpha(c.framebuffer, 8, 8) < 0.05)
        // Ring (inside outer, outside inner): winding 1 → covered.
        #expect(alpha(c.framebuffer, 3, 3) > 0.9)
    }

    // Even-odd: triple nesting → outer and inner covered, middle not.
    @Test func evenOddTripleNesting() {
        let c = ctx(20, 20)
        var path = VNPath(windingRule: .evenOdd)
        path.appendPath(.rect(VNRect(x: 1, y: 1, width: 18, height: 18)))  // winding 1
        path.appendPath(.rect(VNRect(x: 4, y: 4, width: 12, height: 12)))  // winding 2 inside
        path.appendPath(.rect(VNRect(x: 7, y: 7, width:  6, height:  6)))  // winding 3 inside
        c.fill(path, color: .white)
        // Outermost ring: odd → covered.
        #expect(alpha(c.framebuffer, 2, 2) > 0.9)
        // Middle ring: even → NOT covered.
        #expect(alpha(c.framebuffer, 5, 5) < 0.1)
        // Innermost: odd → covered.
        #expect(alpha(c.framebuffer, 10, 10) > 0.9)
    }
}

// MARK: - Porter-Duff identities

@Suite("Porter-Duff identities")
struct PorterDuffIdentityTests {
    // source-over: A over transparent = A (identity for transparent dst).
    @Test func sourceOverTransparentDst() {
        let (r, _, _, a) = VNPorterDuffBlitter.blend(
            srcR: 0.8, srcG: 0.3, srcB: 0.1, srcA: 0.7,
            dstR: 0,   dstG: 0,   dstB: 0,   dstA: 0,
            coverage: 1, mode: .sourceOver)
        // premultiplied src: r=0.8*0.7=0.56, a=0.7
        #expect(abs(r - 0.56) < 0.001)
        #expect(abs(a - 0.7)  < 0.001)
    }

    // source-over: opaque src completely covers any dst.
    @Test func sourceOverOpaqueSrcCoversAll() {
        let (r, _, b, a) = VNPorterDuffBlitter.blend(
            srcR: 1, srcG: 0, srcB: 0, srcA: 1,
            dstR: 0, dstG: 0, dstB: 1, dstA: 1,
            coverage: 1, mode: .sourceOver)
        #expect(abs(r - 1) < 0.001)
        #expect(abs(b - 0) < 0.001)
        #expect(abs(a - 1) < 0.001)
    }

    // source-over: zero coverage leaves dst unchanged.
    @Test func sourceOverZeroCoverageNoop() {
        let dR = 0.3, dG = 0.5, dB = 0.7, dA = 0.9
        let (r, g, b, a) = VNPorterDuffBlitter.blend(
            srcR: 1, srcG: 0, srcB: 0, srcA: 1,
            dstR: Float(dR), dstG: Float(dG), dstB: Float(dB), dstA: Float(dA),
            coverage: 0, mode: .sourceOver)
        #expect(abs(Double(r) - dR) < 0.001)
        #expect(abs(Double(g) - dG) < 0.001)
        #expect(abs(Double(b) - dB) < 0.001)
        #expect(abs(Double(a) - dA) < 0.001)
    }

    // destination-over: A dst-over transparent src = A.
    @Test func destinationOverWithTransparentSrc() {
        let (r, _, _, a) = VNPorterDuffBlitter.blend(
            srcR: 1, srcG: 0, srcB: 0, srcA: 0,
            dstR: 0, dstG: 0, dstB: 1, dstA: 1,
            coverage: 1, mode: .destinationOver)
        #expect(abs(r - 0) < 0.001)
        #expect(abs(a - 1) < 0.001)
    }

    // xor: opaque A xor opaque B → both regions cancel (result is transparent where both overlap).
    @Test func xorOpaqueOnOpaque() {
        let (_, _, _, a) = VNPorterDuffBlitter.blend(
            srcR: 1, srcG: 0, srcB: 0, srcA: 1,
            dstR: 0, dstG: 0, dstB: 1, dstA: 1,
            coverage: 1, mode: .xor)
        // xor of two opaque: (srcA*(1-dstA) + dstA*(1-srcA)) = 0 + 0 = 0 when both opaque.
        #expect(a < 0.001)
    }

    // plus-lighter: channels must not exceed 1.
    @Test func plusLighterClampedToOne() {
        let (r, g, b, a) = VNPorterDuffBlitter.blend(
            srcR: 1, srcG: 1, srcB: 1, srcA: 1,
            dstR: 1, dstG: 1, dstB: 1, dstA: 1,
            coverage: 1, mode: .plusLighter)
        #expect(r <= 1 && g <= 1 && b <= 1 && a <= 1)
    }

    // source-over alpha formula: a_out = src_a + dst_a*(1 - src_a)
    @Test func sourceOverAlphaFormula() {
        // src_a=0.6 (straight), dst_a=0.5 (premult already 0.5).
        // expected a_out = 0.6 + 0.5*(1-0.6) = 0.6 + 0.2 = 0.8
        let (_, _, _, a) = VNPorterDuffBlitter.blend(
            srcR: 1, srcG: 0, srcB: 0, srcA: 0.6,
            dstR: 0, dstG: 0, dstB: 0.5, dstA: 0.5,
            coverage: 1, mode: .sourceOver)
        #expect(abs(a - 0.8) < 0.001, "Expected 0.8, got \(a)")
    }

    // source-in: result alpha = src_a * dst_a.
    @Test func sourceInAlphaIsProduct() {
        let (_, _, _, a) = VNPorterDuffBlitter.blend(
            srcR: 1, srcG: 0, srcB: 0, srcA: 0.8,
            dstR: 0, dstG: 0, dstB: 1, dstA: 0.5,
            coverage: 1, mode: .sourceIn)
        // effective sa = 0.8*cov=0.8; result.a = sa*dstA = 0.8*0.5 = 0.4
        #expect(abs(a - 0.4) < 0.001)
    }
}

// MARK: - Transform mathematics

@Suite("Transform mathematics")
struct TransformMathTests {
    // Scale by 2: covered pixel area increases by 4.
    @Test func scaleDoublesCoverageByFour() {
        let c1 = ctx(32, 32)
        let c2 = ctx(32, 32)
        c1.fill(.rect(VNRect(x: 8, y: 8, width: 8, height: 8)), color: .white)
        c2.saveGraphicsState()
        c2.scaleCTM(sx: 2, sy: 2)
        c2.fill(.rect(VNRect(x: 4, y: 4, width: 4, height: 4)), color: .white)
        c2.restoreGraphicsState()
        let a1 = totalCoverage(c1.framebuffer)
        let a2 = totalCoverage(c2.framebuffer)
        #expect(abs(a1 - a2) < 0.5, "Scale 2× should give same pixel area: \(a1) vs \(a2)")
    }

    // Translate: exact same pixels as drawing at the translated position.
    @Test func translateEquivalentToOffsetRect() {
        let c1 = ctx(16, 16)
        let c2 = ctx(16, 16)
        c1.fill(.rect(VNRect(x: 5, y: 5, width: 6, height: 6)), color: .white)
        c2.translateCTM(tx: 5, ty: 5)
        c2.fill(.rect(VNRect(x: 0, y: 0, width: 6, height: 6)), color: .white)
        let a1 = totalCoverage(c1.framebuffer)
        let a2 = totalCoverage(c2.framebuffer)
        #expect(abs(a1 - a2) < 0.2, "Translate area mismatch: \(a1) vs \(a2)")
    }

    // Rotation by 360°: same coverage as the original.
    @Test func fullRotationPreservesArea() {
        let c1 = ctx(32, 32)
        let c2 = ctx(32, 32)
        let rect = VNPath.rect(VNRect(x: -4, y: -4, width: 8, height: 8))
        c1.translateCTM(tx: 16, ty: 16)
        c1.fill(rect, color: .white)
        c2.translateCTM(tx: 16, ty: 16)
        c2.rotateCTM(angle: 2 * .pi)
        c2.fill(rect, color: .white)
        let a1 = totalCoverage(c1.framebuffer)
        let a2 = totalCoverage(c2.framebuffer)
        #expect(abs(a1 - a2) < 0.5)
    }

    // A circle is rotationally symmetric: rotating by any angle preserves its area.
    //
    // CTM is post-multiplied (appended), so `rotateCTM` then `translateCTM` means
    // "rotate in local space, then place at (32,32)" — the circle stays centred.
    @Test func circleRotationPreservesArea() {
        let c1 = ctx(64, 64)
        let c2 = ctx(64, 64)
        let circle = VNPath.ellipse(in: VNRect(x: -12, y: -12, width: 24, height: 24))
        // c1: identity rotation
        c1.translateCTM(tx: 32, ty: 32)
        c1.fill(circle, color: .white)
        // c2: rotate locally (before translate), so rotation is around circle centre.
        c2.rotateCTM(angle: .pi / 5)
        c2.translateCTM(tx: 32, ty: 32)
        c2.fill(circle, color: .white)
        let a1 = totalCoverage(c1.framebuffer)
        let a2 = totalCoverage(c2.framebuffer)
        #expect(abs(a1 - a2) / a1 < 0.015, "Rotation changed circle area by \(abs(a1-a2)/a1*100)%")
    }
}

// MARK: - Stroke area mathematics

@Suite("Stroke area mathematics")
struct StrokeAreaMathTests {
    // A horizontal line of length L stroked with width W: area ≈ L × W.
    @Test func strokeAreaApproxLengthTimesWidth() {
        let L = 50.0, W = 4.0
        let c = ctx(64, 64)
        var path = VNPath()
        path.move(to: VNPoint(x: 7, y: 32))
        path.line(to: VNPoint(x: 57, y: 32))
        c.stroke(path, color: .white, lineWidth: W)
        let total = totalCoverage(c.framebuffer)
        #expect(abs(total - L * W) < 2.0, "Stroke area \(total) ≠ \(L*W)")
    }

    // Stroke width doubles → area doubles.
    @Test func strokeAreaProportionalToWidth() {
        let c1 = ctx(64, 16)
        let c2 = ctx(64, 16)
        var path = VNPath(); path.move(to: VNPoint(x: 4, y: 8)); path.line(to: VNPoint(x: 60, y: 8))
        c1.stroke(path, color: .white, lineWidth: 2)
        c2.stroke(path, color: .white, lineWidth: 4)
        let a1 = totalCoverage(c1.framebuffer)
        let a2 = totalCoverage(c2.framebuffer)
        #expect(abs(a2 / a1 - 2) < 0.05, "Ratio \(a2/a1) ≠ 2")
    }
}

// MARK: - Affine transform algebra

@Suite("Affine algebra")
struct AffineAlgebraTests {
    // (T1 · T2) · p = T1 · (T2 · p)
    @Test func concatenationAssociativity() {
        let t1 = VNAffineTransform.translation(x: 3, y: -1)
        let t2 = VNAffineTransform.scale(x: 2, y: 3)
        let t3 = VNAffineTransform.rotation(angle: .pi / 4)
        let p  = VNPoint(x: 5, y: 7)

        let lhs = t1.concatenating(t2).concatenating(t3).applying(to: p)
        let rhs = t1.concatenating(t2.concatenating(t3)).applying(to: p)
        #expect(abs(lhs.x - rhs.x) < 1e-10)
        #expect(abs(lhs.y - rhs.y) < 1e-10)
    }

    // Identity is the neutral element.
    @Test func identityNeutralElement() {
        let t = VNAffineTransform.scale(x: 3, y: 0.5)
        let ti = t.concatenating(.identity)
        let it = VNAffineTransform.identity.concatenating(t)
        let p = VNPoint(x: 4, y: 9)
        let pt = t.applying(to: p)
        #expect(abs(ti.applying(to: p).x - pt.x) < 1e-12)
        #expect(abs(it.applying(to: p).x - pt.x) < 1e-12)
    }

    // Rotation by θ then −θ: back to identity.
    @Test func rotationInverse() {
        let theta = 1.23
        let t = VNAffineTransform.rotation(angle: theta)
            .concatenating(.rotation(angle: -theta))
        let p = VNPoint(x: 7, y: -3)
        let out = t.applying(to: p)
        #expect(abs(out.x - p.x) < 1e-10)
        #expect(abs(out.y - p.y) < 1e-10)
    }

    // Scale by s then 1/s: back to identity.
    @Test func scaleInverse() {
        let s = 3.7
        let t = VNAffineTransform.scale(x: s, y: s)
            .concatenating(.scale(x: 1/s, y: 1/s))
        let p = VNPoint(x: 2, y: 5)
        let out = t.applying(to: p)
        #expect(abs(out.x - p.x) < 1e-10)
        #expect(abs(out.y - p.y) < 1e-10)
    }
}
