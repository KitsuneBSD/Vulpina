# Vulpina

A graphical toolkit for FoxynOS, Linux and *BSD, written in Swift and inspired by
Cocoa (AppKit/Foundation). Vulpina aims to provide a modern, ergonomic,
platform-agnostic API for building desktop applications.

## Highlights

- Cocoa-inspired API: `VN`-prefixed classes mirroring AppKit conventions (`VNView`,
  `VNWindow`, `VNApplication`)
- Written in modern Swift (Swift 6 language mode, strict concurrency)
- **Backend-agnostic core**: no display-server-specific code (Wayland, X11, ...)
  in the core target; concrete backends are isolated and plugged in later
- Value semantics for geometry/state; reference semantics where identity matters

## Status

Early scaffolding: package structure, build tooling, and testing harness are in
place. Public API is being defined incrementally, one type at a time.

## Prerequisites

- Swift 6.3+ (Linux or *BSD)
- Swift Package Manager (bundled with Swift)

## Build and Test

```bash
make build     # Debug build (default)
make release   # Release build
make test      # Build and run the test suite
make clean     # Remove build artifacts
```

## Roadmap

- Core value types: geometry (points, sizes, rects), colors, events
- View/window hierarchy with frame/layout model
- Application and event-loop primitives
- Controls: buttons, labels, text fields, ...
- Drawing abstraction over the backend surface
- Concrete backends (Wayland, X11) behind the core API

## License

BSD 3-Clause. See `LICENSE`.
