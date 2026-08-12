# Vulpina TODO

> **Somente bugs abertos e trabalho pendente.** Veja também:
> - `AGENTS.md` — regras de codificação e estilo
> - `README.md` — visão geral do projeto
> - `.ai-docs/` (futuro) — `CHANGELOG.md` / `ROADMAP.md` / `AUDITS.md` quando houver histórico suficiente

---

## Quick Status

| Area | Status | Key Gaps |
|------|--------|----------|
| **Infra (SwiftPM/Make)** | ✅ Working | `make build`/`release`/`clean`/`test` ✅; Swift 6.3 strict concurrency; **241 testes / 41 suites** ✅ |
| **Ambiente** | ✅ M1 (2026-08-09) | `VNEnvironment` X11-first + `VULPINA_BACKEND` override; 31 testes ✅ |
| **Geometria** | ✅ M2 (2026-08-11) | `VNPoint`/`VNSize`/`VNRect`/`VNInsets`/`VNColor` — structs `Sendable`, 30 testes ✅ | **Math/GeometryForms (D33) pendente** — `VNShape` + área exata (Green) + `length(at t:)`; `VNPath` migra de `Rasterizer/` |
| **Rasterizador** | ✅ M3a+M3b+M3c (2026-08-12) | flatten adaptativo 0.1px, ellipse, roundedRect, stroke cap/join, Porter-Duff, even-odd | **Próprio em Swift**, vetorial universal, **AA analítico direto** (D17), scan→cobertura→blitter (D18; **spans por coluna pendente**); Porter-Duff **matriz W3C ✅ 12/12 operadores** (IMM-5 corrigido); **M3c = grupos isolados ✅** + composição glass adiada p/ M12 |
| **Core backbone** | ✅ M4 (2026-08-11) | `VNRunLoop`/`VNApplication`/`VNBackend` + delegate lifecycle + polling backend; IMM-1 corrigido |
| **Backend X11** | ✅ M5 (2026-08-11) | `VulpinaX11` + `ClibX11` + `ClibXext`; janela, expose, MIT-SHM blit, polling 60Hz, `backingScaleFactor` via Xft.dpi, WM_DELETE_WINDOW |
| **Views** | ✅ M6 (2026-08-12) | `VNView` frame/bounds, `isFlipped=false`, `draw(_:)`, display cycle, clip, y-flip |
| **Input** | ✅ M7 (2026-08-12) | `VNEvent`/`VNResponder`/hitTest/responder chain/`firstResponder`/`sendEvent`; flip de coordenadas; X11 mouse+teclado+scroll |
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
| D33 | Math/GeometryForms | **Camada de geometria no core** (pasta, não target separado — D1: sem abstração prematura até existir 2º consumidor, padrão `VNRenderer`): protocolo `VNShape` (`area`/`perimeter`) + `VNCircle`/`VNEllipse`/`VNRect`; **`VNPath` migra de `Rasterizer/` para a camada de geometria**; **área exata via teorema de Green sobre base de Bézier** (forma fechada → πr² exato); **`perimeter`/`length(at t:)` numérico com erro certificado** (comprimento de arco de Bézier não tem forma fechada; elipse = integral elíptica) | testes abandonam shoelace ad hoc; golden-model do P3 ganha referência exata; base para dashing (futuro), animação ao longo de path, métricas de stroke; consumidor inicial: os próprios testes |

