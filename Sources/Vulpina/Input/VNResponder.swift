/// The base class for objects that participate in the responder chain.
///
/// Subclass `VNResponder` (or its concrete subclass ``VNView``) and override
/// event-handling methods to receive input. Unhandled events are forwarded to
/// ``nextResponder``, propagating up the chain until someone handles them.
///
/// The responder chain in Vulpina mirrors AppKit's `NSResponder`:
/// `VNView → superview → … → contentView → VNWindow`
@MainActor
open class VNResponder {
    /// Creates a new responder.
    public init() {}

    // MARK: - Chain

    /// The next responder in the chain, or `nil` at the end.
    ///
    /// ``VNView`` overrides this to return its `superview`.
    open var nextResponder: VNResponder? { nil }

    // MARK: - Mouse events

    open func mouseDown(with event: VNEvent) {
        nextResponder?.mouseDown(with: event)
    }
    open func mouseUp(with event: VNEvent) {
        nextResponder?.mouseUp(with: event)
    }
    open func mouseMoved(with event: VNEvent) {
        nextResponder?.mouseMoved(with: event)
    }
    open func mouseDragged(with event: VNEvent) {
        nextResponder?.mouseDragged(with: event)
    }
    open func rightMouseDown(with event: VNEvent) {
        nextResponder?.rightMouseDown(with: event)
    }
    open func rightMouseUp(with event: VNEvent) {
        nextResponder?.rightMouseUp(with: event)
    }
    open func rightMouseDragged(with event: VNEvent) {
        nextResponder?.rightMouseDragged(with: event)
    }

    // MARK: - Scroll

    open func scrollWheel(with event: VNEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    // MARK: - Key events

    open func keyDown(with event: VNEvent) {
        nextResponder?.keyDown(with: event)
    }
    open func keyUp(with event: VNEvent) {
        nextResponder?.keyUp(with: event)
    }

    // MARK: - First responder

    /// Whether this responder is willing to become first responder.
    ///
    /// Override and return `true` in views that should receive keyboard events.
    open var acceptsFirstResponder: Bool { false }

    /// Called by ``VNWindow/makeFirstResponder(_:)`` before this responder gains focus.
    ///
    /// - Returns: `true` to allow becoming first responder.
    open func becomeFirstResponder() -> Bool { true }

    /// Called by ``VNWindow/makeFirstResponder(_:)`` before this responder loses focus.
    ///
    /// - Returns: `true` to allow resigning.
    open func resignFirstResponder() -> Bool { true }
}
