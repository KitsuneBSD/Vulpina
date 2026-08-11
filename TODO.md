# Vulpina TODO

> **Somente bugs abertos e trabalho pendente.** Veja também:
> - `AGENTS.md` — regras de codificação e estilo
> - `README.md` — visão geral do projeto
> - `.ai-docs/` (futuro) — `CHANGELOG.md` / `ROADMAP.md` / `AUDITS.md` quando houver histórico suficiente

---

## Quick Status

| Area | Status | Key Gaps |
|------|--------|----------|
| **Infra (SwiftPM/Make)** | ✅ Working | `make build`/`release`/`clean`/`test` ✅; Swift 6.3 strict concurrency; 167 testes ✅ |
| **Ambiente** | ✅ M1 (2026-08-09) | `VNEnvironment` X11-first + `VULPINA_BACKEND` override; 31 testes ✅ |
| **Geometria** | ✅ M2 (2026-08-11) | `VNPoint`/`VNSize`/`VNRect`/`VNInsets`/`VNColor` — structs `Sendable`, 30 testes ✅ |
| **Rasterizador** | ✅ M3a+M3b (2026-08-11) | flatten adaptativo 0.1px, ellipse, roundedRect, stroke cap/join, Porter-Duff, even-odd | **Próprio em Swift**, vetorial universal, **AA analítico direto** (D17), scan→cobertura→blitter (D18; **spans por coluna pendente**), Porter-Duff completo (D23); M3a scan+analítico → M3b curvas |
| **Core backbone** | ✅ M4 (2026-08-11) | `VNRunLoop`/`VNApplication`/`VNBackend` + delegate lifecycle + polling backend; IMM-1 corrigido |
| **Backend X11** | ✅ M5 (2026-08-11) | `VulpinaX11` + `ClibX11` + `ClibXext`; janela, expose, MIT-SHM blit, polling 60Hz, `backingScaleFactor` via Xft.dpi, WM_DELETE_WINDOW |
| **Views** | ⚠️ M6 pendente | `VNView` frame/bounds, `isFlipped=false` (bottom-left), `draw(_:)`, display cycle |
| **Input** | ⚠️ M7 pendente | `VNEvent`/hitTest/responder chain; flip de coordenadas |
| **Texto** | ⚠️ M8 pendente | **Próprio em Swift** (D25), modelo TextKit-like "escrever em folha" (D26); glyphs pelo nosso scan converter; `VNLabel` |
| **Backend Wayland** | ⚠️ M9 pendente | `VulpinaWayland` + `ClibWayland` (wl_shm) |
| **Controles/layout** | ⚠️ M10 pendente | `VNButton`, autoresizing frame-based |
| **Docs** | ✅ Partial | `TODO.md` ✅; `.ai-docs/` criado (CHANGELOG/ROADMAP/ARCHITECTURE) |

---

## Decisões de Arquitetura (registradas 2026-08-10; D16–D32: 2026-08-11)

