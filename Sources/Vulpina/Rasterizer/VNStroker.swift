import Foundation

// Converts a stroked VNPath into a filled VNPath outline.
// The outline is built in point-space (bottom-left, y-up).

enum VNStroker {
    /// Returns a filled path representing the stroke of `path`.
    static func strokePath(
        _ path: VNPath,
        lineWidth: Double,
        lineCap: VNLineCap,
        lineJoin: VNLineJoin,
        miterLimit: Double,
        flattenTolerance: Double
    ) -> VNPath {
        let flat = path.flattened(tolerance: flattenTolerance)
        var result = VNPath(windingRule: .nonZero)
        let half = lineWidth / 2

        var subpathStart: VNPoint? = nil
        var points: [VNPoint] = []
        var isClosed = false

        func flush() {
            guard points.count >= 2 else { points = []; subpathStart = nil; return }
            addStrokeSubpath(points: points, closed: isClosed, half: half,
                             lineCap: lineCap, lineJoin: lineJoin,
                             miterLimit: miterLimit, into: &result)
            points = []
            subpathStart = nil
            isClosed = false
        }

        for element in flat.elements {
            switch element {
            case .moveTo(let p):
                flush()
                subpathStart = p
                points = [p]
            case .lineTo(let p):
                points.append(p)
            case .close:
                if let start = subpathStart { points.append(start) }
                isClosed = true
                flush()
            case .cubicTo, .quadTo, .arcTo:
                break  // already flattened
            }
        }
        flush()
        return result
    }

    // MARK: - Sub-path stroke

    private static func addStrokeSubpath(
        points: [VNPoint], closed: Bool, half: Double,
        lineCap: VNLineCap, lineJoin: VNLineJoin,
        miterLimit: Double, into result: inout VNPath
    ) {
        let n = points.count
        guard n >= 2 else { return }

        // Per-segment unit left-normals and tangents.
        var normals  = [VNPoint]()
        var tangents = [VNPoint]()
        for i in 0..<(n - 1) {
            let dx = points[i+1].x - points[i].x
            let dy = points[i+1].y - points[i].y
            let len = Foundation.sqrt(dx*dx + dy*dy)
            guard len > 1e-10 else {
                normals.append(.zero); tangents.append(.zero); continue
            }
            let tx = dx / len, ty = dy / len
            tangents.append(VNPoint(x: tx, y: ty))
            normals.append(VNPoint(x: -ty, y: tx))   // 90° CCW of tangent = left normal
        }

        func leftOf(_ p: VNPoint, _ nrm: VNPoint)  -> VNPoint {
            VNPoint(x: p.x + half * nrm.x, y: p.y + half * nrm.y)
        }
        func rightOf(_ p: VNPoint, _ nrm: VNPoint) -> VNPoint {
            VNPoint(x: p.x - half * nrm.x, y: p.y - half * nrm.y)
        }

        // Build left and right stroke contours.
        var leftPts  = [VNPoint]()
        var rightPts = [VNPoint]()

        // Start vertex.
        if closed {
            // The start vertex has the last segment coming in and the first going out.
            emitJoin(at: points[0],
                     nIn: normals[n-2], tIn: tangents[n-2],
                     nOut: normals[0],  tOut: tangents[0],
                     half: half, joinStyle: lineJoin, miterLimit: miterLimit,
                     leftPts: &leftPts, rightPts: &rightPts)
        } else {
            leftPts.append(leftOf(points[0], normals[0]))
            rightPts.append(rightOf(points[0], normals[0]))
        }

        // Interior joints.
        for i in 1..<(n - 1) {
            emitJoin(at: points[i],
                     nIn: normals[i-1], tIn: tangents[i-1],
                     nOut: normals[i],  tOut: tangents[i],
                     half: half, joinStyle: lineJoin, miterLimit: miterLimit,
                     leftPts: &leftPts, rightPts: &rightPts)
        }

        // End vertex.
        if !closed {
            leftPts.append(leftOf(points[n-1], normals[n-2]))
            rightPts.append(rightOf(points[n-1], normals[n-2]))
        }

        // Assemble the filled outline.
        // Forward along left, end-cap, backward along right, start-cap.
        result.move(to: leftPts[0])
        for pt in leftPts.dropFirst() { result.line(to: pt) }

        if closed {
            result.close()
            // Inner path reversed → winds opposite (non-zero: outer +1, inner −1 = hole).
            result.move(to: rightPts[rightPts.count - 1])
            for i in stride(from: rightPts.count - 2, through: 0, by: -1) {
                result.line(to: rightPts[i])
            }
            result.close()
        } else {
            addCap(center: points[n-1], normal: normals[n-2], half: half,
                   cap: lineCap, atEnd: true, into: &result)
            for pt in rightPts.reversed() { result.line(to: pt) }
            addCap(center: points[0], normal: normals[0], half: half,
                   cap: lineCap, atEnd: false, into: &result)
            result.close()
        }
    }

    // MARK: - Join emission

