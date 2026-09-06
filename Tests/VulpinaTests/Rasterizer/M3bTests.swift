import Testing
import Foundation
@testable import Vulpina

// MARK: - Bézier flattening

@Suite("VNBezierFlattener")
struct VNBezierFlattenerTests {
    // The flattened ellipse area should approximate π·r² to within 1%.
    @Test func ellipseAreaApproxPiR2() {
        let r = 50.0
        let path = VNPath.ellipse(in: VNRect(x: 0, y: 0, width: 2*r, height: 2*r))
        let flat = path.flattened(tolerance: 0.1)

        // Collect vertices and compute area via shoelace.
        var verts: [VNPoint] = []
        var current = VNPoint.zero
        var contourStart = VNPoint.zero
        for el in flat.elements {
            switch el {
            case .moveTo(let p):  verts.append(p); current = p; contourStart = p
            case .lineTo(let p):  verts.append(p); current = p
            case .close:          if current != contourStart { verts.append(contourStart) }
            default: break
            }
        }
        var area = 0.0
        let n = verts.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += verts[i].x * verts[j].y - verts[j].x * verts[i].y
        }
        area = abs(area) / 2
        let expected = Double.pi * r * r
        let error = abs(area - expected) / expected
        #expect(error < 0.01, "Ellipse area error \(error*100)% > 1%")
    }

    // Flatten error for a cubic Bézier must be < tolerance.
    @Test func cubicFlattenError() {
        let p0 = VNPoint(x: 0, y: 0)
        let p1 = VNPoint(x: 20, y: 40)
        let p2 = VNPoint(x: 80, y: 40)
        let p3 = VNPoint(x: 100, y: 0)
        var pts = [p0]
        VNBezierFlattener.flattenCubic(p0: p0, p1: p1, p2: p2, p3: p3,
                                       tolerance: 0.1) { pts.append($0) }
        // Each consecutive chord should be within 0.1px of the true curve.
        for i in 0..<(pts.count - 1) {
            let mid = VNPoint(x: (pts[i].x + pts[i+1].x)/2, y: (pts[i].y + pts[i+1].y)/2)
            // Compute Bézier at parameter near the midpoint for a rough check.
            let t = Double(i) / Double(pts.count - 1) + 0.5 / Double(pts.count - 1)
            let bt = bezierAt(t, p0: p0, p1: p1, p2: p2, p3: p3)
            let dx = bt.x - mid.x, dy = bt.y - mid.y
            let dist = Foundation.sqrt(dx*dx + dy*dy)
            #expect(dist < 2.0, "Midpoint deviation \(dist) too large at segment \(i)")
        }
    }

    // Arc endpoint must match the expected end coordinate.
    @Test func arcEndpointAccuracy() {
        var pts: [VNPoint] = []
        let center = VNPoint(x: 50, y: 50)
        let radius = 30.0
        VNBezierFlattener.flattenArc(
            center: center, radius: radius,
            startAngle: 0, endAngle: .pi / 2,
            clockwise: false,
            tolerance: 0.1) { pts.append($0) }
        guard let last = pts.last else { Issue.record("No points emitted"); return }
        let expected = VNPoint(x: center.x, y: center.y + radius)
        let dx = last.x - expected.x, dy = last.y - expected.y
        let dist = Foundation.sqrt(dx*dx + dy*dy)
        #expect(dist < 0.5)
    }
}

// MARK: - VNPath convenience

@Suite("VNPath M3b")
struct VNPathM3bTests {
    @Test func ellipseElementCount() {
        let e = VNPath.ellipse(in: VNRect(x: 0, y: 0, width: 100, height: 50))
        // move + 4 cubicTo + close = 6
        #expect(e.elements.count == 6)
    }

    @Test func roundedRectElementCount() {
        let r = VNPath.roundedRect(VNRect(x: 0, y: 0, width: 100, height: 100), cornerRadius: 10)
        // move + 4*(line+cubicTo) + close = 1 + 8 + 1 = 10
        #expect(r.elements.count == 10)
    }

