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
    public private(set) var sizePoints: VNSize

    /// Points-to-pixels scale factor (e.g. 2.0 on HiDPI displays).
    public let backingScale: Double

    /// The current first responder, or `nil` if none.
    public private(set) weak var firstResponder: VNResponder?

    // MARK: - Private

    private var _context: VNGraphicsContext
    private var _displayObserver: VNRunLoopObserver?

    /// Tracks the view that received the most recent mouseDown (for drag/up routing).
    private weak var _mouseDownTarget: VNView?
    /// Tracks the view that received the most recent rightMouseDown.
    private weak var _rightMouseDownTarget: VNView?

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

        // Notify when the window's pixels are stale (Expose, resize).
        surface.onNeedsRedraw = { [weak self] in
            self?.contentView.setNeedsDisplay()
        }
        surface.onResize = { [weak self] size in
            self?.resize(to: size)
        }

        // Route backend input events through the responder chain.
        surface.onEvent = { [weak self] event in
            self?.sendEvent(event)
        }

        contentView.setNeedsDisplay()
    }

    /// Stops observing `runLoop` and detaches surface callbacks.
    ///
    /// Call this before releasing a window that has been made visible.
    public func close(runLoop: VNRunLoop = .main) {
        if let observer = _displayObserver {
            runLoop.removeObserver(observer)
            _displayObserver = nil
        }
        surface.onNeedsRedraw = nil
        surface.onResize = nil
        surface.onEvent = nil
    }

    /// Updates the window geometry after a backend resize.
    ///
    /// - Parameter sizePoints: New size in logical points.
    public func resize(to sizePoints: VNSize) {
        guard sizePoints != self.sizePoints else { return }
        self.sizePoints = sizePoints
        contentView.frame = VNRect(origin: .zero, size: sizePoints)
        _context = VNGraphicsContext(
            widthPixels: Int((sizePoints.width * backingScale).rounded()),
            heightPixels: Int((sizePoints.height * backingScale).rounded()),
            backingScale: backingScale)
        contentView.setNeedsDisplay()
    }

    /// Composites the view tree and presents the result if any view is dirty.
    ///
    /// Called automatically by the run-loop observer. Can be called manually for
    /// off-screen rendering or in tests.
    public func display() {
        guard contentView.needsDisplay else { return }
        _context.clear()
        _displayView(contentView, windowX: 0, windowY: 0)
        surface.present(_context.framebuffer)
    }

    // MARK: - First responder

    /// Attempts to make `responder` the first responder.
    ///
    /// - Returns: `true` if the transition succeeded.
    @discardableResult
    public func makeFirstResponder(_ responder: VNResponder?) -> Bool {
        guard responder !== firstResponder else { return true }
        if let old = firstResponder {
            guard old.resignFirstResponder() else { return false }
        }
        if let new = responder {
            guard new.becomeFirstResponder() else { return false }
        }
        firstResponder = responder
        return true
    }

    // MARK: - Event dispatch

    /// Dispatches an event through the responder chain.
    ///
    /// Mouse events are routed by hit-testing the content view; keyboard events
    /// go to the first responder. Unhandled events are silently dropped.
    public func sendEvent(_ event: VNEvent) {
        switch event.type {

        case .mouseDown:
            let target = contentView.hitTest(event.locationInWindow)
            _mouseDownTarget = target
            target?.mouseDown(with: event)
            if let t = target, t.acceptsFirstResponder {
                makeFirstResponder(t)
            }

        case .mouseUp:
            (_mouseDownTarget ?? contentView).mouseUp(with: event)
            _mouseDownTarget = nil

        case .mouseDragged:
            (_mouseDownTarget ?? contentView).mouseDragged(with: event)

        case .mouseMoved:
            contentView.hitTest(event.locationInWindow)?.mouseMoved(with: event)

        case .rightMouseDown:
            let target = contentView.hitTest(event.locationInWindow)
            _rightMouseDownTarget = target
            target?.rightMouseDown(with: event)

        case .rightMouseUp:
            (_rightMouseDownTarget ?? contentView).rightMouseUp(with: event)
            _rightMouseDownTarget = nil

        case .rightMouseDragged:
            (_rightMouseDownTarget ?? contentView).rightMouseDragged(with: event)

        case .scrollWheel:
            contentView.hitTest(event.locationInWindow)?.scrollWheel(with: event)

        case .keyDown:
            (firstResponder ?? contentView).keyDown(with: event)

        case .keyUp:
            (firstResponder ?? contentView).keyUp(with: event)
        }
    }

    // MARK: - Private compositor

    private func _displayView(_ view: VNView, windowX: Double, windowY: Double) {
        let s = backingScale
        let H = sizePoints.height

        let pixMinX = Int((windowX * s).rounded())
        let pixMaxX = Int(((windowX + view.frame.width) * s).rounded())
        let pixMinY = Int(((H - windowY - view.frame.height) * s).rounded())
        let pixMaxY = Int(((H - windowY) * s).rounded())

        _context.saveGraphicsState()
        _context.translateCTM(tx: view.frame.minX, ty: view.frame.minY)
        _context.setClipPixelBounds(minX: pixMinX, minY: pixMinY,
                                     maxX: pixMaxX, maxY: pixMaxY)

        view.draw(_context)
        view.needsDisplay = false

        for sub in view.subviews {
            _displayView(sub,
                         windowX: windowX + sub.frame.minX,
                         windowY: windowY + sub.frame.minY)
        }

        _context.restoreGraphicsState()
    }
}
