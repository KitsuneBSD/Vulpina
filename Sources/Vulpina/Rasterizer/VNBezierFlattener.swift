import Foundation

// Adaptive flattening of cubic Béziers, quadratic Béziers, and arcs to line segments.
// Tolerance is the maximum allowed deviation in points (default 0.1px per D17).

enum VNBezierFlattener {
    // MARK: - Cubic Bézier

    static func flattenCubic(
        p0: VNPoint, p1: VNPoint, p2: VNPoint, p3: VNPoint,
        tolerance: Double,
        emit: (VNPoint) -> Void
    ) {
        if isFlatCubic(p0: p0, p1: p1, p2: p2, p3: p3, tolerance: tolerance) {
            emit(p3)
            return
        }
        // de Casteljau subdivision at t = 0.5
        let m01  = mid(p0, p1);  let m12  = mid(p1, p2);  let m23  = mid(p2, p3)
        let m012 = mid(m01, m12); let m123 = mid(m12, m23)
        let m    = mid(m012, m123)
        flattenCubic(p0: p0, p1: m01, p2: m012, p3: m,    tolerance: tolerance, emit: emit)
        flattenCubic(p0: m,  p1: m123, p2: m23, p3: p3,   tolerance: tolerance, emit: emit)
    }

    // MARK: - Quadratic Bézier

    static func flattenQuad(
        p0: VNPoint, p1: VNPoint, p2: VNPoint,
        tolerance: Double,
        emit: (VNPoint) -> Void
    ) {
        if isFlatQuad(p0: p0, p1: p1, p2: p2, tolerance: tolerance) {
            emit(p2)
            return
        }
        let m01 = mid(p0, p1); let m12 = mid(p1, p2)
        let m   = mid(m01, m12)
        flattenQuad(p0: p0, p1: m01, p2: m,  tolerance: tolerance, emit: emit)
        flattenQuad(p0: m,  p1: m12, p2: p2, tolerance: tolerance, emit: emit)
    }

    // MARK: - Arc

    /// Flattens a circular arc to line segments by converting each ≤90° span
    /// to a cubic Bézier approximation.
    static func flattenArc(
        center: VNPoint, radius: Double,
        startAngle: Double, endAngle: Double,
        clockwise: Bool,
        tolerance: Double,
        emit: (VNPoint) -> Void
    ) {
        // Normalise the angular span into a sequence of at-most-π/2 segments.
        let start = startAngle
        var end   = endAngle

        // Ensure the sweep goes in the right direction.
        if clockwise {
            while end > start { end -= 2 * .pi }
        } else {
            while end < start { end += 2 * .pi }
        }

        let totalSpan = abs(end - start)
        guard totalSpan > 1e-10 else { emit(VNPoint(x: center.x + radius * cos(end),
                                                     y: center.y + radius * sin(end))); return }

        let numSegs = max(1, Int(ceil(totalSpan / (.pi / 2))))
        let step    = (end - start) / Double(numSegs)

        for i in 0..<numSegs {
            let a0 = start + Double(i)     * step
            let a1 = start + Double(i + 1) * step
            flattenArcSegment(center: center, radius: radius, a0: a0, a1: a1,
                              tolerance: tolerance, emit: emit)
        }
    }

    // MARK: - Private helpers

    /// Converts an arc segment (|a1-a0| ≤ π/2) to a cubic Bézier and flattens it.
    private static func flattenArcSegment(
        center: VNPoint, radius: Double, a0: Double, a1: Double,
        tolerance: Double,
        emit: (VNPoint) -> Void
    ) {
        let span = a1 - a0
        let k    = (4.0 / 3.0) * Foundation.tan(span / 4)
        let p0   = VNPoint(x: center.x + radius * cos(a0), y: center.y + radius * sin(a0))
        let p3   = VNPoint(x: center.x + radius * cos(a1), y: center.y + radius * sin(a1))
        let p1   = VNPoint(x: p0.x - radius * sin(a0) * k,  y: p0.y + radius * cos(a0) * k)
        let p2   = VNPoint(x: p3.x + radius * sin(a1) * k,  y: p3.y - radius * cos(a1) * k)
        flattenCubic(p0: p0, p1: p1, p2: p2, p3: p3, tolerance: tolerance, emit: emit)
    }

    // MARK: - Flatness tests

    private static func isFlatCubic(
        p0: VNPoint, p1: VNPoint, p2: VNPoint, p3: VNPoint, tolerance: Double
    ) -> Bool {
        let d1 = perpDistance(p1, from: p0, to: p3)
        let d2 = perpDistance(p2, from: p0, to: p3)
        return max(d1, d2) <= tolerance
    }

    private static func isFlatQuad(
        p0: VNPoint, p1: VNPoint, p2: VNPoint, tolerance: Double
    ) -> Bool {
        return perpDistance(p1, from: p0, to: p2) <= tolerance
    }

    /// Perpendicular distance from `pt` to the line through `a` and `b`.
    private static func perpDistance(_ pt: VNPoint, from a: VNPoint, to b: VNPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 1e-12 else {
            let ex = pt.x - a.x, ey = pt.y - a.y
            return Foundation.sqrt(ex * ex + ey * ey)
        }
        let cross = (pt.x - a.x) * dy - (pt.y - a.y) * dx
        return abs(cross) / Foundation.sqrt(len2)
    }

    private static func mid(_ a: VNPoint, _ b: VNPoint) -> VNPoint {
        VNPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
    }
}