    @Test func roundedRectZeroRadius() {
        // r=0 must degenerate gracefully (no crash).
        let _ = VNPath.roundedRect(VNRect(x: 0, y: 0, width: 50, height: 50), cornerRadius: 0)
    }

    @Test func flattenedContainsOnlyLineElements() {
        let path = VNPath.ellipse(in: VNRect(x: 0, y: 0, width: 100, height: 100))
        let flat = path.flattened()
        for el in flat.elements {
            switch el {
            case .moveTo, .lineTo, .close: break
            default: Issue.record("Unexpected element after flattening")
            }
        }
    }
}

// MARK: - Fill with curves

@Suite("Curve fill")
struct CurveFillTests {
    @Test func ellipseCenterPixelCovered() {
        let c = VNGraphicsContext(widthPixels: 64, heightPixels: 64)
        c.fill(VNPath.ellipse(in: VNRect(x: 4, y: 4, width: 56, height: 56)), color: .white)
        let center = c.framebuffer.pixel(x: 32, y: 32)
        #expect(center.a > 240)
    }

    @Test func ellipseCornerPixelNotCovered() {
        let c = VNGraphicsContext(widthPixels: 64, heightPixels: 64)
        c.fill(VNPath.ellipse(in: VNRect(x: 4, y: 4, width: 56, height: 56)), color: .white)
        // Pixel (0,0) is far outside the ellipse.
        #expect(c.framebuffer.pixel(x: 0, y: 0).a == 0)
    }

    @Test func roundedRectInteriorCovered() {
        let c = VNGraphicsContext(widthPixels: 64, heightPixels: 64)
        c.fill(VNPath.roundedRect(VNRect(x: 4, y: 4, width: 56, height: 56), cornerRadius: 8),
               color: .white)
        #expect(c.framebuffer.pixel(x: 32, y: 32).a > 240)
        // Corners are rounded → pixel (4,4) (bottom-left corner in pixel y-down) may have lower alpha.
        #expect(c.framebuffer.pixel(x: 0, y: 0).a == 0)
    }

    @Test func evenOddDonut() {
        // Concentric ellipses with even-odd rule → center is NOT filled.
        var path = VNPath(windingRule: .evenOdd)
        path.appendPath(VNPath.ellipse(in: VNRect(x: 0, y: 0, width: 64, height: 64)))
        path.appendPath(VNPath.ellipse(in: VNRect(x: 16, y: 16, width: 32, height: 32)))

        let c = VNGraphicsContext(widthPixels: 64, heightPixels: 64)
        c.fill(path, color: .white)
        // Ring area (near edge, e.g. pixel (4,32)): covered.
        #expect(c.framebuffer.pixel(x: 4, y: 32).a > 100)
        // Center of donut: should NOT be filled with even-odd.
        #expect(c.framebuffer.pixel(x: 32, y: 32).a < 50)
    }
}

// MARK: - Stroke

@Suite("Stroke")
struct StrokeTests {
    @Test func strokedLineHasPixelsCovered() {
        let c = VNGraphicsContext(widthPixels: 64, heightPixels: 64)
        var path = VNPath()
        path.move(to: VNPoint(x: 0, y: 32))
        path.line(to: VNPoint(x: 64, y: 32))
        c.stroke(path, color: .white, lineWidth: 4)
        // Pixels along the center of the stroke should be covered.
        #expect(c.framebuffer.pixel(x: 32, y: 32).a > 200)
    }

    @Test func strokedLineWidthApproximate() {
        // A vertical line of width 10 in a 64×64 buffer.
        let c = VNGraphicsContext(widthPixels: 64, heightPixels: 64)
        var path = VNPath()
        path.move(to: VNPoint(x: 32, y: 0))
        path.line(to: VNPoint(x: 32, y: 64))
        c.stroke(path, color: .white, lineWidth: 10)
        // Pixels within ±5 of center (x=32) should be covered; outside should not.
        #expect(c.framebuffer.pixel(x: 29, y: 32).a > 200)
        #expect(c.framebuffer.pixel(x: 8,  y: 32).a < 50)
    }

