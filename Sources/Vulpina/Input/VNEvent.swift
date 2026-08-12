/// Keyboard modifier key flags.
public struct VNModifierFlags: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let shift    = VNModifierFlags(rawValue: 1 << 0)
    public static let control  = VNModifierFlags(rawValue: 1 << 1)
    public static let option   = VNModifierFlags(rawValue: 1 << 2)  // Alt on Linux
    public static let command  = VNModifierFlags(rawValue: 1 << 3)  // Super/Meta
    public static let capsLock = VNModifierFlags(rawValue: 1 << 4)
}

/// The category of a ``VNEvent``.
public enum VNEventType: Sendable {
    case mouseDown, mouseUp, mouseMoved, mouseDragged
    case rightMouseDown, rightMouseUp, rightMouseDragged
    case scrollWheel
    case keyDown, keyUp
}

/// An input event delivered to the responder chain.
///
/// `VNEvent` is an immutable value type. Backends create events and pass them
/// to ``VNWindow/sendEvent(_:)``; views receive them via the responder chain.
///
/// Mouse coordinates are always in **window space** (bottom-left origin, y-up,
/// in points). Use ``VNView/convert(_:from:)`` to convert to a view's local space.
public struct VNEvent: Sendable {
    /// The kind of input this event represents.
    public let type: VNEventType

    /// Mouse position in window coordinates (bottom-left origin, y-up).
    ///
    /// Meaningful for all mouse and scroll events; `.zero` for key events.
    public let locationInWindow: VNPoint

    /// Horizontal scroll delta in points. Positive = scroll right.
    public let scrollDeltaX: Double

    /// Vertical scroll delta in points. Positive = scroll up (natural scrolling).
    public let scrollDeltaY: Double

    /// Platform key code (X11 keycode, hardware scancode). Stable across locales.
    public let keyCode: UInt16

    /// Printable character(s) produced by this key event, or `""`.
    public let characters: String

    /// Active modifier keys at the time of the event.
    public let modifierFlags: VNModifierFlags

    /// Number of consecutive clicks (1 = single, 2 = double, …).
    public let clickCount: Int

    public init(
        type: VNEventType,
        locationInWindow: VNPoint = .zero,
        scrollDeltaX: Double = 0,
        scrollDeltaY: Double = 0,
        keyCode: UInt16 = 0,
        characters: String = "",
        modifierFlags: VNModifierFlags = [],
        clickCount: Int = 1
    ) {
        self.type             = type
        self.locationInWindow = locationInWindow
        self.scrollDeltaX     = scrollDeltaX
        self.scrollDeltaY     = scrollDeltaY
        self.keyCode          = keyCode
        self.characters       = characters
        self.modifierFlags    = modifierFlags
        self.clickCount       = clickCount
    }
}