| D35 | Interop Vulkan — Swift ↔ ObjC | **Swift NÃO importa ObjC fora da Apple** (interop desabilitado no compilador; thread de viabilidade GNUstep mar–abr 2026 sem implementação; SE-0403 mixed-language targets "Returned for Revision"). **Rota ObjC descartada** ("dar de João sem braço" quebra na fronteira do Swift). Estrutura: `ClibVulkan` (`systemLibrary` D7) + `VulpinaVulkan` (target Clang, C++/C internos, **API `extern "C"` com handles opacos**) + Swift importa a C API (mesmo padrão do `ClibX11`); o "linkar direto ao Vulkan" acontece dentro do target Clang | core continua puro Swift (D3); a fronteira C torna a língua interna substituível (C++/Rust/ObjC++ sem o Swift perceber) |
| D36 | Língua do wrapper Vulkan | **C++ como default** — `vulkan.hpp` com `vk::raii::` (destruição automática, elimina a classe de leaks em paths de erro), volk (loader), STL; arquitetura padrão da indústria (Skia, wgpu = API C + internals C++); ~30–50% menos código que C. **C puro só se o FoxynOS não tiver runtime C++** (libstdc++/libc++) — C é a língua que sempre está lá; contras: sem RAII, `VkResult` manual, swapchain recreation vira campo minado de memória | runtime C++ vira dependência do target backend (trivial em Linux/*BSD); decisão pendente do toolchain do FoxynOS (P9) |

> Convensões consolidadas: prefixo `VN`, núcleo backend-agnóstico, value semantics (structs) para geometria/estado, classes só onde identidade importa, Swift 6.3 strict concurrency, UI isolada em `@MainActor`.

---

## ⏳ Decisões Pendentes

| # | Decisão | Contexto |
|---|---------|----------|
| P1 | **D5 — source por fd** | ✅ **Decidida (2026-08-11)**: aceitar polling 60Hz via observer `beforeWaiting` como v1. fd-source (`select`/`poll` em `XConnectionNumber`) entra se latência de input > 16ms for observada em benchmark real. |
| P2 | **D27 × `VNSurface`** | ✅ **Decidida (2026-08-11)**: aceitar cópia única `VNFramebuffer` → SHM buffer no `present(_:)`. MIT-SHM é interno ao `VNX11Surface` (zero cópia no caminho X11); a cópia do seam (Swift struct by-value) é a única overhead real. Revisar se profiling M5 mostrar bottleneck. |
| P3 | **Renderer GPU — rota revisada (2026-08-12): CPU analítico + GPU Vulkan (tesselação → compute-coverage)** | **Antiga direção (2026-08-11)**: "uma matemática, dois substratos" — GPU via cobertura (Vello), tesselação fora (quebraria W3C 12/12 e πr²). **Revisada após análise**: GPU = **fase 1 tesselação+MSAA** (estrada batida, shippable) + **fase 2 compute-coverage estilo Vello** (endgame) na **mesma API Vulkan** — Vello ainda alpha em 2026 (README: "alpha state", blur/filters em andamento), então a cobertura não é produção nem na referência; e **a expressividade do Vulkan (compute, atomics, subgroups) só se paga no endgame** — argumento pró-cobertura, não contra. **Seam no layer/framebuffer**: GPU renderiza layers em RGBA8 premultiplied (D24), **compositor Porter-Duff compartilhado compõe** → matriz W3C sobrevive *entre* layers (blending mora no compositor, não no rasterizer); dentro do layer o MSAA assume (cobertura binária por sample — conflation documentado: NV_path_rendering mostra Cairo/Qt/Skia/Direct2D com "dark cracks"). **Invariantes**: πr² e W3C com coverage=alpha **morrem no caminho GPU** → golden images por renderer, CPU continua o reference. **Environment**: capability probing real — `VkPhysicalDeviceType.CPU` (Lavapipe) → analítico; sample counts queryados via `framebufferColorSampleCounts`; fallback obrigatório (GPU pode falhar em runtime) → **ambos os renderers existem sempre**, o env escolhe o default. **Confirmação industrial**: Skia Graphite (Chrome future, 2025) = MSAA onde pode + fallback CPU atlas. **Texto (D25)**: glyphs analíticos → textura no caminho GPU (CPU rasteriza, upload) — analítico continua vivo no GPU. **Timing**: milestone próprio **pós-M6/M7**. Em aberto: apresentação (swapchain `VK_KHR_xcb_surface` vs SHM — X11 ganha segundo caminho de present; readback serializa GPU→CPU) e estado do toolchain do FoxynOS (P9). |
| P4 | **D13/D14 — snapshot recording (modelo `GtkSnapshot` do GTK4)** | A API `draw(_ context:)` fica idêntica, mas o alvo do desenho muda: `VNGraphicsContext` grava numa **render tree por view** (recorder), reexecutada no display pass — em vez de escrever direto no framebuffer. Habilita cache por subárvore (RepaintBoundary-style do Flutter). Refinamento, não reversão; muda a implementação do contexto (D13) e o display pass (D14). **Decidir antes do M6** (janela apertada). |
| P5 | **D16 — caso bitmap (imagens PNG)** | D16 diz "sem caso bitmap no v1" — imagem É caso bitmap. Suportar PNG/JPEG exige **emenda D34** (caso bitmap para blit de textura) + decoder (stb_image via `ClibSTB` no padrão D7, ou PNG puro em Swift — cultura zero-C). Sem emenda, imagens ficam fora do roadmap. |
| P6 | **D25 — descoberta de fontes** | D25 decide o parser próprio (zero C no core) mas **não decide de onde vêm os arquivos**. fontconfig via `ClibFontconfig` (fora do core, preserva D7) vs scanner Swift de diretórios (perde cobertura `/usr/share/fonts` + paths de distro). Decidir antes do M8. |
| P7 | **Glass — modelo de material (liquid-glass Apple / frosted-glass pop!OS)** | Efeito = captura de backdrop (offscreen) + blur Gaussiano + tint semi-transparente + composição sobre o conteúdo. Modelo W3C: **grupos isolados** (Compositing-1 §9.2) + `backdrop-filter` (CSS Filter Effects L2). Decidir: API `VNVisualEffectView`-style vs. função pura; escopo (janela inteira vs. sub-região com cantos arredondados — depende do clip, D13). **Base de composição em M3c**; blur Gaussiano reutiliza M11. **Decidir antes de M11/M12.** |
| P8 | **Wide color — Display P3 (simulação em software sobre telas sRGB; não confundir com a decisão P3 do renderer GPU)** | Pesquisa 2026-08-11 (References): a vividez do macOS é **painel Display P3** (primárias DCI-P3 + D65 + gamma sRGB) **+ ColorSync** (pipeline color-managed no sistema inteiro) — sem a pipeline, wide gamut é bug (GLFW issue #2748: tela P3 + app sem `setColorSpace` = escuro/oversaturado). Linux não tem o análogo maduro: Wayland `color-management-v1` mergeado upstream fev/2025 (5 anos de review, staging), wlroots mar/2025, Chromium jul/2025, driver NVIDIA pendente. Decidir: **simular P3 em software sobre telas comuns** — manter D15 como espaço de trabalho default e compor em P3 quando o conteúdo for wide (Double já resolve, D20), então **gamut-map perceptual na apresentação** (compressão de saturação preservando matiz + neutros neutros; **não** clipping — achata a vividez). Ganho em tela sRGB é limitado por definição (simulação, não gamut físico — o ColorSync analog é o `color-management-v1`), mas prepara a pilha para telas wide-gamut/HDR; variantes light/dark da paleta seguem o modelo da HIG. Timing: implementar como recurso opcional **antes do M6** (API de cor ainda não travada) vs. adiar até o primeiro backend expor wide gamut. |
| P9 | **Toolchain do FoxynOS — runtime C++** | Estado do toolchain do FoxynOS decide a língua do wrapper Vulkan (D36): tem libstdc++/libc++ disponível? → **C++**. Sem runtime C++ (OS custom) → **C puro** (única língua que sempre está lá). **Decidir antes do milestone Vulkan** (pós-M6/M7). |

---

## 🔴 IMMEDIATE — Correção de Bugs

> **Estado atual: `make test` completa** — **182 testes / 31 suites ✅** (2026-08-11), incluindo a matriz W3C de blend modes (`W3CBlendMatrixTests`: 12/12 operadores × fórmula W3C §6/§9.1 com αs ≠ αb + coverage como alpha + degenerados). IMM-4 reclassificado como falso positivo — verificado contra W3C Compositing-1 §9.1.11 e histórico do git (blitter intocado desde M3a/M3b).

| # | Bug | Estado |
|---|-----|--------|
| IMM-1 | **`swift test` pendura** — `applicationDidFinishLaunching` agendado como `VNRunLoopSource` (dispara na primeira iteração); `terminate()` inside delegate agora seta `_isStopped` antes da próxima checagem do `while` | ✅ corrigido |
| IMM-2 | **`VNPath.flattened()`** — `subpathStart` rastreado; `.close` reseta `current = subpathStart` | ✅ corrigido |
| IMM-3 | **Cobertura com arestas coincidentes** — comportamento verificado e coberto por 3 testes: nonZero clamp ≤1, opostos cancelam, even-odd dobra back | ✅ verificado |
| IMM-4 | **`VNPorterDuffBlitter` `.destinationAtop` — FALSO POSITIVO da auditoria de 2026-08-11**: código verificado correto per W3C Compositing-1 §9.1.11 (`Fa = 1−αb; Fb = αs` → `co = αs·Cs·(1−αb) + αb·Cb·αs`); git confirma blitter intocado desde M3a/M3b. Lacuna real: só 7/12 operadores tinham teste e nenhum com fórmula completa (αs ≠ αb) — fechada pela matriz W3C em `W3CBlendMatrixTests` (12/12 operadores + coverage + degenerados) | ✅ verificado |
| IMM-5 | **Joins do stroker aproximados** (`VNStroker.joinPoint`) — miter-limit excedido cai para ponto na bissetriz a distância `half` (não bevel; sub-preenche); round join emite vértice único na bissetriz (corda inscrita, canto "chato"); bevel emite A→bissetriz→B (sobre-preenche). Contradiz D17 "cobertura exata". Faltam testes de geometria de join | ✅ corrigido (2026-08-12) — `emitJoin` detecta lado convexo/côncavo via cross product; `emitConvexSide` emite miter/bevel/round corretos; `lineIntersect` para o lado côncavo; 6 testes `StrokerJoinTests` |
| IMM-6 | **Race MIT-SHM single-buffer (X11)** — `XShmPutImage` sem completion event + sem `XSync`; o app pode reescrever o segmento enquanto o servidor lê. `freeSHMBuffer()`/`didResize`/`deinit` fazem detach sem sync. Hardening: completion event ou ring de buffers | ✅ corrigido (2026-08-12) — `XSync(display, 0)` após `XShmPutImage` garante que o servidor terminou de ler antes do próximo frame |

---

## 🟠 HIGH — Marcos de Fundação (M1–M7)

| M | Marco | Status | Detalhes |
|---|-------|--------|----------|
| M1 | Detecção de ambiente | ✅ (2026-08-09) | `VNEnvironment` + `VNDisplayServer`/`VNSessionType`; 31 testes ✅ |
| M2 | Geometria | ✅ (2026-08-11) | `VNPoint`/`VNSize`/`VNRect`/`VNInsets`/`VNColor` (structs `Sendable`); unidades em points + escala (D9); sRGB `Double` 0…1 (D15); 30 testes ✅ |
| M3a | Rasterizador — seam + analítico (arestas retas) | ✅ (2026-08-11) | `VNFramebuffer` (RGBA8, stride, **premultiplied** D24, pixels = points × scale); `VNAnalyticScanConverter` (sweep line, y críticos, AET, trapézios, cobertura exata D17) → buffer denso de cobertura → `VNPorterDuffBlitter` (**spans por coluna pendentes**, D18); `VNPath` (move/line/close, `windingRule` D22), `VNAffineTransform`, `VNColor`, `VNBlendMode` (Porter-Duff D23); `VNGraphicsContext` (save/restore, translate/scale/rotate, fill/stroke, blend; **clip pendente** D13); `VNRasterizer`; testes por pixel |
| M3b | Rasterizador — curvas + primitivas completas | ✅ (2026-08-11) | `VNPath` ganha `addCurve`/`addQuadCurve`/`addArc` com **flatten adaptativo 0.1px** (padrão gg/Go + Skia); rounded rect, ellipse/círculo (D21), stroke com cap/join; cobertura×alpha (D19); testes: área de círculo ≈ πr², erro de flatten < 0.1px, roundRect, stroke |
| M3c | Compositing conforme W3C (matriz + grupos isolados + base glass) | ✅ (2026-08-12) | **Matriz Porter-Duff ✅** — `W3CBlendMatrixTests`: 12 operadores × caso não-trivial αs=0.6 ≠ αb=0.4; **grupos isolados §9.2 ✅** — `beginTransparencyLayer(blendMode:)` + `endTransparencyLayer()` em `VNGraphicsContext`; `blendPremul` em `VNPorterDuffBlitter` para composição premul×premul; 7 testes `TransparencyLayerTests` (empty group, sourceOver, sourceIn/destinationIn em grupo vazio, blend modes de grupo, grupos aninhados, pixel W3C); **composição glass** adiada para M12 (precisa de blur Gaussiano do M11) |
| M4 | Core backbone | ✅ (2026-08-11) | `VNRunLoop` (modes, sources, timers, observers) + `VNApplication(backend:)` + `VNApplicationDelegate` (D11) + protocolo `VNBackend`/`VNSurface(present:)`; IMM-1 corrigido; polling via `beforeWaiting` (P1 v1); 182 testes ✅ |
| M5 | Backend X11 | ✅ (2026-08-11) | `VulpinaX11` + `ClibX11` + `ClibXext` (`systemLibrary(pkgConfig:)`); `VNX11Backend` + `VNX11Surface`; janela, expose, blit via MIT-SHM (XPutImage fallback, D27); polling 60Hz (P1); `backingScaleFactor` via Xft.dpi (D9); WM_DELETE_WINDOW (D12); P2 v1: aceitar cópia única, MIT-SHM interno ao backend |
| M6 | VNView | ✅ (2026-08-12) | `VNView`: `frame`/`bounds`, `isFlipped=false`, `draw(_ context:)` (D13), `setNeedsDisplay` + propagação + z-order (D14); `VNWindow`: display cycle via `beforeWaiting` observer, y-flip no compositor, clip por view em `VNGraphicsContext` ✅; 13 novos testes |
| M7 | Input | ✅ (2026-08-12) | `VNEvent` (mouse/key/scroll, `VNModifierFlags`); `VNResponder` (chain, becomeFirstResponder); `VNView` herda `VNResponder` + `hitTest` + `convert(_:from:)`/`convert(_:to:)`; `VNWindow.sendEvent` (hit-test routing, drag tracking, firstResponder); `VNSurface.onEvent` callback; X11 tradução completa (ButtonPress/Release, MotionNotify, KeyPress/Release, scroll buttons 4–7); `MouseTrackerView` no demo (D30); 26 novos testes |

---

## 🟡 MEDIUM — Views Avançadas (M8–M11)

| M | Marco | Status | Detalhes |
|---|-------|--------|----------|
| M8 | Texto | ❌ | **Próprio em Swift** (D25): parser TTF/OTF (cmap/glyf/hmtx), shaping básico Latin + kerning, glyphs via nosso converter analítico; modelo **TextKit-like** `VNTextStorage`→`VNLayoutManager`→`VNTextContainer` (D26); depois `VNLabel` |
| M9 | Backend Wayland | ❌ | `VulpinaWayland` + `ClibWayland`; wl_shm buffer + attach/commit; event source |
| M10 | Controles/layout | ❌ | `VNButton`, autoresizing `NSAutoresizingMask`-style (D29), gerenciamento do frame de `VNWindow` |
| M11 | Gradientes/sombras | ❌ | gradientes lineares/radiais + sombras (drop shadow) — logo após a fundação (D31) |
| M12 | Efeito glass | ❌ | material **liquid-glass (Apple) / frosted-glass (pop!OS)**: captura de backdrop + blur Gaussiano + tint semi-transparente + composição sobre o conteúdo (base: composição de M3c + blur de M11); API/escopo decididos em P7 |

---

## 🔴 Code Quality Debt

| Item | Status |
|------|--------|
| **Commit do M2–M5** | ✅ commitado (8 commits, topo `27eea01`); IMM-5/IMM-6/M3c commitados em `27eea01` |
| **Matriz de blend modes** | ✅ fechada em `W3CBlendMatrixTests` (2026-08-11) — 12/12 operadores × fórmula W3C §6/§9.1 com αs ≠ αb, coverage e casos degenerados; reclassificou o IMM-4 como falso positivo |
| **Demo `VulpinaDemo`** | ✅ criado (2026-08-12) — `swift run VulpinaDemo`; header bar, swatches, círculos, stroke sampler, `MouseTrackerView` interativo (crosshair + drag rectangle, D30) |
| **README desatualizado** | ⚠️ diz "M5 next" (já feito) e "137 testes" (hoje 182); sincronizar com este TODO |
| `.ai-docs/` | ✅ CHANGELOG/ROADMAP/ARCHITECTURE criados (D32); AUDITS quando houver histórico |
| Doc comments em 100% do public API (AGENTS.md) | ⚠️ obrigatório; auditar ao fechar cada marco |

---

## 🟢 LOW — Polimento e Longo Prazo

| Item | Notas |
|------|-------|
| Renderer GPU (Vulkan: tesselação+MSAA → compute-coverage) | **P3 revisada (2026-08-12)**: Vulkan como API única — fase 1 tesselação+MSAA (shippable), fase 2 compute-coverage (endgame, onde o Vulkan se paga); seam no layer/framebuffer com compositor compartilhado (W3C sobrevive entre layers); milestone próprio pós-M6/M7; interop via D35/D36; `deviceType == CPU` (Lavapipe) → analítico |
| Fixed-point (24.8/16.16) | otimização do scan converter, **gated por benchmark** (D20) |
| Rasterizador — alocações | buffer de cobertura `[Float]` W×H alocado por draw op; `VNFramebuffer.clear()` realoca o array; reuso de buffers quando M6 trouxer muitas views |
| `VulpinaDemo` completo | demo **interativo** desde M5: mouse move desenha retângulo (D30); evoluir para kit completo |
| Benchmark do rasterizador | throughput de preenchimento/alpha em largura real |
| Math/GeometryForms (D33) | camada de geometria: protocolo `VNShape` (`area`/`perimeter`), área exata via Green + `length(at t:)` com erro certificado; `VNPath` migra de `Rasterizer/`; consumidor inicial: testes (fim do shoelace ad hoc) |
| Suporte de temas/cores | futuro |
| Wide color — simulação Display P3 em software | telas comuns são sRGB e sem pipeline color-managed: compor com working space de primárias DCI-P3 (gamma sRGB) e **gamut-map perceptual na apresentação** (compressão preservando matiz, neutros neutros, sem clipping); reutiliza o `Double` do D20 e prepara para `color-management-v1` (Wayland, staging) — decisão P8 |

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
- Rasterizer specs: Skia CPU backend + Analytic AA (`SkScan_AAAPath`), FreeType `smooth` (FT_Raster), stb_truetype signed-area, cairo fixed-point (24.8); GPU compute-coverage: Vello (linebender, wgpu) — prova que a cobertura analítica porta para GPU sem tesselação
- Renderer GPU (2026): **Vello ainda alpha** (README: "considered in an alpha state"; blur/filter effects em andamento) — compute-coverage não é produção nem na referência; **Skia Graphite** (Chrome future backend, blog.google jul/2025): "relies on MSAA where it can... fallback to CPU path rasterization using an atlas"; AA do Skia GPU = "binary coverage per sample, MSAA resolve" (skia-discuss); **NV_path_rendering** (Kilgard 2012): conflation documentado ("dark cracks") em Cairo/Qt/Skia/Direct2D, Stencil-then-Cover como cobertura separada da opacidade
- Vulkan: spec WSI (`VK_KHR_xcb_surface`/`xlib_surface` — swapchain xcb envia protocolo pela conexão e **proíbe server grab** enquanto espera = gotcha com o backend X11 existente); Mesa RADV (GCN1-2 → Vulkan 1.3, 1.4 recente via Mesa 26.2)/ANV/NVK; FreeBSD via `mesa-dri` (RADV/ANV + `vulkan-loader`; `vulkan-wsi-layer` apresenta Vulkan via MIT-SHM no X11); `VkPhysicalDeviceType.CPU` = Lavapipe/software → hook do environment
- Swift interop: **Swift não importa ObjC fora da Apple** (desabilitado no compilador; thread "Cross-platform Objective-C Interop with GNUStep" mar–abr 2026 — blockers: object model objc4 vs libobjc2, memória, metadata, bridging; John McCall: "tenable" sem timeline); **SE-0403 mixed-language targets = Returned for Revision** (SwiftPM continua exigindo targets separados por língua); `SwiftVulkan` (ctreffs) = bindings finas (10 stars, última release 2023)
- Composição (W3C): Compositing and Blending Level 1 — operadores Porter-Duff §9.1 (fatores Fa/Fb por operador), grupos isolados/knockout §9.2; `backdrop-filter` (CSS Filter Effects Module Level 2)
- Wide color (Apple/macOS): Display P3 = primárias DCI-P3 (ICC registry v1.0 2022: R 0.68/0.32, G 0.265/0.69, B 0.15/0.06) + D65 + gamma sRGB (`NSColorSpace.displayP3`); painéis P3 desde iMac 5K (2015); **ColorSync** = gerenciamento de cor no sistema inteiro (GLFW issue #2748: sem `setColorSpace`, app em tela P3 fica escuro/oversaturado); paleta de sistema com variantes light/dark tunadas por modo (HIG Color, atualizado jun/2025 — Apple **não** publica hex oficial, valores são medições da comunidade); vibrancy = `NSVisualEffectView` = blur + tint + boost `colorSaturate` (filters do `CABackdropLayer`); Liquid Glass (macOS 26/Tahoe) = lensing/refração
- Wide color (Linux): Wayland `color-management-v1` = análogo do ColorSync — mergeado upstream fev/2025 (5 anos, 800+ comments; staging), wlroots mar/2025, Chromium jul/2025 (testado no KDE Plasma 6.4.2), driver NVIDIA pendente; dark/light = `org.freedesktop.appearance.color-scheme` via xdg-desktop-portal (não nome de tema GTK — armadilha do Qt6)
- Texto (Apple/TextKit): `NSTextStorage`/`NSLayoutManager`/`NSTextContainer` — modelo de escrita em folha (D26); parser TTF/OTF próprio (cmap/glyf/hmtx)
- `.ai-docs/` — CHANGELOG/ROADMAP/ARCHITECTURE criados (D32, desde o M2)
