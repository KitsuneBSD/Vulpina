/// A window managed by a display-server backend.
///
/// `VNWindow` bridges the core view hierarchy with a backend ``VNSurface``.
/// It owns a `contentView` that fills the window and drives the display
/// cycle: a `.beforeWaiting` observer on the run loop checks whether any
/// view is dirty and, if so, composites the full view tree into a
/// ``VNFramebuffer`` and presents it via the surface.
///
/// Coordinate system: the window's bottom-left is the origin; y increases
/// upward (AppKit convention, D4). The compositor applies the y-flip when
/// mapping view coordinates to the pixel buffer (y-down).
@MainActor
public final class VNWindow {
    // MARK: - Public

    /// The backend surface used to present the framebuffer.
    public let surface: any VNSurface

    /// The root view that fills the window's content area.
    public let contentView: VNView

    /// Size of the window in points.
    public let sizePoints: VNSize

    /// Points-to-pixels scale factor (e.g. 2.0 on HiDPI displays).
    public let backingScale: Double

    // MARK: - Private

    private var _context: VNGraphicsContext
    private var _displayObserver: VNRunLoopObserver?

    // MARK: - Init

    /// Creates a window backed by `surface`.
    ///
    /// - Parameters:
    ///   - surface: The backend surface that presents the composited frame.
    ///   - sizePoints: Window dimensions in points.
    ///   - backingScale: Points-to-pixels ratio (from the backend).
    public init(surface: any VNSurface, sizePoints: VNSize, backingScale: Double) {
        self.surface      = surface
        self.sizePoints   = sizePoints
        self.backingScale = backingScale

        let widthPx  = Int((sizePoints.width  * backingScale).rounded())
        let heightPx = Int((sizePoints.height * backingScale).rounded())
        self._context    = VNGraphicsContext(widthPixels: widthPx,
                                             heightPixels: heightPx,
                                             backingScale: backingScale)
        self.contentView = VNView(frame: VNRect(origin: .zero, size: sizePoints))
    }

    // MARK: - Display lifecycle

    /// Registers the window's display observer on `runLoop` and shows the window.
    ///
    /// Call this once after setting up the view hierarchy. The observer fires
    /// before the run loop sleeps and composites the view tree when dirty.
    ///
    /// - Parameter runLoop: The run loop to attach to. Defaults to ``VNRunLoop/main``.
    public func makeKeyAndOrderFront(runLoop: VNRunLoop = .main) {
        let observer = VNRunLoopObserver(activities: .beforeWaiting) { [weak self] _ in
            self?.display()
        }
        _displayObserver = observer
        runLoop.addObserver(observer)
        // Force an initial draw.
        contentView.setNeedsDisplay()
    }

    /// Composites the view tree and presents the result if any view is dirty.
    ///
    /// Called automatically by the run-loop observer installed in
    /// ``makeKeyAndOrderFront(runLoop:)``. Can also be called manually for
    /// off-screen rendering or testing.
    public func display() {
        guard contentView.needsDisplay else { return }
        _context.clear()
        _displayView(contentView, windowX: 0, windowY: 0)
        surface.present(_context.framebuffer)
    }

    // MARK: - Private compositor

    private func _displayView(_ view: VNView, windowX: Double, windowY: Double) {
        let s = backingScale
        let H = sizePoints.height

        // Pixel-space clip rect for this view (screen coordinates, y-down).
        let pixMinX = Int((windowX * s).rounded())
        let pixMaxX = Int(((windowX + view.frame.width) * s).rounded())
        let pixMinY = Int(((H - windowY - view.frame.height) * s).rounded())
        let pixMaxY = Int(((H - windowY) * s).rounded())

        _context.saveGraphicsState()

        // Translate the CTM so view-local drawing lands at the view's window position.
        // The y-flip (bottom-left → top-left) is applied by VNRasterizer.buildEdges
        // using the full window height in points, so the CTM stays in point-space (y-up).
        _context.translateCTM(tx: view.frame.minX, ty: view.frame.minY)
        _context.setClipPixelBounds(minX: pixMinX, minY: pixMinY,
                                     maxX: pixMaxX, maxY: pixMaxY)

        view.draw(_context)
        view.needsDisplay = false

        // Recurse into subviews (z-order: index 0 = back, last index = top).
        for sub in view.subviews {
            _displayView(sub,
                         windowX: windowX + sub.frame.minX,
                         windowY: windowY + sub.frame.minY)
        }

        _context.restoreGraphicsState()
    }
}
