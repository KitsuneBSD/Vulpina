import Foundation

// Analytic anti-aliasing scan converter (straight edges, M3a).
//
// Algorithm: for each edge, for each pixel it overlaps, compute the exact
// signed area to the LEFT of the edge within the pixel cell using the trapezoid
// integral of clamp(u(v), 0, 1). Accumulate into a per-pixel signed-area buffer;
// apply winding rule to derive coverage in [0, 1].
//
// Reference: stb_truetype signed-area AA, Skia SkScan_AAAPath, FreeType smooth.

struct _VNEdge {
    let x0, y0, x1, y1: Double   // pixel-space, y-down; y0 < y1 always
    let direction: Double          // +1 or -1 (winding contribution)
}

enum VNAnalyticScanConverter {
    /// Rasterizes `edges` into `coverage` (width × height signed-area buffer).
    /// Caller must zero `coverage` before the call.
    static func rasterize(
        edges: [_VNEdge],
        width: Int, height: Int,
        windingRule: VNWindingRule,
        into coverage: inout [Float]
    ) {
        for edge in edges {
            processEdge(edge, width: width, height: height, coverage: &coverage)
        }
    }

    /// Converts accumulated signed area to coverage value [0, 1].
    @inline(__always)
    static func coverageValue(_ signedArea: Float, rule: VNWindingRule) -> Float {
        switch rule {
        case .nonZero:
            return min(1, abs(signedArea))
        case .evenOdd:
            let v = abs(signedArea).truncatingRemainder(dividingBy: 2)
            return v > 1 ? Float(2) - v : v
        }
    }

    // MARK: - Private

    private static func processEdge(
        _ edge: _VNEdge,
        width: Int, height: Int,
        coverage: inout [Float]
    ) {
        let yStart = max(0, Int(edge.y0))
        let yEnd   = min(height, Int(ceil(edge.y1)))
        guard yEnd > yStart else { return }

        let totalDy = edge.y1 - edge.y0
        guard totalDy > 0 else { return }

        for py in yStart..<yEnd {
            let rowTop = Double(py), rowBot = Double(py + 1)
            let clipTop = max(edge.y0, rowTop)
            let clipBot = min(edge.y1, rowBot)
            let H = clipBot - clipTop
            guard H > 0 else { continue }

            let t0 = (clipTop - edge.y0) / totalDy
            let t1 = (clipBot - edge.y0) / totalDy
            let xa = edge.x0 + t0 * (edge.x1 - edge.x0)
            let xb = edge.x0 + t1 * (edge.x1 - edge.x0)

            let xMin = min(xa, xb)
            let xMax = max(xa, xb)
            let colStart = max(0, Int(xMin))
            let colEnd   = min(width - 1, Int(xMax))

            if colStart <= colEnd {
                for px in colStart...colEnd {
                    let u0 = xa - Double(px)
                    let u1 = xb - Double(px)
                    let area = _areaToLeft(u0: u0, u1: u1, H: H)
                    coverage[py * width + px] += Float(edge.direction * area)
                }
            }

            // Pixels fully to the left of colStart get full-height contribution.
            if colStart > 0 {
                let fullContrib = Float(edge.direction * H)
                for px in 0..<min(colStart, width) {
                    coverage[py * width + px] += fullContrib
                }
            }
        }
    }

    /// Integral of clamp(u(v), 0, 1) dv from v=0 to v=H,
    /// where u(v) = u0 + v*(u1-u0)/H (linear in v).
    ///
    /// This equals the area to the LEFT of the edge segment within the pixel column.
    /// Exposed as `internal` so tests can verify the formula directly.
    @inline(__always)
    static func _areaToLeft(u0: Double, u1: Double, H: Double) -> Double {
        guard H > 0 else { return 0 }

        func clampU(_ v: Double) -> Double {
            let u = u0 + v * (u1 - u0) / H
            return u < 0 ? 0 : (u > 1 ? 1 : u)
        }

        // Collect break-points where u crosses 0 or 1 within (0, H).
        var breaks: [Double] = [0, H]
        if u0 != u1 {
            let inv = H / (u1 - u0)
            let v0 = -u0 * inv          // v where u = 0
            let v1 = (1 - u0) * inv     // v where u = 1
            if v0 > 0 && v0 < H { breaks.append(v0) }
            if v1 > 0 && v1 < H { breaks.append(v1) }
        }
        breaks.sort()

        // Integrate piecewise using the trapezoid rule on the clamped (linear) function.
        var area = 0.0
        for i in 0..<(breaks.count - 1) {
            let va = breaks[i], vb = breaks[i + 1]
            area += (vb - va) * (clampU(va) + clampU(vb)) * 0.5
        }
        return area
    }
}
