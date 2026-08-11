/// A drawable surface produced by a ``VNBackend``.
///
/// The backend creates surfaces for windows. The core calls ``present(_:)`` after
/// compositing all views into the framebuffer.
public protocol VNSurface: AnyObject {
    /// Presents the framebuffer to the screen.
    ///
    /// - Parameter framebuffer: The composited framebuffer to display.
    @MainActor func present(_ framebuffer: VNFramebuffer)
}

/// A display-server backend (X11, Wayland, …).
///
/// The core never imports display-server-specific modules. Instead, backends
/// conform to `VNBackend` and are injected via ``VNApplication/init(backend:)``.
///
/// Backends must be `@MainActor`-bound because all UI operations are main-thread only.
public protocol VNBackend: AnyObject {
    /// Creates a surface for a new window.
    ///
    /// - Parameters:
    ///   - width: Requested width in pixels.
    ///   - height: Requested height in pixels.
    ///   - title: Window title string.
    /// - Returns: A ``VNSurface`` through which the window content can be presented.
    @MainActor func makeSurface(widthPixels: Int, heightPixels: Int, title: String) -> any VNSurface

    /// The points-to-pixels scale factor for the primary display.
    @MainActor var backingScaleFactor: Double { get }

    /// Registers a run-loop source that wakes up the run loop when display-server
    /// events arrive. Called by ``VNApplication`` during startup.
    ///
    /// - Parameter runLoop: The application's main run loop.
    @MainActor func registerEventSource(with runLoop: VNRunLoop)

    /// Polls or dispatches pending display-server events. Called once per run-loop
    /// iteration (after the event source fires).
    @MainActor func pollEvents()
}
