/// The type of the current desktop session, derived from `XDG_SESSION_TYPE`.
///
/// The known values follow the XDG desktop entry specification (`wayland`,
/// `x11`, `tty`, `mir`) plus `unspecified` for an empty or explicitly
/// `unspecified` value. Any other value is preserved verbatim in `other`.
public enum VNSessionType: Sendable, Equatable, Hashable {
    /// A native Wayland session.
    case wayland

    /// An X11 session.
    case x11

    /// A text/console session (no display server).
    case tty

    /// A Mir session.
    case mir

    /// The value was empty or explicitly `"unspecified"`.
    case unspecified

    /// Any other value, preserved verbatim.
    case other(String)

    /// Creates a session type from the raw `XDG_SESSION_TYPE` value.
    init(rawValue: String?) {
        guard let rawValue, !rawValue.isEmpty else {
            self = .unspecified
            return
        }
        switch rawValue {
        case "wayland":
            self = .wayland
        case "x11":
            self = .x11
        case "tty":
            self = .tty
        case "mir":
            self = .mir
        case "unspecified":
            self = .unspecified
        default:
            self = .other(rawValue)
        }
    }
}