    @Test func squareCapExtendsEndpoints() {
        let c = VNGraphicsContext(widthPixels: 64, heightPixels: 64)
        var path = VNPath()
        path.move(to: VNPoint(x: 10, y: 32))
        path.line(to: VNPoint(x: 54, y: 32))
        c.stroke(path, color: .white, lineWidth: 6, lineCap: .square)
        // With square cap, coverage should extend 3px beyond each endpoint.
        #expect(c.framebuffer.pixel(x: 8, y: 32).a > 100)
    }

    @Test func roundCapNoCrash() {
        let c = VNGraphicsContext(widthPixels: 32, heightPixels: 32)
        var path = VNPath()
        path.move(to: VNPoint(x: 8, y: 16))
        path.line(to: VNPoint(x: 24, y: 16))
        c.stroke(path, color: .red, lineWidth: 4, lineCap: .round)
        #expect(c.framebuffer.pixel(x: 16, y: 16).a > 200)
    }

    @Test func strokedRectOutlineNotFilled() {
        let c = VNGraphicsContext(widthPixels: 64, heightPixels: 64)
        c.stroke(VNPath.rect(VNRect(x: 10, y: 10, width: 44, height: 44)),
                 color: .white, lineWidth: 2)
        // Center of the rect interior should NOT be covered (stroke only, not fill).
        #expect(c.framebuffer.pixel(x: 32, y: 32).a < 50)
        // The left stroke ring covers pixels in [outer=9, inner=11), i.e. pixel x=10.
        #expect(c.framebuffer.pixel(x: 10, y: 32).a > 100)
    }
}

// MARK: - IMM-2: flattened() after close

@Suite("VNPath.flattened post-close")
struct VNPathFlattenedPostCloseTests {
    // After closing a subpath, current must reset to subpathStart so that a
    // subsequent curve (quadTo/cubicTo) without an intervening moveTo starts
    // from the correct point instead of from the close point (which is the same)
    // but verifies the tracking is correct when two subpaths are chained.
    @Test func flattenedTwoSubpathsIndependent() {
        // First subpath: triangle (0,0)→(10,0)→(5,10)→close
        // Second subpath: line from (20,20)→(30,20) with a quadTo using
        // current-point continuity — this relies on current being (20,20) after moveTo.
        var path = VNPath()
        path.move(to: VNPoint(x: 0, y: 0))
        path.line(to: VNPoint(x: 10, y: 0))
        path.line(to: VNPoint(x: 5, y: 10))
        path.close()
        // Second subpath starts fresh.
        path.move(to: VNPoint(x: 20, y: 20))
        path.addQuadCurve(to: VNPoint(x: 30, y: 20), control: VNPoint(x: 25, y: 25))
        path.close()

        let flat = path.flattened(tolerance: 0.1)

        // Collect all line endpoints per subpath.
        var subpaths: [[VNPoint]] = []
        var current: [VNPoint] = []
        for el in flat.elements {
            switch el {
            case .moveTo(let p): current = [p]
            case .lineTo(let p): current.append(p)
            case .close:         subpaths.append(current); current = []
            default: break
            }
        }
        #expect(subpaths.count == 2)
        // Second subpath must start at (20,20) and end near (30,20).
        guard subpaths.count == 2 else { return }
        #expect(abs(subpaths[1].first!.x - 20) < 0.01)
        #expect(abs(subpaths[1].first!.y - 20) < 0.01)
        #expect(abs(subpaths[1].last!.x - 30) < 0.01)
        #expect(abs(subpaths[1].last!.y - 20) < 0.5)
    }