| # | Decisão | Escolha | Consequência |
|---|---------|---------|--------------|
| D1 | Renderer inicial | **Rasterizador próprio em Swift** (`VNRasterizer` → framebuffer RGBA); protocolo factory `VNRenderer` **adiado até existir 2º renderer** (evita abstração prematura) | zero dependências C no core; Skia/Vulkan entram depois via protocolo; texto adiado (D6) |
| D2 | Modelo de layout | **Frame-based** (AppKit): `frame`/`bounds` + autoresizing masks | simples e fiel ao Cocoa; measure/arrange reavaliado se precisar |
| D3 | Estrutura dos backends | **Targets no mesmo package**: `VulpinaX11`, `VulpinaWayland` | core sem imports de plataforma; demo em `VulpinaDemo` |
| D4 | Sistema de coordenadas | **Bottom-left estilo AppKit** (`isFlipped=false` default); y-flip aplicado pelo compositor ao apresentar | eventos e draw seguem AppKit; backend só apresenta top-left |
| D5 | Event loop | **`VNRunLoop` no core** (modes, sources, timers, observers); backend registra event source (ex. fd do display) | fiel ao Cocoa/CFRunLoop; mais trabalho que loop dirigido pelo backend |
| D6 | Stack de texto | **Decidida em D25** — própria em Swift, inspirada no TextKit da Apple | primeiros marcos sem texto (só formas/cores); texto entra em M8 |
| D7 | Interop C (assentado) | `.systemLibrary(pkgConfig:)` + `module.modulemap`, módulos prefixados `Clib*` (ClibX11, ClibWayland) | o core nunca importa esses módulos |
| D8 | Ambiente (assentado) | X11-first com override `VULPINA_BACKEND` | M1 ✅ |
| D9 | Unidade de geometria / HiDPI | **Points + backing scale** — `VNPoint` em points (`Double`); janela com `backingScaleFactor`; rasterizador renderiza em pixels = points × scale; X11 via Xft.dpi/RANDR, Wayland via `wl_output.scale` | HiDPI real (máquina roda `GDK_SCALE=2`); backend entrega tamanho em pixels |
| D10 | Concorrência | **`@MainActor` nos tipos UI** (`VNView`/`VNWindow`/`VNApplication`/`VNRunLoop`); backend entrega eventos na main thread e usa `MainActor.assumeIsolated` no entry point | main-thread-only estilo AppKit + seguro sob strict concurrency |
| D11 | Ciclo de vida da aplicação | **Instância explícita + delegate** — `main` cria `VNApplication(backend:)`, seta `VNApplicationDelegate` (`applicationDidFinishLaunching`/`WillTerminate`), chama `run()`; sem global | alinhado ao "no global mutable state" do AGENTS.md |
| D12 | Decorações de janela | **Server-side primeiro** — WM desenha a titlebar (X11 `_MOTIF_WM_HINTS`/EWMH; Wayland `xdg-decoration` server-side) | zero código de titlebar; CSD depois se necessário |
| D13 | API de desenho | **Immediate mode com `VNGraphicsContext`** — `draw(_ context:)` estilo `NSView.draw(_:)`; context = rasterizador + clip + transform (y-flip) | estado *retained* nas views, desenho *immediate* |
| D14 | Pipeline de redraw | **`setNeedsDisplay` + coalesce + display pass em z-order** — dirty flag por view; display via observer do `VNRunLoop` (beforeWaiting); subviews na ordem do array (último no topo); clip por view | dirty rects finos otimizam depois |
| D15 | Sistema de cores | **sRGB + componentes `Double` 0…1** — `VNColor` struct value RGBA; named/system colors depois | simples e suficiente para rasterizador próprio |
| D16 | Pipeline de desenho | **Vetorial universal** — todo desenho vira `VNPath` → arestas → spans → pixels; rect alinhado tem fast path por cópia de linha; sem caso bitmap no v1 | uma única entrada de geometria (path); primitivas são paths + fast paths |
| D17 | Anti-aliasing | **Analítico por área exata desde o início** (modelo Skia AAA / FreeType smooth / stb_truetype): sweep line, y críticos, AET, trapézios, cobertura exata; **sem fase aliased binária** | AA de primeira; M3a já entrega cobertura 0–255; supersampling não é ponte |
| D18 | Arquitetura do rasterizador | **Scan converter → spans de cobertura → blitter** (modelo Skia `SkScan`/`SkBlitter` + FreeType `smooth`); seam interno, conversores trocáveis | geometria separada da composição; converters testáveis isoladamente |
| D19 | Cobertura × alpha | Cobertura 0–255 **separada** do alpha de cor; composição `cov·Blend(src,dst) + (1−cov)·dst` | evita artefatos de conflation em primitivas vizinhas/sobrepostas |
| D20 | Precisão numérica | **`Double`** na geometria/scan; conversão para inteiro na fronteira do pixel | fixed-point (cairo 24.8 / pixman 16.16) só gated por benchmark (LOW) |
| D21 | Primitivas v1 | **rect, rounded rect, ellipse/círculo, linha, path arbitrário — fill + stroke**; gradientes/sombras fora (pós-M3b) | conjunto completo suficiente para o demo e M6 |
| D22 | Regras de preenchimento | **Non-zero + even-odd** via `windingRule` do `VNPath` (como `NSBezierPath.windingRule`) | fiel ao Cocoa; testes com path auto-intersectante |
| D23 | Blend modes | **Porter-Duff completo** via `VNBlendMode` — 12 operadores (source-over, copy, source-in/out/atop, destination-*, xor, plus-lighter/darker, clear) | composição completa desde o v1 |
| D24 | Pixel format | Framebuffer **premultiplied RGBA8** interno; straight (não-premultiplied) só na conversão para o blit X11 | blend source-over exato em uma passada; modelo Skia/cairo/pixman |
| D25 | Texto — stack | **Próprio em Swift** — parser TTF/OTF (cmap/glyf/hmtx) + shaping básico (Latin + kerning) + glyphs preenchidos pelo **nosso** scan converter analítico (M3b); harfbuzz como ponte futura se scripts complexos (árabe/índico) exigirem | preserva D1/D7 (zero C no core); sem hinting/subpixel no v1 (aceitável em HiDPI, D9) |
| D26 | Texto — modelo | **Escrita em folha** (TextKit da Apple): `VNTextStorage` → `VNLayoutManager` → `VNTextContainer`; linhas fluem e embrulham naturalmente, como escrever em papel | layout de texto documental (não caixa única); base para `VNLabel` e futuro editor |
| D27 | Blit X11 | **MIT-SHM desde já** — `XShm` via `ClibXext` + `ClibX11` | zero cópia extra no blit; `libXext` vira dependência do M5 |
| D28 | Input v1 | **Mouse (move/down/up/drag) + scroll + teclado + focus/first responder completo** | M7 entrega responder chain completa; base para `VNButton` e editor |
| D29 | Autoresizing | **Espelhar `NSAutoresizingMask`** — flexibleWidth/Height/MinX/MaxX + `autoresizesSubviews` | frame-based fiel ao Cocoa (D2) |
| D30 | Demo | **Interativo mínimo** — mouse move desenha um retângulo; valida input+redraw+blit de uma vez | demo desde M5 exercita a pilha inteira |
| D31 | Gradientes/sombras | **M11 logo após a fundação** (não sob demanda) — gradientes lineares/radiais + sombras | entra como marco dedicado, não item LOW |
| D32 | Histórico | **`.ai-docs/` criado agora** — CHANGELOG.md desde o M2; ROADMAP/AUDITS quando houver histórico | histórico começa no M2 |

