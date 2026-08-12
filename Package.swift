// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Vulpina",
    products: [
        .library(name: "Vulpina",      targets: ["Vulpina"]),
        .library(name: "VulpinaX11",   targets: ["VulpinaX11"]),
        .executable(name: "VulpinaDemo", targets: ["VulpinaDemo"]),
    ],
    targets: [
        // Core — backend-agnostic; never imports ClibX11 / ClibXext.
        .target(name: "Vulpina"),

        // C system-library shims (D7).
        .systemLibrary(name: "ClibX11",   pkgConfig: "x11",
                       providers: [.apt(["libx11-dev"])]),
        .systemLibrary(name: "ClibXext",  pkgConfig: "xext",
                       providers: [.apt(["libxext-dev"])]),

        // X11 backend (M5).
        .target(
            name: "VulpinaX11",
            dependencies: ["Vulpina", "ClibX11", "ClibXext"]
        ),

        // Interactive demo — requires a running X11 display (DISPLAY set).
        .executableTarget(
            name: "VulpinaDemo",
            dependencies: ["Vulpina", "VulpinaX11"]
        ),

        // Tests — only test the backend-agnostic core.
        .testTarget(
            name: "VulpinaTests",
            dependencies: ["Vulpina"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
