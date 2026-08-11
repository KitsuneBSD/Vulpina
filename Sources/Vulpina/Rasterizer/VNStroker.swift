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

        // Compute per-segment unit normals (pointing "left" of the direction).
        var normals = [VNPoint]()
        for i in 0..<(n - 1) {
            let dx = points[i+1].x - points[i].x
            let dy = points[i+1].y - points[i].y
            let len = Foundation.sqrt(dx*dx + dy*dy)
            guard len > 1e-10 else { normals.append(VNPoint.zero); continue }
            normals.append(VNPoint(x: -dy / len, y: dx / len))  // left normal
        }

        // Build left and right offset vertices at each point.
        // For a joint between segment i-1 and i, compute the miter/round/bevel join.

        var leftPts  = [VNPoint]()
        var rightPts = [VNPoint]()

        func offsetPoint(base: VNPoint, normal: VNPoint, sign: Double) -> VNPoint {
            VNPoint(x: base.x + sign * half * normal.x, y: base.y + sign * half * normal.y)
        }

        // Start cap (or closed join).
        if closed {
            let joinL = joinPoint(at: points[0], nIn: normals[n-2], nOut: normals[0],
                                  half: half, joinStyle: lineJoin, miterLimit: miterLimit,
                                  side: +1)
            let joinR = joinPoint(at: points[0], nIn: normals[n-2], nOut: normals[0],
                                  half: half, joinStyle: lineJoin, miterLimit: miterLimit,
                                  side: -1)
            leftPts.append(joinL)
            rightPts.append(joinR)
        } else {
            leftPts.append(offsetPoint(base: points[0], normal: normals[0], sign: +1))
            rightPts.append(offsetPoint(base: points[0], normal: normals[0], sign: -1))
        }

        // Interior joints.
        for i in 1..<(n - 1) {
            let jL = joinPoint(at: points[i], nIn: normals[i-1], nOut: normals[i],
                               half: half, joinStyle: lineJoin, miterLimit: miterLimit, side: +1)
            let jR = joinPoint(at: points[i], nIn: normals[i-1], nOut: normals[i],
                               half: half, joinStyle: lineJoin, miterLimit: miterLimit, side: -1)
            leftPts.append(jL)
            rightPts.append(jR)
        }

        // End cap (or closed join).
        if closed {
            // closed: endpoint == startpoint, so no extra needed
        } else {
            let last = n - 1
            leftPts.append(offsetPoint(base: points[last], normal: normals[last-1], sign: +1))
            rightPts.append(offsetPoint(base: points[last], normal: normals[last-1], sign: -1))
        }

        // Assemble the filled outline path.
        // Forward along left, backward along right, connected by caps at ends.
        result.move(to: leftPts[0])
        for pt in leftPts.dropFirst() { result.line(to: pt) }

        if closed {
            result.close()
            // Inner path reversed so it winds opposite to the outer path.
            // With non-zero rule: outer (+1) + inner (-1) = 0 at the center (hole).
            result.move(to: rightPts[rightPts.count - 1])
            for i in stride(from: rightPts.count - 2, through: 0, by: -1) {
                result.line(to: rightPts[i])
            }
            result.close()
        } else {
            // End cap
            addCap(center: points[n-1], normal: normals[n-2], half: half,
                   cap: lineCap, atEnd: true, into: &result)
            // Right side in reverse
            for pt in rightPts.reversed() { result.line(to: pt) }
            // Start cap
            addCap(center: points[0], normal: normals[0], half: half,
                   cap: lineCap, atEnd: false, into: &result)
            result.close()
        }
    }

    // MARK: - Join helpers

    private static func joinPoint(
        at vertex: VNPoint,
        nIn: VNPoint, nOut: VNPoint,
        half: Double,
        joinStyle: VNLineJoin,
        miterLimit: Double,
        side: Double
    ) -> VNPoint {
        let nx = side * (nIn.x + nOut.x)
        let ny = side * (nIn.y + nOut.y)
        let len2 = nx * nx + ny * ny
        guard len2 > 1e-12 else {
            return VNPoint(x: vertex.x + side * half * nIn.x,
                           y: vertex.y + side * half * nIn.y)
        }
        // Miter: scale so that the join is on the offset edge.
        // Use abs(dot) because for the right side (side=-1) the join direction is flipped,
        // making the raw dot negative — the magnitude is what matters.
        let dot = abs((nx / Foundation.sqrt(len2)) * nIn.x + (ny / Foundation.sqrt(len2)) * nIn.y)
        let miterScale: Double
        if joinStyle == .miter && dot > 1e-6 {
            let ratio = 1.0 / dot
            miterScale = ratio <= miterLimit ? ratio : 1.0  // fallback to bevel distance
        } else {
            miterScale = 1.0
        }
        let scale = half * miterScale / Foundation.sqrt(len2)
        return VNPoint(x: vertex.x + nx * scale, y: vertex.y + ny * scale)
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
            // Forward tangent = (normal.y, -normal.x); backward = (-normal.y, normal.x).
            let tx =  sign * normal.y * half
            let ty = -sign * normal.x * half
            let lpx = center.x + normal.x * half + tx
            let lpy = center.y + normal.y * half + ty
            let rpx = center.x - normal.x * half + tx
            let rpy = center.y - normal.y * half + ty
            // For end cap: emit left-extension then right-extension (continuing along left side).
            // For start cap: emit right-extension then left-extension (connecting from right side).
            if atEnd {
                result.line(to: VNPoint(x: lpx, y: lpy))
                result.line(to: VNPoint(x: rpx, y: rpy))
            } else {
                result.line(to: VNPoint(x: rpx, y: rpy))
                result.line(to: VNPoint(x: lpx, y: lpy))
            }
        case .round:
            // Semicircle from the current offset point around the endpoint.
            let startA = Foundation.atan2(normal.y, normal.x) * sign
            let endA   = startA + .pi
            // Emit via arc-to-cubic approximation using the flattener.
            VNBezierFlattener.flattenArc(
                center: center, radius: half,
                startAngle: startA, endAngle: endA,
                clockwise: !atEnd,
                tolerance: 0.1) { result.line(to: $0) }
        }
    }
}
