# Vulpina Development Guide

## Project Identity

Vulpina is a **graphical toolkit for FoxynOS, Linux and *BSD**, written in Swift and
inspired by Cocoa (AppKit/Foundation). It aims to provide a modern, ergonomic,
platform-agnostic API for building desktop applications.

The core is **backend-agnostic**: no display-server-specific code (Wayland, X11, etc.)
belongs in the core target. Concrete backends are isolated and plugged in later.

## Build Commands

```bash
make build       # Debug build (default)
make release     # Release build (-c release)
make test        # Build and run the test suite (Swift Testing)
make clean       # Remove build artifacts
```

Equivalent SwiftPM commands:

```bash
swift build
swift build -c release
swift test
swift package clean
```

Build outputs land in `.build/` (git-ignored).

## Toolchain

- Swift 6.3+ (Swift 6 language mode — strict concurrency)
- `swift-tools-version: 6.3` in `Package.swift`
- Build system: Swift Package Manager
- Test framework: Swift Testing (`@Test`, `#expect`)

## Source Layout

```
Sources/Vulpina/           # Core library target (public API)
Tests/VulpinaTests/        # Unit tests
Package.swift
```

## API Naming (STRICT)

All public API uses the **`VN` prefix**, mirroring Cocoa's `NS`/`UI` convention:

- `VNView`, `VNWindow`, `VNApplication`, `VNButton`, ...

Naming follows Cocoa conventions adapted to Swift:

- Classes for reference-semantics objects (views, windows, application).
- Enums/structs for value types (geometry, colors, events).
- Action/selector style follows AppKit naming (`func action(_ sender: VNAny?)`).

## Conventions

- Swift 6 strict concurrency: types shared across isolation domains must be `Sendable`.
- No global mutable state; prefer explicit dependency injection.
- One type per file; file name matches type name.
- Public API requires doc comments (including `- Parameters:` where relevant).
- Keep the core target free of platform-specific imports (`wayland-client`, X11, etc.).
- Prefer value semantics (structs) for geometry/state; classes only where identity matters.
- Ask before assuming: prefer confirming decisions, scope, and intent with the user before making them (e.g. what enters/exits the TODO.md). Do not silently decide for the user.

## Testing

- Tests use Swift Testing and live in `Tests/VulpinaTests/`.
- Every new public API must ship with tests.
- Run `make test` before finishing any change.

## Verification Checklist

Before concluding any change:

1. `make build` succeeds.
2. `make test` passes.
3. No new platform-specific code leaked into the core target.
