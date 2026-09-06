import Foundation
import Testing
@testable import Vulpina

// MARK: - VNStroker join geometry tests (IMM-5)
//
// Each test builds a two-segment path with a known turn angle, strokes it,
// and checks that the resulting filled-path vertices match the expected
// join geometry (bevel endpoints, miter vertex, round arc presence).
//
// Coordinate system: bottom-left origin, y-up.
// Path: A(0,0) → B(10,0) → C with a known turn.

@Suite("VNStrokerJoinTests")
struct StrokerJoinTests {

    // Half-width used in all tests.
    private let hw: Double = 2.0

    // Strokes a two-segment open path A→B→C and returns the flattened
    // outline vertices.
    private func strokeABC(
        a: VNPoint = VNPoint(x: 0, y: 0),
        b: VNPoint = VNPoint(x: 10, y: 0),
        c: VNPoint,
        join: VNLineJoin,
        miterLimit: Double = 10.0
    ) -> [VNPoint] {
        var path = VNPath(windingRule: .nonZero)
        path.move(to: a)
        path.line(to: b)
        path.line(to: c)

        let outline = VNStroker.strokePath(
            path,
            lineWidth: hw * 2,
            lineCap: .butt,
            lineJoin: join,
            miterLimit: miterLimit,
            flattenTolerance: 0.01
        )
        // Flatten the outline (which is already lines only) to a vertex list.
        var verts: [VNPoint] = []
        for el in outline.elements {
            switch el {
            case .moveTo(let p): verts.append(p)
            case .lineTo(let p): verts.append(p)
            default: break
            }
        }
        return verts
    }

    // MARK: Bevel join — 90° left turn

    @Test("Bevel join: 90° left turn emits two outer points")
    func bevelLeftTurn() {
        // A(0,0)→B(10,0)→C(10,10): 90° left turn at B.
        // Left (convex) side at B: lIn=(10,2) [offset from incoming seg],
        //                          lOut=(8,0)  [offset from outgoing seg].
        // Bevel emits both points → outline must contain both.
        let verts = strokeABC(c: VNPoint(x: 10, y: 10), join: .bevel)

        let hasLIn  = verts.contains { abs($0.x - 10) < 0.05 && abs($0.y - 2) < 0.05 }
        let hasLOut = verts.contains { abs($0.x -  8) < 0.05 && abs($0.y - 0) < 0.05 }
        #expect(hasLIn,  "bevel outer vertex lIn=(10,2) not found")
        #expect(hasLOut, "bevel outer vertex lOut=(8,0) not found")
    }

    @Test("Bevel join: 90° right turn emits two outer points")
    func bevelRightTurn() {
        // A(0,0)→B(10,0)→C(10,-10): 90° right turn at B.
        // Segment A→B: tangent=(1,0), left-normal=(0,1).
        // Segment B→C: tangent=(0,-1), left-normal=(1,0).
        // cross = tIn×tOut = 1*(-1)-0*0 = -1 < 0 → right turn → right side is convex.
        // rIn  = B - half·nIn  = (10,0) - 2·(0,1)  = (10,-2).
        // rOut = B - half·nOut = (10,0) - 2·(1,0)   = (8, 0).
        let verts = strokeABC(c: VNPoint(x: 10, y: -10), join: .bevel)

        let hasRIn  = verts.contains { abs($0.x - 10) < 0.05 && abs($0.y + 2) < 0.05 }
        let hasROut = verts.contains { abs($0.x -  8) < 0.05 && abs($0.y - 0) < 0.05 }
        #expect(hasRIn,  "bevel outer vertex rIn=(10,-2) not found")
        #expect(hasROut, "bevel outer vertex rOut=(8,0) not found")
    }

    // MARK: Miter join — within limit

