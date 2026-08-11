# Vulpina

A graphical toolkit for FoxynOS, Linux and \*BSD, written in Swift and inspired by
Cocoa (AppKit/Foundation). Vulpina provides a modern, ergonomic, platform-agnostic
API for building desktop applications.

## Highlights

- **Cocoa-inspired API** — `VN`-prefixed types mirroring AppKit conventions
  (`VNView`, `VNWindow`, `VNApplication`, `VNRunLoop`, …)
- **Own pure-Swift rasterizer** — analytic anti-aliasing (exact area coverage),
  Porter-Duff compositing, adaptive Bézier flattening, stroke cap/join; no C
  dependencies in the core target
- **Backend-agnostic core** — no display-server code (Wayland, X11, …) in
  `Sources/Vulpina`; concrete backends plug in as separate SwiftPM targets
- **Bottom-left coordinate system** (AppKit style, `isFlipped = false`); HiDPI
  via a `backingScaleFactor` that multiplies points to pixels
- **AppKit-style run loop** — `VNRunLoop` with modes, sources, timers, and
  observers; backends register an event source rather than owning the loop
- **Swift 6 strict concurrency** — UI types are `@MainActor`, value types are
  `Sendable`, no global mutable state

## Status

| Milestone | Status | Detail |
|-----------|--------|--------|
| M1 — Environment | ✅ | X11-first detection, `VULPINA_BACKEND` override |
| M2 — Geometry | ✅ | `VNPoint/Size/Rect/Insets/Color` |
| M3a — Rasterizer (straight edges) | ✅ | Analytic AA, Porter-Duff, `VNGraphicsContext` |
| M3b — Rasterizer (curves) | ✅ | Bézier flatten, stroke, ellipse, even-odd fill |
| M4 — Core backbone | ✅ | `VNRunLoop`, `VNApplication`, `VNBackend`/`VNSurface` |
| M5 — X11 backend | ⚠️ | Next: window + MIT-SHM blit |
| M6 — VNView | ⚠️ | Frame-based layout, draw cycle |
| M7 — Input | ⚠️ | Events, hit-test, responder chain |
| M8 — Text | ⚠️ | Own TTF/OTF parser + TextKit-like layout |
| M9 — Wayland backend | ⚠️ | `wl_shm` blit |
| M10 — Controls / layout | ⚠️ | `VNButton`, autoresizing |
| M11 — Gradients / shadows | ⚠️ | Linear/radial gradients, drop shadows |

**137 tests passing** across geometry, rasterizer (including mathematical invariance),
run loop, and application lifecycle.

## Prerequisites

- Swift 6.3+ (Linux or \*BSD)
- Swift Package Manager (bundled with Swift)

## Build and Test

```bash
make build     # Debug build
make release   # Release build
make test      # Build and run the test suite
make clean     # Remove build artifacts
```

## Architecture overview

The core is layered into four groups:

```
VNApplication + VNApplicationDelegate
      │ owns
VNRunLoop  ←── VNRunLoopSource / Timer / Observer
      │ drives
VNGraphicsContext  ──→  VNFramebuffer  (premultiplied RGBA8)
      │ uses
VNRasterizer  ──→  VNAnalyticScanConverter  ──→  VNPorterDuffBlitter
      │ consumes
VNPath  ←── VNBezierFlattener / VNStroker
      │ built from
VNPoint / VNRect / VNSize / VNInsets / VNColor / VNAffineTransform
```

Backends (`VulpinaX11`, `VulpinaWayland`) conform to `VNBackend` and `VNSurface`
and are never imported by the core.

See `.ai-docs/ARCHITECTURE.md` for detailed design decisions, and
`.ai-docs/ROADMAP.md` for upcoming milestones.

## License

BSD 3-Clause. See `LICENSE`.
