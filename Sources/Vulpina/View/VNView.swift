/// A rectangular region that displays content and handles events.
///
/// `VNView` is the base class for all Vulpina visual elements, mirroring
/// `NSView` from AppKit. Subclass it and override ``draw(_:)`` to provide
/// custom rendering.
///
/// Coordinate system: `isFlipped == false` (AppKit default) means the origin
/// is at the bottom-left of the view and y increases upward. The compositor
/// handles the y-flip when presenting to the screen.
///
/// The view hierarchy is retained: each view strongly references its subviews.
/// `superview` is a weak back-reference.
@MainActor
open class VNView {
    // MARK: - Geometry

    /// The view's frame rectangle in its superview's coordinate space (points).
    public var frame: VNRect {
        didSet { setNeedsDisplay() }
    }

    /// The view's bounds rectangle in its own coordinate space (points).
    ///
    /// The origin is always `.zero`; the size matches `frame.size`.
    public var bounds: VNRect { VNRect(origin: .zero, size: frame.size) }

    /// When `false` (default), the coordinate origin is at the bottom-left and
    /// y increases upward (AppKit convention).
    public var isFlipped: Bool = false

    // MARK: - Hierarchy

    /// The view's child views, in back-to-front z-order (last is on top).
    public private(set) var subviews: [VNView] = []

    /// The parent view. `nil` for the root view or a detached view.
    public private(set) weak var superview: VNView?

    // MARK: - Display

    /// `true` if the view needs to be redrawn on the next display pass.
    ///
    /// Set via ``setNeedsDisplay()``. Cleared by the compositor after drawing.
    public internal(set) var needsDisplay: Bool = true

    // MARK: - Init

    /// Creates a view with the given frame rectangle.
    public init(frame: VNRect) {
        self.frame = frame
    }

    // MARK: - Drawing

    /// Override to draw the view's content into `context`.
    ///
    /// The context's coordinate system is set up so that drawing in the view's
    /// local coordinate space (origin bottom-left, y-up) produces correct output.
    /// Do not call `super.draw(_:)` unless you want the default no-op.
    open func draw(_ context: VNGraphicsContext) {}

    /// Marks the view as needing redisplay and propagates the flag upward.
    ///
    /// The view (and its ancestors) will be redrawn on the next display pass.
    public func setNeedsDisplay() {
        needsDisplay = true
        superview?.setNeedsDisplay()
    }

    // MARK: - Hierarchy management

    /// Adds `view` as the topmost subview.
    ///
    /// If `view` already has a superview, it is removed first.
    public func addSubview(_ view: VNView) {
        view.removeFromSuperview()
        subviews.append(view)
        view.superview = self
        setNeedsDisplay()
    }

    /// Removes the view from its superview.
    public func removeFromSuperview() {
        guard let sv = superview else { return }
        sv.subviews.removeAll { $0 === self }
        superview = nil
        sv.setNeedsDisplay()
    }
}