    @Test("Miter join: 90° left turn within limit emits single miter vertex")
    func miterWithinLimit() {
        // At a 90° left turn at B(10,0) with half=2:
        // lIn=(10,2), lOut=(8,0).
        // Miter intersection of lines (10,2)+t*(1,0) and (8,0)+s*(0,1):
        //   x: 10+t = 8  → impossible. Let me recalculate.
        //
        // Incoming tangent at B: (1,0). Outgoing tangent: (0,1).
        // Incoming left offset line through lIn=(10,2) in direction (1,0).
        // Outgoing left offset line through lOut=(8,0)  in direction (0,1).
        //
        // Line1: (10+t, 2),  Line2: (8, s).
        // Intersect: 10+t=8 → t=-2; y: 2=s → miter=(8,2).
        //
        // Miter distance from B(10,0): sqrt((8-10)²+(2-0)²) = sqrt(8) ≈ 2.83.
        // Miter limit check: dist/half = 2.83/2 ≈ 1.41 ≤ 10 → accepted.
        let verts = strokeABC(c: VNPoint(x: 10, y: 10), join: .miter, miterLimit: 10)

        let hasMiter = verts.contains { abs($0.x - 8) < 0.05 && abs($0.y - 2) < 0.05 }
        #expect(hasMiter, "miter vertex (8,2) not found for 90° left turn")

        // Must NOT have both bevel points simultaneously (that would be a bevel, not miter).
        let hasLIn  = verts.contains { abs($0.x - 10) < 0.05 && abs($0.y - 2) < 0.05 }
        let hasLOut = verts.contains { abs($0.x -  8) < 0.05 && abs($0.y - 0) < 0.05 }
        #expect(!(hasLIn && hasLOut), "miter emitted bevel points instead of miter vertex")
    }

    // MARK: Miter join — limit exceeded → bevel fallback

    @Test("Miter join: limit exceeded falls back to bevel (two outer points)")
    func miterLimitFallback() {
        // At a 90° left turn, miter distance ≈ 2.83, half=2.
        // miterScale = 2.83/2 ≈ 1.41.
        // Set miterLimit=1.0 → limit exceeded → fallback to bevel.
        let verts = strokeABC(c: VNPoint(x: 10, y: 10), join: .miter, miterLimit: 1.0)

        let hasLIn  = verts.contains { abs($0.x - 10) < 0.05 && abs($0.y - 2) < 0.05 }
        let hasLOut = verts.contains { abs($0.x -  8) < 0.05 && abs($0.y - 0) < 0.05 }
        #expect(hasLIn,  "miter-fallback bevel vertex lIn=(10,2) not found")
        #expect(hasLOut, "miter-fallback bevel vertex lOut=(8,0) not found")

        // The true miter vertex (8,2) must NOT appear.
        let hasMiter = verts.contains { abs($0.x - 8) < 0.05 && abs($0.y - 2) < 0.05 }
        #expect(!hasMiter, "miter vertex (8,2) should not appear when limit is exceeded")
    }

    // MARK: Round join — arc present

    @Test("Round join: outer contour has more vertices than bevel (arc)")
    func roundJoinHasArc() {
        // A round join must emit more outer-side vertices than a bevel join
        // (the arc is subdivided into line segments by the flattener).
        let bevelVerts = strokeABC(c: VNPoint(x: 10, y: 10), join: .bevel)
        let roundVerts = strokeABC(c: VNPoint(x: 10, y: 10), join: .round)
        #expect(roundVerts.count > bevelVerts.count,
                "round join should produce more vertices than bevel (arc segments)")
    }

    @Test("Round join: all arc vertices lie on the circle of radius half")
    func roundJoinOnCircle() {
        // All extra vertices introduced by the round join at B(10,0) should lie
        // at distance ≈ half from B.
        let bevelVerts = Set(strokeABC(c: VNPoint(x: 10, y: 10), join: .bevel)
            .map { "\(Int($0.x*100)),\(Int($0.y*100))" })
        let roundVerts = strokeABC(c: VNPoint(x: 10, y: 10), join: .round)

        let b = VNPoint(x: 10, y: 0)
        for v in roundVerts {
            let key = "\(Int(v.x*100)),\(Int(v.y*100))"
            guard !bevelVerts.contains(key) else { continue }  // not an arc-only point
            let dx = v.x - b.x, dy = v.y - b.y
            let dist = Foundation.sqrt(dx*dx + dy*dy)
            #expect(abs(dist - hw) < 0.15,
                    "arc vertex \(v) is not at radius \(hw) from join vertex B\(b) (dist=\(dist))")
        }
    }

    // MARK: Concave side — line intersection

    @Test("Concave side uses line intersection (no over-extension)")
    func concaveLineIntersection() {
        // At a 90° left turn at B(10,0), the RIGHT (concave) side should be
        // a single intersection point. Incoming right offset: rIn=(10,-2) along (1,0).
        // Outgoing right offset: rOut=(12,0) along (0,1).
        // Intersection: (10+t,-2) = (12, s) → t=2, s=-2 → (12,-2).
        let verts = strokeABC(c: VNPoint(x: 10, y: 10), join: .bevel)

        let hasInner = verts.contains { abs($0.x - 12) < 0.05 && abs($0.y + 2) < 0.05 }
        #expect(hasInner, "concave intersection (12,-2) not found")
    }
}