> Convensões consolidadas: prefixo `VN`, núcleo backend-agnóstico, value semantics (structs) para geometria/estado, classes só onde identidade importa, Swift 6.3 strict concurrency, UI isolada em `@MainActor`.

---

## ⏳ Decisões Pendentes

| # | Decisão | Contexto |
|---|---------|----------|
| P1 | **D5 — source por fd** | ✅ **Decidida (2026-08-11)**: aceitar polling 60Hz via observer `beforeWaiting` como v1. fd-source (`select`/`poll` em `XConnectionNumber`) entra se latência de input > 16ms for observada em benchmark real. |
| P2 | **D27 × `VNSurface`** | ✅ **Decidida (2026-08-11)**: aceitar cópia única `VNFramebuffer` → SHM buffer no `present(_:)`. MIT-SHM é interno ao `VNX11Surface` (zero cópia no caminho X11); a cópia do seam (Swift struct by-value) é a única overhead real. Revisar se profiling M5 mostrar bottleneck. |
| P3 | **Timing do `VNRenderer`** | GPU (Skia/Vulkan) hoje em LOW "pós-M10". Se GPU for intenção real, o protocolo entra **antes** de M5/M6 travarem a API de apresentação; o front do pipeline (paths/flatten/stroke/transform) porta bem, mas scan converter + blitter seriam substituídos por tesselação + shader. |
| P4 | **D13/D14 — snapshot recording (modelo `GtkSnapshot` do GTK4)** | A API `draw(_ context:)` fica idêntica, mas o alvo do desenho muda: `VNGraphicsContext` grava numa **render tree por view** (recorder), reexecutada no display pass — em vez de escrever direto no framebuffer. Habilita cache por subárvore (RepaintBoundary-style do Flutter). Refinamento, não reversão; muda a implementação do contexto (D13) e o display pass (D14). **Decidir antes do M6** (janela apertada). |
| P5 | **D16 — caso bitmap (imagens PNG)** | D16 diz "sem caso bitmap no v1" — imagem É caso bitmap. Suportar PNG/JPEG exige **emenda D33** (caso bitmap para blit de textura) + decoder (stb_image via `ClibSTB` no padrão D7, ou PNG puro em Swift — cultura zero-C). Sem emenda, imagens ficam fora do roadmap. |
| P6 | **D25 — descoberta de fontes** | D25 decide o parser próprio (zero C no core) mas **não decide de onde vêm os arquivos**. fontconfig via `ClibFontconfig` (fora do core, preserva D7) vs scanner Swift de diretórios (perde cobertura `/usr/share/fonts` + paths de distro). Decidir antes do M8. |

