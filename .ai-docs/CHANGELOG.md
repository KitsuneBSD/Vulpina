# Changelog

All notable changes to Vulpina are recorded here per milestone.
Format: `[Mx] — YYYY-MM-DD · Title`.

---

## [M4] — 2026-08-11 · Core backbone

**New types**

- `VNRunLoop` — AppKit-style main-thread run loop (`run()`, `stop()`, `runOnce()`).
  Supports named modes (`VNRunLoopMode`: `.default`, `.tracking`, `.common`).
- `VNRunLoopSource` — manual signal source; fires its handler once per iteration
  while pending.
- `VNRunLoopTimer` — interval-based timer with `repeats` flag and `invalidate()`.
  Advances `nextFireDate` by `interval` on each firing (skips missed firings).
- `VNRunLoopObserver` — subscribes to `VNRunLoopActivity` flags
  (`.beforeSources`, `.beforeWaiting`, `.afterWaiting`, `.exit`).
- `VNBackend` — protocol for display-server backends: `makeSurface(widthPixels:heightPixels:title:)`,
  `backingScaleFactor`, `registerEventSource(with:)`, `pollEvents()`.
- `VNSurface` — protocol for a drawable surface; single method `present(_:)`.
- `VNApplication` — owns `VNRunLoop.main` and a `VNBackend`; calls
  `applicationDidFinishLaunching` / `applicationWillTerminate` on its delegate.
- `VNApplicationDelegate` — lifecycle protocol with default no-op implementations.

**Tests:** 28 new tests in `RunLoopTests.swift`.

---

## [Math] — 2026-08-11 · Mathematical invariance tests

Dedicated test suite (`MathTests.swift`) verifying quantitative properties of the
rasterizer rather than "pixel > 0" assertions:

- `areaToLeft` formula: 10 tests against exact analytical integrals.
- Area conservation: pixel-aligned and half-pixel rects, ellipse ≈ πr², HiDPI @2×.
- AA edge coverage: half-pixel boundary splits, diagonal monotone coverage,
  vertical edge 50/50 split.
- Winding rule math: non-zero clamping, even-odd cancellation, triple nesting.
- Porter-Duff identities: 7 tests for alpha formula correctness.
- Transform mathematics: scale, translate, rotation area conservation.
- Stroke area: proportional to length × width.
- Affine algebra: associativity, identity neutral element, inverses.

Also exposed `VNAnalyticScanConverter._areaToLeft` as `internal` for direct testing.

---

## [M3b] — 2026-08-11 · Rasterizer — curves and complete primitives

**New types / extensions**

- `VNBezierFlattener` — adaptive de Casteljau cubic/quadratic flattening (tolerance
  0.1 pt); arc-to-cubic via `k = (4/3)*tan(span/4)`, max π/2 per segment.
- `VNStroker` — converts stroked paths to filled outlines: left/right offset arrays,
  miter/round/bevel joins, butt/round/square caps. Closed paths use opposite windings
  to create a non-zero hole in the centre.
- `VNStrokeStyle` — `VNLineCap` (butt, round, square) and `VNLineJoin` (miter, round, bevel).
- `VNPath` extended: `addCurve(to:control1:control2:)`, `addQuadCurve(to:control:)`,
  `addArc(center:radius:startAngle:endAngle:clockwise:)`, `flattened(tolerance:)`,
  `appendPath(_:)`, `ellipse(in:)`, `roundedRect(_:cornerRadius:)`.
- `VNGraphicsContext.stroke(…lineCap:lineJoin:miterLimit:…)`.

**Tests:** 16 tests in `M3bTests.swift` (flatten error, ellipse area ≈ πr²,
round/square caps, even-odd donut, closed stroke ring).

**Key fixes during development**

- `joinPoint` used `abs(dot)` to correctly handle outer-corner miter (side = -1
  produces negative raw dot).
- Square cap start/end winding: end emits left then right; start emits right then left.
- Closed stroke test pixel corrected to `(10, 32)` (inside the [outer=9, inner=11) ring).

---

## [M3a] — 2026-08-11 · Rasterizer — analytic AA + straight edges

**New types**

- `VNFramebuffer` — premultiplied RGBA8 pixel buffer (`widthPixels × heightPixels`),
  y-down storage, `pixel(x:y:)` / `setPixel(x:y:r:g:b:a:)` / `clear()`.
- `VNAnalyticScanConverter` — sweep-line scan converter computing exact signed area
  per pixel via the `areaToLeft` trapezoid integral. Supports non-zero and even-odd
  winding rules.
- `VNPorterDuffBlitter` — 12 Porter-Duff operators on premultiplied floats.
  Coverage [0, 1] is separate from color alpha (D19).
- `VNBlendMode` — enum: sourceOver, copy, clear, sourceIn/Out/Atop,
  destinationOver/In/Out/Atop, xor, plusLighter.
- `VNRasterizer` — `fill(path:transform:color:blendMode:backingScale:into:)` and
  `stroke(…)`. Converts path to `_VNEdge` array in pixel space (y-down) then
  calls the scan converter.
- `VNAffineTransform` — row-vector 2D affine (`x' = x·a + y·c + tx`); `identity`,
  `translation`, `scale`, `rotation`, `concatenating`, `applying(to:)`.
- `VNPath` (initial) — `move(to:)`, `line(to:)`, `close()`, `windingRule`,
  `rect(_:)` convenience constructor.
- `VNGraphicsContext` — immediate-mode context: save/restore state stack,
  `translateCTM`, `scaleCTM`, `rotateCTM`, `fill(_:color:blendMode:)`.

**Coordinate system:** points in y-up (bottom-left), pixels in y-down (top-left).
Conversion: `py = (pointHeight − y_point) × backingScale`.

**Tests:** 16 tests in `RasterizerTests.swift`.

**Key fixes during development**

- `ceil` not in scope → added `import Foundation` to `VNAnalyticScanConverter.swift`.
- Crash on `colStart...colEnd` when `colStart > colEnd` → guarded with `if colStart <= colEnd`.

---

## [M2] — 2026-08-11 · Geometry

- `VNPoint(x:y:)` — `Double` coordinates in point space (y-up). `Sendable, Hashable, Codable`.
- `VNSize(width:height:)` — `isEmpty`, arithmetic helpers.
- `VNRect(origin:size:)` — `minX/Y`, `maxX/Y`, `midX/Y`, `center`, `standardized`,
  `contains(_:)` (point and rect), `intersects`, `intersection`, `union`,
  `insetBy(dx:dy:)`, `offsetBy(dx:dy:)`.
- `VNInsets(top:left:bottom:right:)` — uniform `init(_ value:)`.
- `VNColor(red:green:blue:alpha:)` — sRGB `Double` 0…1, straight alpha. Ten named
  colors. `withAlpha(_:)`, `premultiplied`.

**Tests:** 30 tests in `GeometryTests.swift`.

---

## [M1] — 2026-08-09 · Environment detection

- `VNEnvironment` — detects display server and session type at startup.
- `VNDisplayServer` — `.x11`, `.wayland`, `.none`. X11-first with
  `VULPINA_BACKEND` env-var override.
- `VNSessionType` — `.graphical`, `.tty`, `.unknown`.

**Tests:** 31 tests in `EnvironmentTests.swift`.
