import Testing
@testable import Vulpina

struct VNEnvironmentTests {

    private static let x11Sockets = "/tmp/.X11-unix"
    private static let runtimeDir = "/run/user/1000"

    private func makeEnvironment(
        _ values: [String: String],
        existing: Set<String> = [],
        preferredOrder: [VNDisplayServer] = [.x11, .wayland]
    ) -> VNEnvironment {
        VNEnvironment(
            environment: values,
            fileExists: { existing.contains($0) },
            x11SocketDirectory: Self.x11Sockets,
            preferredOrder: preferredOrder
        )
    }

    // MARK: - Selection

    @Test func emptyEnvironmentDetectsNoDisplayServer() {
        let env = makeEnvironment([:])
        #expect(env.displayServer == .none)
        #expect(env.x11Display == nil)
        #expect(env.waylandDisplay == nil)
        #expect(env.sessionType == nil)
    }

    @Test func x11Only() {
        let env = makeEnvironment(
            ["DISPLAY": ":0"],
            existing: ["\(Self.x11Sockets)/X0"]
        )
        #expect(env.displayServer == .x11)
        #expect(env.x11Display == ":0")
        #expect(env.x11SocketPath == "\(Self.x11Sockets)/X0")
    }

    @Test func waylandOnly() {
        let env = makeEnvironment(
            [
                "WAYLAND_DISPLAY": "wayland-0",
                "XDG_RUNTIME_DIR": Self.runtimeDir,
            ],
            existing: ["\(Self.runtimeDir)/wayland-0"]
        )
        #expect(env.displayServer == .wayland)
        #expect(env.waylandDisplay == "wayland-0")
        #expect(env.waylandSocketPath == "\(Self.runtimeDir)/wayland-0")
    }

    @Test func bothAvailablePrefersX11() {
        let env = makeEnvironment(
            [
                "DISPLAY": ":0",
                "WAYLAND_DISPLAY": "wayland-0",
                "XDG_RUNTIME_DIR": Self.runtimeDir,
            ],
            existing: [
                "\(Self.x11Sockets)/X0",
                "\(Self.runtimeDir)/wayland-0",
            ]
        )
        #expect(env.displayServer == .x11)
    }

    @Test func x11PreferredWhenWaylandSocketMissing() {
        let env = makeEnvironment(
            [
                "DISPLAY": ":0",
                "WAYLAND_DISPLAY": "wayland-0",
                "XDG_RUNTIME_DIR": Self.runtimeDir,
            ],
            existing: ["\(Self.x11Sockets)/X0"]
        )
        #expect(env.displayServer == .x11)
    }

    @Test func waylandAsFallbackWhenX11SocketMissing() {
        let env = makeEnvironment(
            [
                "DISPLAY": ":0",
                "WAYLAND_DISPLAY": "wayland-0",
                "XDG_RUNTIME_DIR": Self.runtimeDir,
            ],
            existing: ["\(Self.runtimeDir)/wayland-0"]
        )
        #expect(env.displayServer == .wayland)
    }

    @Test func neitherBackendAvailableYieldsNone() {
        let env = makeEnvironment(
            [
                "DISPLAY": ":0",
                "WAYLAND_DISPLAY": "wayland-0",
                "XDG_RUNTIME_DIR": Self.runtimeDir,
            ]
        )
        #expect(env.displayServer == .none)
    }

    // MARK: - Wayland resolution

    @Test func absoluteWaylandDisplayUsedAsIs() {
        let env = makeEnvironment(
            ["WAYLAND_DISPLAY": "/run/compositor/wayland.sock"],
            existing: ["/run/compositor/wayland.sock"]
        )
        #expect(env.displayServer == .wayland)
        #expect(env.waylandSocketPath == "/run/compositor/wayland.sock")
    }

