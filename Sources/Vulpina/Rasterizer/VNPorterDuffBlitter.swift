// Porter-Duff compositing on premultiplied RGBA8 (D23, D24).
// All math done in Float [0,1]; inputs/outputs are UInt8 [0,255] premultiplied.

enum VNPorterDuffBlitter {
    /// Blends `src` (straight alpha, from VNColor) over `dst` (premultiplied) at the given
    /// coverage [0,1] and writes back as premultiplied RGBA8.
    @inline(__always)
    static func blend(
        srcR: Float, srcG: Float, srcB: Float, srcA: Float,
        dstR: Float, dstG: Float, dstB: Float, dstA: Float,
        coverage: Float,
        mode: VNBlendMode
    ) -> (r: Float, g: Float, b: Float, a: Float) {
        // Premultiply src and scale by coverage.
        let cov = max(0, min(1, coverage))
        let sa = srcA * cov
        let sr = srcR * sa
        let sg = srcG * sa
        let sb = srcB * sa

        switch mode {
        case .sourceOver:
            let ia = 1 - sa
            return (sr + dstR * ia, sg + dstG * ia, sb + dstB * ia, sa + dstA * ia)
        case .copy:
            return (sr, sg, sb, sa)
        case .clear:
            return (0, 0, 0, 0)
        case .sourceIn:
            return (sr * dstA, sg * dstA, sb * dstA, sa * dstA)
        case .sourceOut:
            let ia = 1 - dstA
            return (sr * ia, sg * ia, sb * ia, sa * ia)
        case .sourceAtop:
            let ia = 1 - sa
            return (sr * dstA + dstR * ia, sg * dstA + dstG * ia, sb * dstA + dstB * ia, dstA)
        case .destinationOver:
            let ia = 1 - dstA
            return (dstR + sr * ia, dstG + sg * ia, dstB + sb * ia, dstA + sa * ia)
        case .destinationIn:
            return (dstR * sa, dstG * sa, dstB * sa, dstA * sa)
        case .destinationOut:
            let ia = 1 - sa
            return (dstR * ia, dstG * ia, dstB * ia, dstA * ia)
        case .destinationAtop:
            let ia = 1 - dstA
            return (dstR * sa + sr * ia, dstG * sa + sg * ia, dstB * sa + sb * ia, sa)
        case .xor:
            let ia = 1 - sa; let ib = 1 - dstA
            return (sr * ib + dstR * ia, sg * ib + dstG * ia, sb * ib + dstB * ia,
                    sa * ib + dstA * ia)
        case .plusLighter:
            return (min(1, sr + dstR), min(1, sg + dstG), min(1, sb + dstB), min(1, sa + dstA))
        }
    }
}
