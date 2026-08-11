/// Immediate-mode drawing context backed by a ``VNFramebuffer``.
///
/// Usage mirrors `NSView.draw(_:)`: the context is passed into a draw method,
/// used synchronously, and discarded. It is NOT `Sendable` — don't store it.
public final class VNGraphicsContext {
    // MARK: - State

    private struct DrawingState {
        var ctm: VNAffineTransform
    }

    private var stateStack: [DrawingState] = []
    private var state: DrawingState

    // MARK: - Public properties

    public private(set) var framebuffer: VNFramebuffer
    /// Points × backingScale = pixels.
    public let backingScale: Double

    // MARK: - Init

    /// Creates a context of the given pixel dimensions.
    ///
    /// - Parameters:
    ///   - widthPixels: Framebuffer width in pixels.
    ///   - heightPixels: Framebuffer height in pixels.
    ///   - backingScale: Points-to-pixels ratio (1 = 1:1, 2 = HiDPI @2x).
    public init(widthPixels: Int, heightPixels: Int, backingScale: Double = 1.0) {
        self.framebuffer = VNFramebuffer(widthPixels: widthPixels, heightPixels: heightPixels)
        self.backingScale = backingScale
        self.state = DrawingState(ctm: .identity)
    }

    // MARK: - State stack

    /// Pushes the current graphics state onto the stack.
    public func saveGraphicsState() {
        stateStack.append(state)
    }

    /// Pops the last saved graphics state.
    public func restoreGraphicsState() {
        guard !stateStack.isEmpty else { return }
        state = stateStack.removeLast()
    }

    // MARK: - CTM

    public func translateCTM(tx: Double, ty: Double) {
        state.ctm = state.ctm.concatenating(.translation(x: tx, y: ty))
    }

    public func scaleCTM(sx: Double, sy: Double) {
        state.ctm = state.ctm.concatenating(.scale(x: sx, y: sy))
    }

    public func rotateCTM(angle: Double) {
        state.ctm = state.ctm.concatenating(.rotation(angle: angle))
    }

    // MARK: - Drawing

    /// Fills `path` with `color`.
    public func fill(_ path: VNPath, color: VNColor, blendMode: VNBlendMode = .sourceOver) {
        VNRasterizer.fill(
            path: path, transform: state.ctm,
            color: color, blendMode: blendMode,
            backingScale: backingScale,
            into: &framebuffer)
    }

    /// Strokes `path` with `color` and the given line attributes.
    public func stroke(
        _ path: VNPath,
        color: VNColor,
        lineWidth: Double,
        lineCap: VNLineCap = .butt,
        lineJoin: VNLineJoin = .miter,
        miterLimit: Double = 10,
        blendMode: VNBlendMode = .sourceOver
    ) {
        VNRasterizer.stroke(
            path: path, transform: state.ctm,
            color: color, lineWidth: lineWidth,
            lineCap: lineCap, lineJoin: lineJoin,
            miterLimit: miterLimit, blendMode: blendMode,
            backingScale: backingScale,
            into: &framebuffer)
    }

    /// Clears the framebuffer to transparent black.
    public func clear() { framebuffer.clear() }
}