    @Test func relativeWaylandWithoutRuntimeDirectoryIsUnavailable() {
        let env = makeEnvironment(
            ["WAYLAND_DISPLAY": "wayland-0"],
            existing: ["\(Self.runtimeDir)/wayland-0"]
        )
        #expect(env.displayServer == .none)
        #expect(env.waylandSocketPath == nil)
    }

    @Test func unsetWaylandDisplayFallsBackToDefaultSocketName() {
        let env = makeEnvironment(
            ["XDG_RUNTIME_DIR": Self.runtimeDir],
            existing: ["\(Self.runtimeDir)/wayland-0"]
        )
        #expect(env.displayServer == .wayland)
        #expect(env.waylandSocketPath == "\(Self.runtimeDir)/wayland-0")
    }

    @Test func emptyWaylandDisplayTreatedAsUnset() {
        let env = makeEnvironment(
            [
                "WAYLAND_DISPLAY": "",
                "XDG_RUNTIME_DIR": Self.runtimeDir,
            ],
            existing: ["\(Self.runtimeDir)/wayland-0"]
        )
        #expect(env.displayServer == .wayland)
        #expect(env.waylandSocketPath == "\(Self.runtimeDir)/wayland-0")
    }

    @Test func runtimeDirectoryWithTrailingSlash() {
        let env = makeEnvironment(
            [
                "WAYLAND_DISPLAY": "wayland-0",
                "XDG_RUNTIME_DIR": "\(Self.runtimeDir)/",
            ],
            existing: ["\(Self.runtimeDir)/wayland-0"]
        )
        #expect(env.waylandSocketPath == "\(Self.runtimeDir)/wayland-0")
    }

    @Test func waylandSocketFdCountsAsAvailable() {
        let env = makeEnvironment(["WAYLAND_SOCKET": "5"])
        #expect(env.displayServer == .wayland)
    }

    // MARK: - X11 resolution

    @Test func displayWithScreenNumberMapsToBaseSocket() {
        let env = makeEnvironment(
            ["DISPLAY": ":0.0"],
            existing: ["\(Self.x11Sockets)/X0"]
        )
        #expect(env.displayServer == .x11)
        #expect(env.x11SocketPath == "\(Self.x11Sockets)/X0")
    }

    @Test func unixDisplayMapsToSocket() {
        let env = makeEnvironment(
            ["DISPLAY": "unix:1"],
            existing: ["\(Self.x11Sockets)/X1"]
        )
        #expect(env.displayServer == .x11)
        #expect(env.x11SocketPath == "\(Self.x11Sockets)/X1")
    }

    @Test func remoteDisplayIsAvailableWithoutLocalSocket() {
        let env = makeEnvironment(["DISPLAY": "localhost:10"])
        #expect(env.displayServer == .x11)
        #expect(env.x11SocketPath == nil)
    }

    @Test func malformedLocalDisplayIsNotAvailable() {
        let env = makeEnvironment(
            ["DISPLAY": ":abc"],
            existing: ["\(Self.x11Sockets)/X0"]
        )
        #expect(env.displayServer == .none)
    }

    @Test func emptyDisplayTreatedAsUnset() {
        let env = makeEnvironment(
            ["DISPLAY": ""],
            existing: ["\(Self.x11Sockets)/X0"]
        )
        #expect(env.displayServer == .none)
    }

    // MARK: - Override

    @Test func overrideForcesX11WhenBothAvailable() {
        let env = makeEnvironment(
            [
                "DISPLAY": ":0",
                "WAYLAND_DISPLAY": "wayland-0",
                "XDG_RUNTIME_DIR": Self.runtimeDir,
                "VULPINA_BACKEND": "x11",
            ],
            existing: [
                "\(Self.x11Sockets)/X0",
                "\(Self.runtimeDir)/wayland-0",
            ]
        )
        #expect(env.displayServer == .x11)
    }

