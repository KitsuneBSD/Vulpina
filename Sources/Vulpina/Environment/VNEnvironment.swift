import Foundation

/// Describes the display-server environment Vulpina runs in and the backend
/// selected for it.
///
/// Detection mirrors the resolution rules of the underlying display protocols:
/// `wl_display_connect(3)` for Wayland and the `DISPLAY` conventions documented
/// in `X(7)` for X11. Backends are tried in a preferred order — X11 first, with
/// Wayland as the fallback, by default — unless `VULPINA_BACKEND` forces a
/// single backend.
public struct VNEnvironment: Sendable, Equatable {

    /// The display server selected for this process.
    public let displayServer: VNDisplayServer

    /// The value of `XDG_SESSION_TYPE`, if set.
    public let sessionType: VNSessionType?

    /// The value of `XDG_CURRENT_DESKTOP`, if set. May contain multiple names
    /// separated by colons (e.g. `"KDE:Plasma"`).
    public let currentDesktop: String?

    /// The value of `XDG_SESSION_DESKTOP`, if set.
    public let sessionDesktop: String?

    /// The raw value of `WAYLAND_DISPLAY`, if set.
    public let waylandDisplay: String?

    /// The Wayland socket path that would be used for a connection, or `nil`
    /// when it cannot be resolved (e.g. a relative display name with no
    /// `XDG_RUNTIME_DIR`) or the connection is supplied through `WAYLAND_SOCKET`.
    public let waylandSocketPath: String?

    /// The raw value of `DISPLAY`, if set.
    public let x11Display: String?

    /// The X11 socket path for the local display, or `nil` for remote displays
    /// or when `DISPLAY` is unset.
    public let x11SocketPath: String?

    /// Detects the environment from the current process.
    public static func detect() -> VNEnvironment {
        let environment = ProcessInfo.processInfo.environment
        return VNEnvironment(
            environment: environment,
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
    }

    /// Builds an environment from an explicit dictionary and file-existence
    /// probe, so detection is fully deterministic and testable.
    ///
    /// - Parameters:
    ///   - environment: The environment to inspect, keyed by variable name.
    ///   - fileExists: Returns whether a path exists on the filesystem.
    ///   - x11SocketDirectory: The directory holding local X11 sockets,
    ///     conventionally `/tmp/.X11-unix`.
    ///   - preferredOrder: The order in which backends are tried when
    ///     `VULPINA_BACKEND` is not forcing a single backend. Defaults to
    ///     `[.x11, .wayland]`.
    init(
        environment: [String: String],
        fileExists: (String) -> Bool,
        x11SocketDirectory: String = "/tmp/.X11-unix",
        preferredOrder: [VNDisplayServer] = [.x11, .wayland]
    ) {
        let x11Display = Self.nonEmpty(environment["DISPLAY"])
        let waylandDisplay = Self.nonEmpty(environment["WAYLAND_DISPLAY"])
        let runtimeDirectory = Self.nonEmpty(environment["XDG_RUNTIME_DIR"])
        let waylandSocket = Self.nonEmpty(environment["WAYLAND_SOCKET"])
        let backendOverride = Self.nonEmpty(environment["VULPINA_BACKEND"])

        let x11SocketPath = x11Display.flatMap {
            Self.x11SocketPath(for: $0, socketDirectory: x11SocketDirectory)
        }
        let waylandSocketPath = Self.waylandSocketPath(
            waylandDisplay: waylandDisplay,
            runtimeDirectory: runtimeDirectory
        )

        let x11Available = Self.isX11Available(
            display: x11Display,
            socketPath: x11SocketPath,
            fileExists: fileExists
        )
        let waylandAvailable = Self.isWaylandAvailable(
            socket: waylandSocket,
            socketPath: waylandSocketPath,
            fileExists: fileExists
        )

        let order = Self.backendOrder(
            override: backendOverride,
            preferredOrder: preferredOrder
        )

        var selected = VNDisplayServer.none
        for backend in order {
            let available: Bool
            switch backend {
            case .wayland:
                available = waylandAvailable
            case .x11:
                available = x11Available
            case .none:
                available = false
            }
            if available {
                selected = backend
                break
            }
        }

        self.displayServer = selected
        self.sessionType = Self.nonEmpty(environment["XDG_SESSION_TYPE"])
            .map { VNSessionType(rawValue: $0) }
        self.currentDesktop = Self.nonEmpty(environment["XDG_CURRENT_DESKTOP"])
        self.sessionDesktop = Self.nonEmpty(environment["XDG_SESSION_DESKTOP"])
        self.waylandDisplay = waylandDisplay
        self.waylandSocketPath = waylandSocketPath
        self.x11Display = x11Display
        self.x11SocketPath = x11SocketPath
    }

    // MARK: - Helpers

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func backendOrder(
        override: String?,
        preferredOrder: [VNDisplayServer]
    ) -> [VNDisplayServer] {
        switch override?.lowercased() {
        case "wayland":
            return [.wayland]
        case "x11":
            return [.x11]
        default:
            return preferredOrder
        }
    }

    private static func x11SocketPath(
        for display: String,
        socketDirectory: String
    ) -> String? {
        guard let number = x11LocalDisplayNumber(for: display) else { return nil }
        let directory = socketDirectory.hasSuffix("/")
            ? String(socketDirectory.dropLast())
            : socketDirectory
        return "\(directory)/X\(number)"
    }

    /// Extracts the display number of a local `DISPLAY` value (`:N`,
    /// `:N.S` or `unix:N`). Returns `nil` for remote (`host:N`) or malformed
    /// values.
    private static func x11LocalDisplayNumber(for display: String) -> Int? {
        let tail: Substring
        if display.hasPrefix("unix:") {
            tail = display.dropFirst("unix:".count)
        } else if display.hasPrefix(":") {
            tail = display.dropFirst(1)
        } else {
            return nil
        }
        let digits = String(tail.prefix { $0.isNumber })
        return digits.isEmpty ? nil : Int(digits)
    }

    private static func isRemoteX11Display(_ display: String) -> Bool {
        display.contains(":") && !display.hasPrefix(":") && !display.hasPrefix("unix:")
    }

    private static func isX11Available(
        display: String?,
        socketPath: String?,
        fileExists: (String) -> Bool
    ) -> Bool {
        guard let display else { return false }
        if let socketPath {
            return fileExists(socketPath)
        }
        return isRemoteX11Display(display)
    }

    /// Resolves the Wayland socket path following `wl_display_connect(3)`:
    /// an absolute `WAYLAND_DISPLAY` is used as-is; a relative name is joined
    /// to `XDG_RUNTIME_DIR`; an unset display falls back to `wayland-0`.
    private static func waylandSocketPath(
        waylandDisplay: String?,
        runtimeDirectory: String?
    ) -> String? {
        let name = waylandDisplay ?? "wayland-0"
        if name.hasPrefix("/") {
            return name
        }
        guard let runtimeDirectory else { return nil }
        let directory = runtimeDirectory.hasSuffix("/")
            ? String(runtimeDirectory.dropLast())
            : runtimeDirectory
        return "\(directory)/\(name)"
    }

    private static func isWaylandAvailable(
        socket: String?,
        socketPath: String?,
        fileExists: (String) -> Bool
    ) -> Bool {
        if socket != nil {
            // WAYLAND_SOCKET supplies an already-open file descriptor, so the
            // socket path itself cannot (and need not) be verified.
            return true
        }
        guard let socketPath else { return false }
        return fileExists(socketPath)
    }
}