---

## 🔴 IMMEDIATE — Correção de Bugs

> **Estado atual: `make test` completa** — 167 testes ✅. Todos os IMMs resolvidos (2026-08-11).

| # | Bug | Estado |
|---|-----|--------|
| IMM-1 | **`swift test` pendura** — `applicationDidFinishLaunching` agendado como `VNRunLoopSource` (dispara na primeira iteração); `terminate()` inside delegate agora seta `_isStopped` antes da próxima checagem do `while` | ✅ corrigido |
| IMM-2 | **`VNPath.flattened()`** — `subpathStart` rastreado; `.close` reseta `current = subpathStart` | ✅ corrigido |
| IMM-3 | **Cobertura com arestas coincidentes** — comportamento verificado e coberto por 3 testes: nonZero clamp ≤1, opostos cancelam, even-odd dobra back | ✅ verificado |

---

## 🟠 HIGH — Marcos de Fundação (M1–M7)

| M | Marco | Status | Detalhes |
|---|-------|--------|----------|
| M1 | Detecção de ambiente | ✅ (2026-08-09) | `VNEnvironment` + `VNDisplayServer`/`VNSessionType`; 31 testes ✅ |
| M2 | Geometria | ✅ (2026-08-11) | `VNPoint`/`VNSize`/`VNRect`/`VNInsets`/`VNColor` (structs `Sendable`); unidades em points + escala (D9); sRGB `Double` 0…1 (D15); 30 testes ✅ |
| M3a | Rasterizador — seam + analítico (arestas retas) | ✅ (2026-08-11) | `VNFramebuffer` (RGBA8, stride, **premultiplied** D24, pixels = points × scale); `VNAnalyticScanConverter` (sweep line, y críticos, AET, trapézios, cobertura exata D17) → buffer denso de cobertura → `VNPorterDuffBlitter` (**spans por coluna pendentes**, D18); `VNPath` (move/line/close, `windingRule` D22), `VNAffineTransform`, `VNColor`, `VNBlendMode` (Porter-Duff D23); `VNGraphicsContext` (save/restore, translate/scale/rotate, fill/stroke, blend; **clip pendente** D13); `VNRasterizer`; testes por pixel |
| M3b | Rasterizador — curvas + primitivas completas | ✅ (2026-08-11) | `VNPath` ganha `addCurve`/`addQuadCurve`/`addArc` com **flatten adaptativo 0.1px** (padrão gg/Go + Skia); rounded rect, ellipse/círculo (D21), stroke com cap/join; cobertura×alpha (D19); testes: área de círculo ≈ πr², erro de flatten < 0.1px, roundRect, stroke |
| M4 | Core backbone | ✅ (2026-08-11) | `VNRunLoop` (modes, sources, timers, observers) + `VNApplication(backend:)` + `VNApplicationDelegate` (D11) + protocolo `VNBackend`/`VNSurface(present:)`; IMM-1 corrigido; polling via `beforeWaiting` (P1 v1); 167 testes ✅ |
| M5 | Backend X11 | ✅ (2026-08-11) | `VulpinaX11` + `ClibX11` + `ClibXext` (`systemLibrary(pkgConfig:)`); `VNX11Backend` + `VNX11Surface`; janela, expose, blit via MIT-SHM (XPutImage fallback, D27); polling 60Hz (P1); `backingScaleFactor` via Xft.dpi (D9); WM_DELETE_WINDOW (D12); P2 v1: aceitar cópia única, MIT-SHM interno ao backend |
| M6 | VNView | ❌ | `frame`/`bounds`, `isFlipped=false`, `draw(_ context:)` (D13), `setNeedsDisplay` + coalesce + z-order (D14), display cycle, y-flip no compositor; **clip no `VNGraphicsContext` pendente desde M3a (D13)** |
| M7 | Input | ❌ | `VNEvent` (NSEvent-like), hitTest, responder chain completa + focus/first responder (D28), conversão de coordenadas (flip) |

