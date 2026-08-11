/// A display server backend that Vulpina can connect to.
public enum VNDisplayServer: Sendable, Equatable, Hashable {
    /// A Wayland compositor.
    case wayland

    /// An X11 (or XWayland) server.
    case x11

    /// No display server was detected.
    case none
}
