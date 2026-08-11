# Roadmap

Milestones are listed in priority order. Each milestone ships only when
`make test` passes with full coverage for the new public API.

---

## Foundation (M1–M4) ✅

| Milestone | Status | Summary |
|-----------|--------|---------|
| M1 — Environment | ✅ 2026-08-09 | `VNEnvironment`, display server + session detection |
| M2 — Geometry | ✅ 2026-08-11 | `VNPoint/Size/Rect/Insets/Color`, 30 tests |
| M3a — Rasterizer (straight edges) | ✅ 2026-08-11 | Analytic AA, Porter-Duff, `VNGraphicsContext` |
| M3b — Rasterizer (curves) | ✅ 2026-08-11 | Bézier flatten, stroke cap/join, ellipse, even-odd |
| M4 — Core backbone | ✅ 2026-08-11 | `VNRunLoop`, `VNApplication`, `VNBackend`/`VNSurface` |

---

## 🟠 HIGH — Display and Input (M5–M7)

### M5 — X11 backend

- New target: `VulpinaX11`.
- C interop: `ClibX11` + `ClibXext` via `systemLibrary(pkgConfig:)` + `module.modulemap`.
- Open a window (`XCreateWindow`, `_MOTIF_WM_HINTS` for server-side decorations).
- Blit framebuffer using MIT-SHM (`XShm`): `XShmCreateImage` → `XShmPutImage`.
- Register display connection fd as a `VNRunLoopSource`.
- Read `Xft.dpi` / RANDR to determine `backingScaleFactor`.
- Minimal interactive demo: coloured rectangle drawn on `Expose`.

### M6 — VNView

- `VNView` class (`@MainActor`): `frame`, `bounds`, `isFlipped = false`.
- `draw(_ context: VNGraphicsContext)` — override point for subclasses.
- `setNeedsDisplay()` dirty flag coalesced into a `beforeWaiting` run-loop observer.
- Subview array; composite in z-order (last child on top).
- `VNWindow`: owns a `VNSurface` and a root `VNView`. Drives the display cycle.
- y-flip applied when converting view coordinates to framebuffer pixel space.

### M7 — Input

- `VNEvent`: mouse (move, down, up, drag), scroll, keyboard (key down/up, modifiers).
- `hitTest(_:)`: walk subview tree to find the deepest view under a point.
- Responder chain: `VNView → VNWindow → VNApplication`.
- First-responder management: `makeFirstResponder(_:)`, `resignFirstResponder()`.
- Coordinate conversion: view-local ↔ window ↔ screen, accounting for y-flip.

---

## 🟡 MEDIUM — Views and Text (M8–M11)

### M8 — Text

- TTF/OTF parser: `cmap` (Unicode BMP), `glyf` (TrueType outlines), `hmtx` (advance widths).
- Basic Latin shaping + pair kerning.
- Glyph outlines converted to `VNPath` and filled by the analytic scan converter.
- Layout model: `VNTextStorage → VNLayoutManager → VNTextContainer`.
  Lines flow and wrap (TextKit "writing on paper" model).
- `VNLabel`: single-line read-only label view.
- No hinting or sub-pixel rendering in v1 (acceptable at HiDPI backing scales).

### M9 — Wayland backend

- New target: `VulpinaWayland`.
- C interop: `ClibWayland` wrapping `wayland-client`.
- `wl_shm` shared-memory buffer; `wl_surface.attach` + `commit` for presentation.
- `xdg_shell` surface for a top-level window with server-side decorations.
- Register Wayland display fd as a `VNRunLoopSource`.
- `wl_output.scale` for `backingScaleFactor`.

### M10 — Controls and layout

- `VNButton`: push-button control with action target, normal/highlighted/disabled states.
- Autoresizing masks (`flexibleWidth`, `flexibleHeight`, `flexibleMinX/MaxX`, …)
  mirroring `NSAutoresizingMask`.
- `VNWindow` resizing: propagate new size through the view hierarchy.

### M11 — Gradients and shadows

- Linear and radial gradients via `VNGradient` + `VNGraphicsContext.fill(_:gradient:)`.
- Drop shadows: pre-render a blurred alpha mask offset by `(dx, dy)` and composite
  under the shape.
- Gaussian blur for shadow: separable 1D kernel applied in two passes over the
  framebuffer.

---

## 🟢 LOW — Polish and long-term

| Item | Notes |
|------|-------|
| GPU renderer | Via `VNRenderer` protocol, post-M10. Likely Vulkan + SPIR-V shaders. |
| Fixed-point scan converter | 24.8 / 16.16 arithmetic. Only if benchmarks show `Double` is a bottleneck (D20). |
| `VulpinaDemo` evolution | Interactive from M5 (mouse-draw rectangle). Grow into a full widget showcase. |
| Rasterizer benchmarks | Fill + alpha throughput at real-world widths. |
| Complex script shaping | Arabic, Indic via HarfBuzz (C interop, gated behind `VulpinaHarfBuzz` target). |
| System colour palette | Platform accent colours, dark-mode detection. |
| Accessibility | `VNAccessibility` protocol for view hierarchy export. |