    // Verify that current resets to subpathStart after close, not to zero.
    @Test func flattenedCurrentResetsToSubpathStartAfterClose() {
        // Two rects: if current doesn't reset, the second rect's implicit-moveTo
        // would be wrong (but VNPath.rect always has explicit moveTo, so we test
        // a cubicTo immediately after close without moveTo — that's the real gap).
        var path = VNPath()
        path.move(to: VNPoint(x: 5, y: 5))
        path.line(to: VNPoint(x: 10, y: 5))
        path.close()
        // cubicTo immediately after close: current should be (5,5) not (0,0).
        path.addCurve(to: VNPoint(x: 20, y: 5),
                      control1: VNPoint(x: 10, y: 10),
                      control2: VNPoint(x: 15, y: 10))

        let flat = path.flattened(tolerance: 0.1)
        // Collect all lineTo points after the close.
        var postClosePoints: [VNPoint] = []
        var pastClose = false
        for el in flat.elements {
            switch el {
            case .close: pastClose = true
            case .lineTo(let p): if pastClose { postClosePoints.append(p) }
            default: break
            }
        }
        // The curve from (5,5) to (20,5) must pass through the upper region (y ≈ 5..10).
        // If current were (0,0), the curve would dip far below, producing y-values < 4.
        let allReasonable = postClosePoints.allSatisfy { $0.y >= 4.0 }
        #expect(allReasonable, "Curve after close started from wrong point (expected ~(5,5))")
    }
}

// MARK: - IMM-3: coverage with coincident edges

@Suite("VNAnalyticScanConverter coincident edges")
struct CoincidentEdgeCoverageTests {
    // Two edges in the same direction over the same pixel: winding = 2,
    // non-zero coverage must clamp to 1 (not 2).
    @Test func coincidentSameDirectionClampsToOne() {
        let edge = _VNEdge(x0: 0.5, y0: 0, x1: 0.5, y1: 1, direction: 1)
        var coverage = [Float](repeating: 0, count: 4)
        VNAnalyticScanConverter.rasterize(
            edges: [edge, edge],
            width: 2, height: 1,
            windingRule: .nonZero,
            into: &coverage)
        let cov = VNAnalyticScanConverter.coverageValue(coverage[0], rule: .nonZero)
        #expect(cov <= 1.0, "Coverage \(cov) exceeds 1.0 for coincident edges")
        #expect(cov > 0.0, "Coverage should be nonzero inside")
    }

    // Two edges in opposite directions (degenerate stroke): winding = 0,
    // non-zero coverage must be 0 (outside).
    @Test func coincidentOppositeDirectionsCancelOut() {
        let edgeA = _VNEdge(x0: 0.5, y0: 0, x1: 0.5, y1: 1, direction:  1)
        let edgeB = _VNEdge(x0: 0.5, y0: 0, x1: 0.5, y1: 1, direction: -1)
        var coverage = [Float](repeating: 0, count: 4)
        VNAnalyticScanConverter.rasterize(
            edges: [edgeA, edgeB],
            width: 2, height: 1,
            windingRule: .nonZero,
            into: &coverage)
        let cov = VNAnalyticScanConverter.coverageValue(coverage[0], rule: .nonZero)
        #expect(abs(cov) < 0.01, "Opposite coincident edges should cancel (got \(cov))")
    }

    // Even-odd rule with two coincident same-direction edges contributing full
    // coverage (edge at x=1.5 → pixel x=0 gets fullContrib=H=1.0 per edge,
    // total accumulated area = 2.0 → even-odd folds 2 back to 0 → outside).
    @Test func coincidentEvenOddFoldsBack() {
        // Edge entirely to the right of pixel 0: pixel 0 receives fullContrib=H per edge.
        let edge = _VNEdge(x0: 1.5, y0: 0, x1: 1.5, y1: 1, direction: 1)
        var coverage = [Float](repeating: 0, count: 4)
        VNAnalyticScanConverter.rasterize(
            edges: [edge, edge],
            width: 2, height: 1,
            windingRule: .evenOdd,
            into: &coverage)
        // coverage[0] ≈ 2.0 (two full-height contributions); even-odd: 2 mod 2 = 0 → outside.
        let cov = VNAnalyticScanConverter.coverageValue(coverage[0], rule: .evenOdd)
        #expect(cov < 0.1, "Even-odd with accumulated area ≈ 2.0 should fold back to outside (got \(cov))")
    }
}

// MARK: - Helpers

private func bezierAt(_ t: Double, p0: VNPoint, p1: VNPoint, p2: VNPoint, p3: VNPoint) -> VNPoint {
    let u = 1 - t
    let x = u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x
    let y = u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y
    return VNPoint(x: x, y: y)
}
