import Testing
@testable import Vulpina

// MARK: - W3C Porter-Duff matrix (Compositing and Blending Level 1, §9.1)
//
// Expected values are computed from the spec's general formula
// (Compositing-1 §6):
//
//     Co = αs × Fa × Cs + αb × Fb × Cb
//     αo = αs × Fa + αb × Fb
//
// with the (Fa, Fb) pair of each operator from §9.1.x. VNPorterDuffBlitter
// consumes straight-alpha src + premultiplied dst, so the expected
// premultiplied output is sr·Fa + dst·Fb per channel (sr = αs·Cs).
//
// Fixed non-trivial case (srcA ≠ dstA on purpose — several operators are only
// distinguishable from each other when the alphas differ, and no test
// previously exercised the full formula; this gap caused IMM-4 to be
// misreported as a bug):
//
//     Source (straight): Cs = (0.8, 0.2, 0.4), αs = 0.6
//         → premultiplied src = (0.48, 0.12, 0.24)
//     Destination (premultiplied): (0.3, 0.1, 0.05), αb = 0.4
//         → straight Cb = (0.75, 0.25, 0.125)

@Suite("VNBlendMode W3C matrix")
struct W3CBlendMatrixTests {
    private let srcR: Float = 0.8
    private let srcG: Float = 0.2
    private let srcB: Float = 0.4
    private let srcA: Float = 0.6
    private let dstR: Float = 0.3
    private let dstG: Float = 0.1
    private let dstB: Float = 0.05
    private let dstA: Float = 0.4

    /// Blends the fixed src/dst and asserts every channel against the
    /// expected premultiplied RGBA (computed by hand from W3C §6/§9.1).
    private func assertBlend(
        _ mode: VNBlendMode,
        _ expected: (r: Float, g: Float, b: Float, a: Float),
        coverage: Float = 1,
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) {
        let (r, g, b, a) = VNPorterDuffBlitter.blend(
            srcR: srcR, srcG: srcG, srcB: srcB, srcA: srcA,
            dstR: dstR, dstG: dstG, dstB: dstB, dstA: dstA,
            coverage: coverage, mode: mode)
        #expect(abs(r - expected.r) < 0.001, "R: got \(r), expected \(expected.r)", sourceLocation: sourceLocation)
        #expect(abs(g - expected.g) < 0.001, "G: got \(g), expected \(expected.g)", sourceLocation: sourceLocation)
        #expect(abs(b - expected.b) < 0.001, "B: got \(b), expected \(expected.b)", sourceLocation: sourceLocation)
        #expect(abs(a - expected.a) < 0.001, "A: got \(a), expected \(expected.a)", sourceLocation: sourceLocation)
    }

    @Test("clear — W3C §9.1.1 (Fa=0, Fb=0)")
    func clear() {
        assertBlend(.clear, (0, 0, 0, 0))
    }

    @Test("copy — W3C §9.1.2 (Fa=1, Fb=0)")
    func copy() {
        assertBlend(.copy, (0.48, 0.12, 0.24, 0.60))
    }

    @Test("sourceOver — W3C §9.1.4 (Fa=1, Fb=1−αs)")
    func sourceOver() {
        assertBlend(.sourceOver, (0.60, 0.16, 0.26, 0.76))
    }

    @Test("destinationOver — W3C §9.1.5 (Fa=1−αb, Fb=1)")
    func destinationOver() {
        assertBlend(.destinationOver, (0.588, 0.172, 0.194, 0.76))
    }

    @Test("sourceIn — W3C §9.1.6 (Fa=αb, Fb=0)")
    func sourceIn() {
        assertBlend(.sourceIn, (0.192, 0.048, 0.096, 0.24))
    }

    @Test("destinationIn — W3C §9.1.7 (Fa=0, Fb=αs)")
    func destinationIn() {
        assertBlend(.destinationIn, (0.18, 0.06, 0.03, 0.24))
    }

    @Test("sourceOut — W3C §9.1.8 (Fa=1−αb, Fb=0)")
    func sourceOut() {
        assertBlend(.sourceOut, (0.288, 0.072, 0.144, 0.36))
    }

    @Test("destinationOut — W3C §9.1.9 (Fa=0, Fb=1−αs)")
    func destinationOut() {
        assertBlend(.destinationOut, (0.12, 0.04, 0.02, 0.16))
    }

    @Test("sourceAtop — W3C §9.1.10 (Fa=αb, Fb=1−αs)")
    func sourceAtop() {
        assertBlend(.sourceAtop, (0.312, 0.088, 0.116, 0.40))
    }

    @Test("destinationAtop — W3C §9.1.11 (Fa=1−αb, Fb=αs)")
    func destinationAtop() {
        // This is the operator that IMM-4 claimed was wrong. Verified against
        // the spec: the code is correct (IMM-4 was a false positive).
        assertBlend(.destinationAtop, (0.468, 0.132, 0.174, 0.60))
    }

    @Test("xor — W3C §9.1.12 (Fa=1−αb, Fb=1−αs)")
    func xor() {
        assertBlend(.xor, (0.408, 0.112, 0.164, 0.52))
    }

    @Test("plusLighter — W3C §9.1.13 (Fa=1, Fb=1, clamp)")
    func plusLighter() {
        assertBlend(.plusLighter, (0.78, 0.22, 0.29, 1.00))
    }

    @Test("coverage scales the source exactly like alpha")
    func coverageActsLikeAlpha() {
        // coverage 0.5 → αs' = 0.3, premultiplied src' = (0.24, 0.06, 0.12).
        // sourceOver over the same dst: Co = src' + dst·(1−0.3).
        assertBlend(.sourceOver, (0.45, 0.13, 0.155, 0.58), coverage: 0.5)
    }

    @Test("destinationAtop over transparent destination equals copy")
    func destinationAtopTransparentDstEqualsCopy() {
        // αb = 0 → Fa = 1, Fb = αs; dst color is 0 → result is the source alone.
        let (r, g, b, a) = VNPorterDuffBlitter.blend(
            srcR: 0.8, srcG: 0.2, srcB: 0.4, srcA: 0.6,
            dstR: 0, dstG: 0, dstB: 0, dstA: 0,
            coverage: 1, mode: .destinationAtop)
        #expect(abs(r - 0.48) < 0.001)
        #expect(abs(g - 0.12) < 0.001)
        #expect(abs(b - 0.24) < 0.001)
        #expect(abs(a - 0.60) < 0.001)
    }

    @Test("destinationAtop with transparent source clears")
    func destinationAtopTransparentSrcClears() {
        // αs = 0 → sa = 0; both terms vanish → transparent.
        let (r, g, b, a) = VNPorterDuffBlitter.blend(
            srcR: 0.8, srcG: 0.2, srcB: 0.4, srcA: 0,
            dstR: 0.3, dstG: 0.1, dstB: 0.05, dstA: 0.4,
            coverage: 1, mode: .destinationAtop)
        #expect(abs(r) < 0.001)
        #expect(abs(g) < 0.001)
        #expect(abs(b) < 0.001)
        #expect(abs(a) < 0.001)
    }
}
