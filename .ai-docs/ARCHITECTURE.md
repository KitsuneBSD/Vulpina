# Architecture

This document records the key technical decisions made during Vulpina's design.
Each decision is numbered (D1–D32) and cross-referenced from `TODO.md`.

---

## Drawing model

**D1 — Own Swift rasterizer**  
Vulpina renders with its own pure-Swift rasterizer (`VNRasterizer → VNFramebuffer`).
No dependency on Cairo, Skia, or any C library in the core target. A `VNRenderer`
protocol is intentionally deferred until a second renderer exists (avoids premature
abstraction). GPU backends (Skia/Vulkan) are a post-M10 concern.

**D16 — Universal vector pipeline**  
Every drawing operation becomes a `VNPath` → edges → spans → pixels. Axis-aligned
rects get a fast-path (row copy), but there is no special bitmap case.

**D17 — Analytic anti-aliasing from day one**  
Coverage is computed as the exact signed area swept by each edge through each pixel
cell (trapezoid integral of `clamp(u(v), 0, 1)`). This matches Skia's `SkScan_AAAPath`
and FreeType's smooth rasterizer. There is no binary (aliased) phase.

**D18 — Scan converter → spans → blitter**  
The pipeline mirrors Skia's `SkScan`/`SkBlitter` and FreeType's smooth module:
geometry is separated from compositing, making converters independently testable.

**D19 — Coverage × alpha are separate**  
Coverage `[0, 1]` is kept separate from the colour's alpha. Compositing is:
`coverage × Blend(src, dst) + (1 − coverage) × dst`. This avoids conflation
artefacts between adjacent primitives.

**D20 — `Double` precision**  
All geometry and scan-converter arithmetic uses `Double`. Fixed-point (24.8 / 16.16,
as in cairo/pixman) is only considered if benchmarks show it necessary.

**D21 — Primitives for v1**  
Filled and stroked versions of: rectangle, rounded rectangle, ellipse/circle, line,
and arbitrary paths. Gradients and shadows are deferred to M11.

**D22 — Non-zero and even-odd winding rules**  
`VNPath.windingRule` mirrors `NSBezierPath.windingRule`.

**D23 — Complete Porter-Duff compositing**  
`VNBlendMode` covers all 12 operators: sourceOver, copy, clear, sourceIn/Out/Atop,
destinationOver/In/Out/Atop, xor, plusLighter.

**D24 — Premultiplied RGBA8 framebuffer**  
Internal storage is premultiplied. Straight (unpremultiplied) alpha only appears at
the X11 blit boundary.

---

## Coordinate system and HiDPI

