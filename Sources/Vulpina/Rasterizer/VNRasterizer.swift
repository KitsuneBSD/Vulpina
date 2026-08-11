// VNRasterizer: path → edges → analytic coverage → Porter-Duff blit.

enum VNRasterizer {
    /// Fills `path` with `color` into `framebuffer` using `blendMode`.
    ///
    /// - Parameters:
    ///   - path: Path in point-space (bottom-left origin, y-up). Curves are flattened internally.
    ///   - transform: CTM converting point-space to screen-point-space.
    ///   - color: Fill color (straight alpha sRGB).
    ///   - blendMode: Porter-Duff compositing operator.
    ///   - backingScale: Points-to-pixels scale factor.
    ///   - framebuffer: Target pixel buffer (y-down, premultiplied RGBA8).
    static func fill(
        path: VNPath,
        transform: VNAffineTransform,
        color: VNColor,
        blendMode: VNBlendMode,
        backingScale: Double,
        into framebuffer: inout VNFramebuffer
    ) {
        let W = framebuffer.widthPixels
        let H = framebuffer.heightPixels
        guard W > 0 && H > 0 else { return }

        let flatPath = path.flattened(tolerance: 0.1 / backingScale)
        let pointHeight = Double(H) / backingScale
        let edges = buildEdges(path: flatPath, transform: transform,
                               backingScale: backingScale, pointHeight: pointHeight)
        guard !edges.isEmpty else { return }

        blit(edges: edges, windingRule: flatPath.windingRule,
             color: color, blendMode: blendMode,
             W: W, H: H, into: &framebuffer)
    }

    /// Strokes `path` and fills the resulting outline.
    static func stroke(
        path: VNPath,
        transform: VNAffineTransform,
        color: VNColor,
        lineWidth: Double,
        lineCap: VNLineCap,
        lineJoin: VNLineJoin,
        miterLimit: Double,
        blendMode: VNBlendMode,
        backingScale: Double,
        into framebuffer: inout VNFramebuffer
    ) {
        let tolerance = 0.1 / backingScale
        let outline = VNStroker.strokePath(
            path, lineWidth: lineWidth,
            lineCap: lineCap, lineJoin: lineJoin,
            miterLimit: miterLimit,
            flattenTolerance: tolerance)
        fill(path: outline, transform: transform, color: color,
             blendMode: blendMode, backingScale: backingScale, into: &framebuffer)
    }

    // MARK: - Internal blit pipeline

    private static func blit(
        edges: [_VNEdge], windingRule: VNWindingRule,
        color: VNColor, blendMode: VNBlendMode,
        W: Int, H: Int,
        into framebuffer: inout VNFramebuffer
    ) {
        var coverage = [Float](repeating: 0, count: W * H)
        VNAnalyticScanConverter.rasterize(
            edges: edges, width: W, height: H,
            windingRule: windingRule, into: &coverage)

        let srcR = Float(color.red)
        let srcG = Float(color.green)
        let srcB = Float(color.blue)
        let srcA = Float(color.alpha)

        for py in 0..<H {
            for px in 0..<W {
                let cov = VNAnalyticScanConverter.coverageValue(
                    coverage[py * W + px], rule: windingRule)
                guard cov > 0 else { continue }

                let i = framebuffer.byteOffset(x: px, y: py)
                let dR = Float(framebuffer.bytes[i])     / 255
                let dG = Float(framebuffer.bytes[i + 1]) / 255
                let dB = Float(framebuffer.bytes[i + 2]) / 255
                let dA = Float(framebuffer.bytes[i + 3]) / 255

                let (oR, oG, oB, oA) = VNPorterDuffBlitter.blend(
                    srcR: srcR, srcG: srcG, srcB: srcB, srcA: srcA,
                    dstR: dR, dstG: dG, dstB: dB, dstA: dA,
                    coverage: cov, mode: blendMode)

                framebuffer.bytes[i]     = UInt8(max(0, min(255, oR * 255 + 0.5)))
                framebuffer.bytes[i + 1] = UInt8(max(0, min(255, oG * 255 + 0.5)))
                framebuffer.bytes[i + 2] = UInt8(max(0, min(255, oB * 255 + 0.5)))
                framebuffer.bytes[i + 3] = UInt8(max(0, min(255, oA * 255 + 0.5)))
            }
        }
    }

    // MARK: - Edge extraction (flat paths only)

    static func buildEdges(
        path: VNPath,
        transform: VNAffineTransform,
        backingScale: Double,
        pointHeight: Double
    ) -> [_VNEdge] {
        func toPixel(_ p: VNPoint) -> VNPoint {
            let s = transform.applying(to: p)
            return VNPoint(x: s.x * backingScale,
                           y: (pointHeight - s.y) * backingScale)
        }

        var edges: [_VNEdge] = []
        var contourStart: VNPoint? = nil
        var current: VNPoint? = nil

        func addEdge(from a: VNPoint, to b: VNPoint) {
            guard a.y != b.y else { return }
            if a.y < b.y {
                edges.append(_VNEdge(x0: a.x, y0: a.y, x1: b.x, y1: b.y, direction: +1))
            } else {
                edges.append(_VNEdge(x0: b.x, y0: b.y, x1: a.x, y1: a.y, direction: -1))
            }
        }

        for element in path.elements {
            switch element {
            case .moveTo(let p):
                let px = toPixel(p)
                contourStart = px; current = px
            case .lineTo(let p):
                let px = toPixel(p)
                if let cur = current { addEdge(from: cur, to: px) }
                current = px
            case .close:
                if let cur = current, let start = contourStart {
                    addEdge(from: cur, to: start)
                }
                current = contourStart
            case .cubicTo, .quadTo, .arcTo:
                break  // must be pre-flattened
            }
        }
        return edges
    }
}
