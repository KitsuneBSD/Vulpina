/// Immediate-mode drawing context backed by a ``VNFramebuffer``.
///
/// Usage mirrors `NSView.draw(_:)`: the context is passed into a draw method,
/// used synchronously, and discarded. It is NOT `Sendable` — don't store it.
public final class VNGraphicsContext {
    // MARK: - State

    private struct DrawingState {
        var ctm: VNAffineTransform
        var clipPixelBounds: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
    }

    private var stateStack: [DrawingState] = []
    private var state: DrawingState

    // Layer stack for isolated transparency groups (W3C Compositing-1 §9.2).
    // Each entry holds the parent framebuffer and the blend mode used to
    // composite the layer onto it when endTransparencyLayer() is called.
    private struct LayerEntry {
        var parentFramebuffer: VNFramebuffer
        var blendMode: VNBlendMode
    }
    private var layerStack: [LayerEntry] = []

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
        self.state = DrawingState(ctm: .identity, clipPixelBounds: nil)
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

    /// Replaces the current transformation matrix.
    public func setCTM(_ transform: VNAffineTransform) {
        state.ctm = transform
    }

    // MARK: - Clipping

    /// Restricts subsequent drawing to the given pixel-space rectangle.
    ///
    /// The clip is saved and restored with ``saveGraphicsState()`` /
    /// ``restoreGraphicsState()``. Pass `nil` values (or call with no clip) to
    /// draw to the full framebuffer.
    public func setClipPixelBounds(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        state.clipPixelBounds = (minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    /// Removes the current pixel-space clip, allowing drawing to the full framebuffer.
    public func resetClip() {
        state.clipPixelBounds = nil
    }

    // MARK: - Drawing

    /// Fills `path` with `color`.
    public func fill(_ path: VNPath, color: VNColor, blendMode: VNBlendMode = .sourceOver) {
        VNRasterizer.fill(
            path: path, transform: state.ctm,
            color: color, blendMode: blendMode,
            backingScale: backingScale,
            clipBounds: state.clipPixelBounds,
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
            clipBounds: state.clipPixelBounds,
            into: &framebuffer)
    }

    /// Clears the framebuffer to transparent black.
    public func clear() { framebuffer.clear() }

    // MARK: - Isolated transparency groups (W3C Compositing-1 §9.2)

    /// Begins an isolated transparency group.
    ///
    /// All drawing until ``endTransparencyLayer()`` targets a new transparent
    /// framebuffer (transparent black). On `endTransparencyLayer()` the layer
    /// is composited onto the parent framebuffer using `blendMode`.
    ///
    /// Because the group starts transparent, backdrop-dependent operators
    /// (`.sourceIn`, `.destinationIn`, `.sourceAtop`, etc.) applied as the
    /// *first* operation inside the group yield an empty result — matching
    /// the isolated-group semantics of the W3C spec.
    ///
    /// - Parameter blendMode: How the completed layer is composited onto the
    ///   parent. Defaults to `.sourceOver`.
    public func beginTransparencyLayer(blendMode: VNBlendMode = .sourceOver) {
        let layer = VNFramebuffer(widthPixels: framebuffer.widthPixels,
                                  heightPixels: framebuffer.heightPixels)
        layerStack.append(LayerEntry(parentFramebuffer: framebuffer, blendMode: blendMode))
        framebuffer = layer
    }

    /// Ends the current transparency group and composites it onto the parent.
    ///
    /// Each pixel of the completed layer is blended onto the corresponding
    /// parent pixel using the blend mode passed to ``beginTransparencyLayer(blendMode:)``.
    /// Both buffers are in premultiplied RGBA8, so `blendPremul` is used directly.
    public func endTransparencyLayer() {
        guard let entry = layerStack.last else { return }
        layerStack.removeLast()

        let layer  = framebuffer
        var parent = entry.parentFramebuffer
        let count  = parent.widthPixels * parent.heightPixels

        layer.bytes.withUnsafeBytes { srcBytes in
            let src = srcBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
            for i in 0..<count {
                let o  = i &* 4
                let sr = Float(src[o])     / 255
                let sg = Float(src[o &+ 1]) / 255
                let sb = Float(src[o &+ 2]) / 255
                let sa = Float(src[o &+ 3]) / 255
                let dr = Float(parent.bytes[o])     / 255
                let dg = Float(parent.bytes[o &+ 1]) / 255
                let db = Float(parent.bytes[o &+ 2]) / 255
                let da = Float(parent.bytes[o &+ 3]) / 255
                let out = VNPorterDuffBlitter.blendPremul(
                    sr: sr, sg: sg, sb: sb, sa: sa,
                    dr: dr, dg: dg, db: db, da: da,
                    mode: entry.blendMode)
                parent.bytes[o]     = UInt8(min(255, out.r * 255 + 0.5))
                parent.bytes[o &+ 1] = UInt8(min(255, out.g * 255 + 0.5))
                parent.bytes[o &+ 2] = UInt8(min(255, out.b * 255 + 0.5))
                parent.bytes[o &+ 3] = UInt8(min(255, out.a * 255 + 0.5))
            }
        }

        framebuffer = parent
    }
}