---

## 🟡 MEDIUM — Views Avançadas (M8–M11)

| M | Marco | Status | Detalhes |
|---|-------|--------|----------|
| M8 | Texto | ❌ | **Próprio em Swift** (D25): parser TTF/OTF (cmap/glyf/hmtx), shaping básico Latin + kerning, glyphs via nosso converter analítico; modelo **TextKit-like** `VNTextStorage`→`VNLayoutManager`→`VNTextContainer` (D26); depois `VNLabel` |
| M9 | Backend Wayland | ❌ | `VulpinaWayland` + `ClibWayland`; wl_shm buffer + attach/commit; event source |
| M10 | Controles/layout | ❌ | `VNButton`, autoresizing `NSAutoresizingMask`-style (D29), gerenciamento do frame de `VNWindow` |
| M11 | Gradientes/sombras | ❌ | gradientes lineares/radiais + sombras (drop shadow) — logo após a fundação (D31) |

---

## 🔴 Code Quality Debt

| Item | Status |
|------|--------|
| **Commit do M2–M5** | ❌ todo o trabalho (Geometry/Rasterizer/RunLoop/Application/VulpinaX11, `.ai-docs/`, testes) está sem commit (repo tem só 3 commits); commitar agora |
| `.ai-docs/` | ✅ CHANGELOG/ROADMAP/ARCHITECTURE criados (D32); AUDITS quando houver histórico |
| Doc comments em 100% do public API (AGENTS.md) | ⚠️ obrigatório; auditar ao fechar cada marco |

---

## 🟢 LOW — Polimento e Longo Prazo

| Item | Notas |
|------|-------|
| Renderer GPU (Skia/Vulkan) | via protocolo `VNRenderer`, pós-M10 |
| Fixed-point (24.8/16.16) | otimização do scan converter, **gated por benchmark** (D20) |
| Rasterizador — alocações | buffer de cobertura `[Float]` W×H alocado por draw op; `VNFramebuffer.clear()` realoca o array; reuso de buffers quando M6 trouxer muitas views |
| `VulpinaDemo` completo | demo **interativo** desde M5: mouse move desenha retângulo (D30); evoluir para kit completo |
| Benchmark do rasterizador | throughput de preenchimento/alpha em largura real |
| Suporte de temas/cores | futuro |

---

## Build Verification

| After change | Commands |
|--------------|----------|
| Core changes | `make build` + `make test` |
| Novo target backend | `make build` |
| Full check | `make test` |

## References

- `AGENTS.md` — regras de codificação e estilo
- `README.md` — visão geral do projeto
- Rasterizer specs: Skia CPU backend + Analytic AA (`SkScan_AAAPath`), FreeType `smooth` (FT_Raster), stb_truetype signed-area, cairo fixed-point (24.8)
- Texto (Apple/TextKit): `NSTextStorage`/`NSLayoutManager`/`NSTextContainer` — modelo de escrita em folha (D26); parser TTF/OTF próprio (cmap/glyf/hmtx)
- `.ai-docs/` — CHANGELOG/ROADMAP/ARCHITECTURE criados (D32, desde o M2)