    @Test func overrideForcesWaylandWhenBothAvailable() {
        let env = makeEnvironment(
            [
                "DISPLAY": ":0",
                "WAYLAND_DISPLAY": "wayland-0",
                "XDG_RUNTIME_DIR": Self.runtimeDir,
                "VULPINA_BACKEND": "wayland",
            ],
            existing: [
                "\(Self.x11Sockets)/X0",
                "\(Self.runtimeDir)/wayland-0",
            ]
        )
        #expect(env.displayServer == .wayland)
    }

    @Test func overrideToUnavailableWaylandYieldsNone() {
        let env = makeEnvironment(
            [
                "DISPLAY": ":0",
                "VULPINA_BACKEND": "wayland",
            ],
            existing: ["\(Self.x11Sockets)/X0"]
        )
        #expect(env.displayServer == .none)
    }

    @Test func overrideToUnavailableX11YieldsNone() {
        let env = makeEnvironment(
            [
                "WAYLAND_DISPLAY": "wayland-0",
                "XDG_RUNTIME_DIR": Self.runtimeDir,
                "VULPINA_BACKEND": "x11",
            ],
            existing: ["\(Self.runtimeDir)/wayland-0"]
        )
        #expect(env.displayServer == .none)
    }

    @Test func autoOverrideUsesDefaultOrder() {
        let env = makeEnvironment(
            [
                "DISPLAY": ":0",
                "WAYLAND_DISPLAY": "wayland-0",
                "XDG_RUNTIME_DIR": Self.runtimeDir,
                "VULPINA_BACKEND": "auto",
            ],
            existing: [
                "\(Self.x11Sockets)/X0",
                "\(Self.runtimeDir)/wayland-0",
            ]
        )
        #expect(env.displayServer == .x11)
    }

    @Test func unknownOverrideUsesDefaultOrder() {
        let env = makeEnvironment(
            [
                "DISPLAY": ":0",
                "WAYLAND_DISPLAY": "wayland-0",
                "XDG_RUNTIME_DIR": Self.runtimeDir,
                "VULPINA_BACKEND": "vnc",
            ],
            existing: [
                "\(Self.x11Sockets)/X0",
                "\(Self.runtimeDir)/wayland-0",
            ]
        )
        #expect(env.displayServer == .x11)
    }

    // MARK: - Preferred order

    @Test func waylandFirstOrderIsInjectable() {
        let env = makeEnvironment(
            [
                "DISPLAY": ":0",
                "WAYLAND_DISPLAY": "wayland-0",
                "XDG_RUNTIME_DIR": Self.runtimeDir,
            ],
            existing: [
                "\(Self.x11Sockets)/X0",
                "\(Self.runtimeDir)/wayland-0",
            ],
            preferredOrder: [.wayland, .x11]
        )
        #expect(env.displayServer == .wayland)
    }

    // MARK: - Session metadata

    @Test func sessionTypeParsed() {
        let env = makeEnvironment(["XDG_SESSION_TYPE": "wayland"])
        #expect(env.sessionType == .wayland)
    }

    @Test func unknownSessionTypeIsOther() {
        let env = makeEnvironment(["XDG_SESSION_TYPE": "someshell"])
        #expect(env.sessionType == .other("someshell"))
    }

    @Test func missingSessionTypeIsNil() {
        let env = makeEnvironment([:])
        #expect(env.sessionType == nil)
    }

    @Test func desktopMetadataRecorded() {
        let env = makeEnvironment([
            "XDG_CURRENT_DESKTOP": "Hyprland",
            "XDG_SESSION_DESKTOP": "Hyprland",
        ])
        #expect(env.currentDesktop == "Hyprland")
        #expect(env.sessionDesktop == "Hyprland")
    }

    // MARK: - Value semantics

    @Test func environmentsAreComparable() {
        let a = makeEnvironment(
            ["DISPLAY": ":0"],
            existing: ["\(Self.x11Sockets)/X0"]
        )
        let b = makeEnvironment(
            ["DISPLAY": ":0"],
            existing: ["\(Self.x11Sockets)/X0"]
        )
        #expect(a == b)
    }
}