**D4 — Bottom-left origin (AppKit style)**  
`VNPoint` is in point space, y-up (same as AppKit's `isFlipped = false`). The y-flip
`py = (pointHeight − y) × backingScale` is applied when converting to pixel space.
Backends present the framebuffer top-left; the coordinate flip happens inside the
compositor, invisible to callers.

**D9 — Points + backing scale**  
All public geometry is in points (`Double`). The backing scale factor converts to
pixels: `pixels = points × backingScale`. X11 reads the scale from `Xft.dpi`/RANDR;
Wayland from `wl_output.scale`.

---

## Application and event loop

**D5 — `VNRunLoop` in the core**  
The run loop (modes, sources, timers, observers) lives in the core target, not in
any backend. Backends register an event source (e.g. a display-server file
descriptor) that wakes the loop when events arrive. This mirrors CFRunLoop / AppKit's
`NSRunLoop`.

**D10 — `@MainActor` isolation**  
All UI types (`VNView`, `VNWindow`, `VNApplication`, `VNRunLoop`) are `@MainActor`.
Backends deliver events on the main thread and use `MainActor.assumeIsolated` in
their entry points.

**D11 — Explicit instance + delegate**  
`main.swift` creates `VNApplication(backend:)`, sets a `VNApplicationDelegate`, and
calls `run()`. There is no global shared instance. This satisfies the "no global
mutable state" rule.

---

## Backend and windowing

**D3 — Backends are separate targets**  
`VulpinaX11`, `VulpinaWayland`, and future backends are separate SwiftPM targets in
the same package. The core (`Vulpina`) never imports them.

**D7 — C interop via `systemLibrary`**  
Display-server C libraries are wrapped with `.systemLibrary(pkgConfig:)` +
`module.modulemap`. Modules are prefixed `Clib*` (e.g. `ClibX11`, `ClibWayland`).
The core never imports these modules.

**D12 — Server-side window decorations**  
The window manager draws titlebars. X11 uses `_MOTIF_WM_HINTS`/EWMH; Wayland uses
`xdg-decoration` server-side. Client-side decorations (CSD) are deferred.

**D27 — MIT-SHM for X11 blit**  
X11 framebuffer presentation uses `XShm` (via `ClibXext`). This avoids a copy per
frame. `libXext` becomes a dependency of the `VulpinaX11` target in M5.

---

## View and layout

**D2 — Frame-based layout**  
Layout uses `frame`/`bounds` + autoresizing masks, mirroring AppKit's model. A
measure/arrange pass is deferred until the autoresizing approach proves insufficient.

**D13 — Immediate-mode drawing**  
Views implement `draw(_ context: VNGraphicsContext)` (like `NSView.draw(_:)`).
State is retained in views; drawing is immediate.

**D14 — `setNeedsDisplay` + coalesce**  
A dirty flag per view is coalesced and flushed in a `beforeWaiting` run-loop observer.
Subviews are composited in z-order (last child on top). Dirty rects are a future
optimisation.

**D29 — `NSAutoresizingMask`-style autoresizing**  
`flexibleWidth`, `flexibleHeight`, `flexibleMinX/MaxX` flags; `autoresizesSubviews`.

---

## Input

**D28 — Full mouse + keyboard input in M7**  
`VNEvent` covers mouse move/down/up/drag, scroll, and keyboard. Hit-testing and a
complete first-responder chain are included.

---

## Text

**D25 — Own Swift text stack**  
Text rendering uses Vulpina's own TTF/OTF parser (`cmap`/`glyf`/`hmtx`), basic
Latin shaping + kerning, and the analytic scan converter for glyph fill. HarfBuzz
is a future fallback for complex scripts (Arabic, Indic). No C libraries in the core.

**D26 — TextKit-like layout model**  
`VNTextStorage → VNLayoutManager → VNTextContainer` mirrors Apple's TextKit.
Lines flow and wrap naturally ("writing on paper"). Forms the foundation for
`VNLabel` and a future text editor.

---

## Colours

**D15 — sRGB `Double` 0…1**  
`VNColor` stores RGBA as `Double` in sRGB (straight alpha). Named/system colours are
a future addition. Sufficient for the own rasterizer; no ICC profile support in v1.

---

## Concurrency

**Swift 6 strict concurrency throughout.**
Value types (`VNPoint`, `VNRect`, `VNColor`, `VNPath`, `VNFramebuffer`, …) are
`Sendable`. Reference types that represent UI objects are `@MainActor`. No shared
mutable state is accessible from concurrent contexts.

---

## Source layout

```
Sources/
  Vulpina/              # Core library — the only public API target
    Environment/        # M1: VNEnvironment, VNDisplayServer, VNSessionType
    Geometry/           # M2: VNPoint, VNSize, VNRect, VNInsets, VNColor
    Rasterizer/         # M3a+M3b: VNFramebuffer, VNPath, VNGraphicsContext, …
    RunLoop/            # M4: VNRunLoop, VNRunLoopSource/Timer/Observer
    Application/        # M4: VNApplication, VNApplicationDelegate, VNBackend, VNSurface

Tests/
  VulpinaTests/         # Swift Testing suite
    EnvironmentTests.swift
    GeometryTests.swift
    RasterizerTests.swift
    M3bTests.swift
    MathTests.swift
    RunLoopTests.swift
```

Future targets (not yet created):

```
Sources/
  VulpinaX11/           # M5: X11 backend
  VulpinaWayland/       # M9: Wayland backend
  VulpinaDemo/          # M5+: interactive demo application
```