    /// Appends the correct offset vertices for the join at `vertex`.
    ///
    /// The cross product of `tIn × tOut` tells us the turn direction:
    /// - cross > 0 → left turn: left side is convex, right side is concave.
    /// - cross < 0 → right turn: right side is convex, left side is concave.
    ///
    /// The convex (outer) side may emit 1–N points depending on join style.
    /// The concave (inner) side emits the single line-intersection point.
    private static func emitJoin(
        at vertex: VNPoint,
        nIn: VNPoint, tIn: VNPoint,
        nOut: VNPoint, tOut: VNPoint,
        half: Double,
        joinStyle: VNLineJoin,
        miterLimit: Double,
        leftPts: inout [VNPoint],
        rightPts: inout [VNPoint]
    ) {
        let cross = tIn.x * tOut.y - tIn.y * tOut.x

        // Offset points at the join vertex from each neighbouring segment.
        let lIn  = VNPoint(x: vertex.x + half * nIn.x,  y: vertex.y + half * nIn.y)
        let lOut = VNPoint(x: vertex.x + half * nOut.x, y: vertex.y + half * nOut.y)
        let rIn  = VNPoint(x: vertex.x - half * nIn.x,  y: vertex.y - half * nIn.y)
        let rOut = VNPoint(x: vertex.x - half * nOut.x, y: vertex.y - half * nOut.y)

        guard abs(cross) >= 1e-8 else {
            // Straight segment: use the incoming offset point on each side.
            leftPts.append(lIn)
            rightPts.append(rIn)
            return
        }

        if cross > 0 {
            // Left turn → left side convex, right side concave.
            emitConvexSide(into: &leftPts, vertex: vertex,
                           pIn: lIn, pOut: lOut, tIn: tIn, tOut: tOut,
                           half: half, joinStyle: joinStyle, miterLimit: miterLimit)
            // Concave side: intersection of the two inset offset lines.
            rightPts.append(lineIntersect(rIn, tIn, rOut, tOut) ?? rIn)
        } else {
            // Right turn → right side convex, left side concave.
            leftPts.append(lineIntersect(lIn, tIn, lOut, tOut) ?? lIn)
            emitConvexSide(into: &rightPts, vertex: vertex,
                           pIn: rIn, pOut: rOut, tIn: tIn, tOut: tOut,
                           half: half, joinStyle: joinStyle, miterLimit: miterLimit)
        }
    }

    /// Appends 1 or more points for the convex (outer) side of a join.
    ///
    /// - Miter: extends both offset edges to their intersection; falls back to bevel
    ///   when the miter length exceeds `half × miterLimit`.
    /// - Bevel: the two endpoint offset points connected by a straight line.
    /// - Round: an arc from `pIn` to `pOut` around `vertex`.
    private static func emitConvexSide(
        into contour: inout [VNPoint],
        vertex: VNPoint,
        pIn: VNPoint, pOut: VNPoint,
        tIn: VNPoint, tOut: VNPoint,
        half: Double,
        joinStyle: VNLineJoin,
        miterLimit: Double
    ) {
        switch joinStyle {
        case .miter:
            if let miter = lineIntersect(pIn, tIn, pOut, tOut) {
                let dx = miter.x - vertex.x, dy = miter.y - vertex.y
                if Foundation.sqrt(dx*dx + dy*dy) <= half * miterLimit {
                    contour.append(miter)
                    return
                }
            }
            // Miter limit exceeded → bevel.
            contour.append(pIn)
            contour.append(pOut)

        case .bevel:
            contour.append(pIn)
            contour.append(pOut)

        case .round:
            // Arc from pIn to pOut around vertex.
            // flattenArc emits only the end points of each sub-segment (not the start),
            // so we must append pIn explicitly before the arc call.
            let startAngle = Foundation.atan2(pIn.y - vertex.y, pIn.x - vertex.x)
            let endAngle   = Foundation.atan2(pOut.y - vertex.y, pOut.x - vertex.x)
            // (pIn−vertex) × (pOut−vertex): negative → CW arc, positive → CCW.
            let cx = (pIn.x - vertex.x) * (pOut.y - vertex.y)
                   - (pIn.y - vertex.y) * (pOut.x - vertex.x)
            contour.append(pIn)
            VNBezierFlattener.flattenArc(
                center: vertex, radius: half,
                startAngle: startAngle, endAngle: endAngle,
                clockwise: cx < 0,
                tolerance: 0.1) { contour.append($0) }
        }
    }

    // MARK: - Line intersection helper

    /// Intersection of lines (p1 + t·d1) and (p2 + s·d2), or `nil` if parallel.
    private static func lineIntersect(
        _ p1: VNPoint, _ d1: VNPoint,
        _ p2: VNPoint, _ d2: VNPoint
    ) -> VNPoint? {
        let denom = d1.x * d2.y - d1.y * d2.x
        guard abs(denom) > 1e-10 else { return nil }
        let t = ((p2.x - p1.x) * d2.y - (p2.y - p1.y) * d2.x) / denom
        return VNPoint(x: p1.x + t * d1.x, y: p1.y + t * d1.y)
    }

    // MARK: - Cap helpers

    private static func addCap(
        center: VNPoint, normal: VNPoint, half: Double,
        cap: VNLineCap, atEnd: Bool,
        into result: inout VNPath
    ) {
        let sign: Double = atEnd ? 1 : -1   // direction of the cap tangent
        switch cap {
        case .butt:
            break  // no extra geometry; edges already closed
        case .square:
            // Extend by half along the path direction (perpendicular to normal).
            let tx =  sign * normal.y * half
            let ty = -sign * normal.x * half
            let lpx = center.x + normal.x * half + tx
            let lpy = center.y + normal.y * half + ty
            let rpx = center.x - normal.x * half + tx
            let rpy = center.y - normal.y * half + ty
            if atEnd {
                result.line(to: VNPoint(x: lpx, y: lpy))
                result.line(to: VNPoint(x: rpx, y: rpy))
            } else {
                result.line(to: VNPoint(x: rpx, y: rpy))
                result.line(to: VNPoint(x: lpx, y: lpy))
            }
        case .round:
            let startA = Foundation.atan2(normal.y, normal.x) * sign
            let endA   = startA + .pi
            VNBezierFlattener.flattenArc(
                center: center, radius: half,
                startAngle: startA, endAngle: endA,
                clockwise: !atEnd,
                tolerance: 0.1) { result.line(to: $0) }
        }
    }
}
