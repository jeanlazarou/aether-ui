# Roadmap: what to engineer next

**Status: PROPOSAL.** 2026-07-12. Successor to the re-namespace plan
(executed and deleted; see commits 3c4583a..a36647d for the plan and the
Swing/Flutter/SwiftUI namespace comparisons): that settled where things
live; this is what to build there next, pulling from SwiftUI, Flutter,
QML, and Swing.

## Method: the stress test already ran

grand_perspective (and fight_flash_fraud, and the month's platform work)
was a de-facto audit of the toolkit. Every place an app hand-rolled
something is a missing feature with evidence attached:

| Wound (what we hand-rolled / suffered)                      | Missing feature |
|--------------------------------------------------------------|-----------------|
| Breadcrumbs = fixed pool of 8 buttons, relabelled/hidden      | dynamic children (`each`) |
| List pane hand-drawn in canvas: rows, hit-test, "+N more…"    | table/list widget |
| GTK popovers never display on sommelier; picker unusable there| in-window overlay layer |
| Text draws ~17px above requested baseline; 3 bugs, every call site compensates | typography layer |
| Tile depth faked with a 5-rect bevel                          | shadow effect |
| Stop/Rescan ghosting and radio flips snap instantly           | implicit transitions |
| Three panes fixed-width inside one canvas                     | split panes / flex weights |
| Imperative `set_text` everywhere; state is doubles-only       | declarative bindings, typed state |
| Focus grabbed ad hoc; keyboard nav wired per-app              | focus & shortcut system |
| Open/Reveal shell out to xdg-open; no save/open dialog        | file dialogs |

The ranking below is by (foundation-ness × evidence), not by shininess.

## The ranked items

### 1. In-window overlay layer — the Swing z-layer, aimed at our sorest wound ✅ DONE (2026-07-12)

**Shipped** (commits 526bd6a host + toast + modal scrim, 27ad331 drawn
tooltip, a9d73dc drawn dropdown): the full overlay layer + all three D3
consumers. A GtkOverlay is interposed lazily between window and root
(zero change when no overlay is open); `ui.overlay`/`overlay_modal`/
`dismiss_overlay`/`toast` DSL; a full-window modal scrim (glass pane)
that eats clicks (proven by a real-hit-test `GET /window/pick` resolving
the scrim ahead of the button beneath it); a drawn tooltip for vg scenes
(`vg_tooltip_*`, wired into the vg live hover path, gated
`$AETHER_UI_TOOLTIP=drawn`); a drawn dropdown picker (a button trigger +
overlay list behind the same picker ABI, gated `$AETHER_UI_PICKER=drawn`,
ABI parity with the native GtkDropDown proven by a surface-agnostic
spec). `GET /overlays` + `GET /window/pick` driver routes; examples
overlay_demo / vg_tooltip and the picker example, specs at ci.sh Phases
5b/5c/5d (6+4+3 checks). win32/macOS stubs. Full ci.sh green. Because
everything draws in-window (no xdg_popup), it works on sommelier by
construction (design fact, not machine-verifiable on this box). Detail
below is the original proposal, kept for the reasoning.

**Borrowed from:** Swing `JLayeredPane` (POPUP_LAYER / MODAL_LAYER / glass
pane) — its menus worked everywhere *because they were drawn in-window*,
not compositor popups. Flutter `Overlay` + `OverlayEntry` is the modern
restatement: a dropdown is just paint. SwiftUI `.overlay`/`.popover`.

**Evidence:** the context-menu saga. GTK4 popovers (xdg_popup) report
mapped=1 but never display under sommelier (ChromeOS); `picker`
(GtkDropDown) is unusable there for the same reason; we shipped a
window-fallback hack gated on `$SOMMELIER_VERSION`. An overlay stack
converts our worst platform liability into a non-issue by construction.

**Shape:** a per-window z-ordered stack of vg scenes above the widget
tree (vg.region already has per-region z — the compositing primitive
exists). DSL: `ui.overlay { … vg or widgets … }`, `ui.dismiss_overlay()`,
plus the three consumers that prove it: a drawn dropdown (replaces
picker on hostile compositors), tooltips, toasts. Modal scrim = a
full-window overlay that eats clicks (Swing's glass pane, literally).

**Effort:** M (1–2 weeks incl. the drawn dropdown + driver routes + specs).
**Risk:** low — no new compositor surface is the whole point. Input
routing (overlay eats clicks first) needs care with the canvas legacy
controllers. **Depends on:** nothing. **Unlocks:** menus/dropdowns/
tooltips/toasts portable across GTK4/sommelier/Win32/AppKit.

### 2. Typography layer — metrics, measurement, wrap ✅ DONE (2026-07-12)

**Shipped** (commits 9e55d0c Phase A, 12c32cc Phase B baseline fix,
aa78062 Phase C metrics API, f299b06 Phase D sweep): the text
double-correction is fixed (SVG conformance rose 195→196 good), and there
is now a real measurement surface — `vg.text_extent(size,s) -> (w, height,
ascent)`, `vg.text_width`, `vg.font_ascent/descent/height`, `vg.ellipsize`
(cairo-backed on GTK4; win32/macOS stubbed → 0). A GET /text_extent driver
route + Aeocha spec (5/5) and a 16-check unit test cover it. gp's every
`+17` compensation is gone, re-derived from real metrics (row_baseline
helper). Stretch goals NOT done (own follow-up if wanted): multi-line
wrap (`text_wrapped`) and text-anchor middle/end; win32/macOS real GDI/
CoreText metrics (deferred to those boxes). Detail below is the original
proposal, kept for the reasoning.

**Borrowed from:** Flutter's layering lesson: the paragraph/painting
layer shipped *before* the widget layer because everything sits on it.
SwiftUI `Text` metrics; QML `TextMetrics`/`FontMetrics`.

**Evidence:** the renderer draws text at a fixed ~17px above the
requested baseline. Three separate visual bugs this month (clipped list
header, legend labels floating a line above their chips, the ".." row
missing its own click zone) — and every call site now carries a hand-
tuned `+17`. There is no way to measure a string, so labels clip by
character count (`clip_name`), not by width.

**Shape:** real font metrics in the vg text path (ascent/descent/line
height per size), `vg.text_extent(size, s) -> (w, h, baseline)`,
ellipsize-to-width, multi-line wrap with alignment. Then a one-time
sweep deleting every `+17` compensation (they're all commented).

**Effort:** M (renderer work + call-site sweep + conformance re-run —
the ~86% librsvg parity number guards against regressions here).
**Risk:** medium — touching the text path can move the SVG conformance
needle; the compare harness is the gate. **Depends on:** nothing.
**Unlocks:** items 4 and 9; honest labels everywhere.

### 3. Dynamic children — `each` (smaller than a QML Repeater) ✅ DONE (2026-07-13)

**Shipped** (commits 7216239 verb+demo+spec, a552550 gp crumbs; plus the
compiler work it forced: aether PR #1125 fixed closure-in-closure capture
[filed by us], and aether PR #1127 — AUTHORED by us — made closure envs
retain captured heap strings; both released, toolchain on v0.390).
`ui.each(orientation, spacing) callback |item, i, parent| {…}` +
`each_update(e, items)` — an owned group container, clear+rebuild
reconcile, ng-repeat-without-track-by semantics; explicit update (item 8
adds the binding overload later). examples/each_demo + 6/6 Aeocha spec
(ci.sh Phase 5e) prove add/remove/reset and — the assertion that was
GARBAGE before v0.390 — that each per-item closure fires with ITS item's
computed label. Proving consumer: gp's breadcrumb pool of 8 (and its
stale "widgets can't be created post-build" belief) replaced by real
dynamic crumbs; all 5 gp specs green unchanged. Item 4 (table/list) is
now un-gated. Detail below is the original proposal, kept for the
reasoning.

**Borrowed from:** QML's `Repeater`/model-delegate split — but Aether
needs LESS than QML did, on two counts verified 2026-07-12:

1. **The construction half already exists in the language.** Trailing
   blocks are *immediate* (inline code with the builder-context stack
   active), so first-class `while`/`for`/`if` inside a `window {}` block
   IS a build-time Repeater — grand_perspective already wires its crumb
   context-menus in a `while` loop inside the window block. QML needed
   `Repeater` because QML isn't an imperative language; Aether's DSL is
   ("DSL with scope" — see aether's closures-and-builder-dsl.md).
2. **Runtime creation + attach WORKS** (probed on GTK4): capture
   `here = builder_context()` inside the immediate block, and a later
   callback can do `aether_ui_text_create(...)` +
   `aether_ui_widget_add_child_ctx(here, h)` — the new widget appears in
   the live window and the driver's widget tree. The long-held "widgets
   can't be created post-build" belief (which forced the breadcrumb
   *pool* of 8 pre-made buttons) is STALE — probably true pre-ae-0.252,
   never retested.

**What's actually missing:** (a) child REMOVE/INSERT-AT in the backends
(append exists; removal doesn't), (b) a small reconciler that re-runs a
per-item `callback |item|` when a list state changes (identity by index
first; track-by later — vg.grammar.bind has `bind_trackby` as in-repo
prior art), and (c) an ergonomic `with_ctx(parent) { … }` wrapper so the
item closure builds children declaratively instead of calling externs.

**Effort:** M, downgraded from L (the two hard-looking halves turned out
to exist). **Risk:** low-medium — removal must release closures/handles
correctly (the widget registry is append-only today). **Depends on:**
nothing. **Unlocks:** item 4, real breadcrumbs, dynamic forms.

### 4. Table / list / tree widgets ✅ DONE (2026-07-13) — tree mode later

**Shipped** (commits 345a916 listbox, 04f9daf table, 4b5762c gp
migration): `ui.listbox` (each-backed real-widget rows, click +
programmatic selection via .aui-row-selected, on_select, reset-on-update,
200-row scale) and `ui.table` (column spec, header buttons firing
on_sort(col) — the app sorts and updates, the widget never owns data —
sized text cells from a |item,col|->string template). Proving consumer:
gp's whole hand-drawn left pane (draw_list + list_click, ~100 lines +
hit-testing + the "+N more…" fold) became a header block + ".." button +
table in a scrollview; canvas shifted left 280px; all 5 gp specs green
with clicks rewritten from canvas coords to widget rows. Driver-first
throughout: generic /widget/{id}/click now fires gesture handlers on
non-buttons, widget JSON gained "classes" (tracked, never read off-thread)
and window-local x/y. Two deep infrastructure fixes forced en route:
send_response write-all (>64KB bodies truncated on loopback), and ALL
widget-JSON GET routes serialized through g_idle_add (off-thread tree
walks trip GTK's css-node cache once rows churn — gtkcssnode.c:321
abort). NOT done (later, own items): virtualization/GtkColumnView (the
recycled-cell/handle-registry question stands), delegate cells (%-bars,
chips), row double-click, multi-select, tree mode. Detail below is the
original proposal, kept for the reasoning.

**Borrowed from:** Swing's genuinely great contribution — `JTable`/
`JTree` with the renderer/editor split and sortable columns. QML
`ListView` + delegates for the declarative shape; SwiftUI `List`/`Table`.

**Evidence:** grand_perspective's entire left pane — rows, chips,
selection outline, %-bars, hit-testing, and a "+N more…" fold instead of
scrolling — is ~300 lines of app code that should have been
`ui.table(columns…, rows_state)`.

**Shape:** virtualized rows over a list state, column spec with widths/
alignment, row selection synced to state, sort hooks, and delegate-style
cell content (a callback per cell, QML-style). Driver: rows and cells
visible in `/widgets` JSON, `select_row` route, uidriver helpers +
Aeocha matchers on day one.

**Effort:** L–XL (the flagship widget; virtualization + 3 backends).
GTK4 first via GtkColumnView; a vg-drawn fallback is plan B where native
tables fight us. **Risk:** medium. **Depends on:** 3 (models), 2 (cell
text measurement).

### 5. Effects: shadow, opacity groups, (later) backdrop blur ✅ DONE (2026-07-13) — backdrop blur later

**Shipped** (commit 2ebec4a): vg.shadow(dx,dy,sigma,color) on rects/
circles — silhouette → the existing gaussian blur → tinted raster drawn
under the shape, CACHED per element (position moves reuse the mask; idle
zero); vg.group_begin(alpha)/group_end — TRUE group opacity via cairo
push/pop group (overlaps composite once; proven at the PIXEL level by the
new canvas_read_pixel + GET /canvas/{id}/pixel primitives); ui.style_shadow
(CSS box-shadow via a new public apply-css ABI); toast + overlay-card
chrome shadowed. test_effects (12 asserts) + test_group_pixels in ci.sh;
SVG conformance unchanged (198/8/2). gp tiles deliberately NOT shadowed:
per-frame draw-region elements defeat the cache (documented; bevel
stays). Not done: paths/text shadows, backdrop blur (backlog). Detail
below is the original proposal, kept for the reasoning.

**Borrowed from:** SwiftUI `.shadow(radius:x:y:)`; Flutter `BoxShadow`/
`elevation`; QML GraphicalEffects (`DropShadow`, `FastBlur`); QML's
layer.enabled for group opacity.

**Evidence:** render_shaded's 5-rect bevel fakes depth on every tile;
vg already has gaussian blur (`vg/raster/blur.ae`) — a drop shadow is
blur + offset + tint of an alpha mask, mostly plumbing. No way to fade a
subtree (highlight-dim in gp re-colours every tile instead).

**Shape:** `vg.shadow(el, dx, dy, blur, color)` modifier; `ui`-side via
GTK CSS `box-shadow` for native widgets; `vg.group_opacity(g, a)`.
Backdrop blur (frosted overlay scrim) explicitly LAST — it's the
expensive one and only matters once overlays (item 1) exist.

**Effort:** S–M for shadow + group opacity; backdrop blur separate/later.
**Risk:** low; perf on big scenes → cache the blurred mask per element
like the recording cache. **Depends on:** nothing (pairs beautifully
with 1).

### 6. Implicit transitions — QML `Behavior`, not SwiftUI `withAnimation`

**Hand-off brief: `briefs/transitions.md`** (2026-07-12, ready for execution).

**Borrowed from:** QML's `Behavior on opacity { NumberAnimation {} }` —
declare once on a property, every subsequent setter animates. The most
markup-centric of the three designs (SwiftUI's `withAnimation` is a
call-site wrapper; Flutter's Animated* is a widget zoo).

**Evidence:** Stop/Rescan ghosting, radio flips, selection outlines —
all snap. The animation machinery (easing curves, the 60fps loop,
`scene_advance`) already exists in vg and idles at zero cost.

**Shape:** `ui.transition(handle, "opacity", 150ms, ease_out)` — then
`set_hidden`/`style_opacity`/enable changes tween instead of snap.
vg-side: `vg.behavior(el, "fill", 200ms)` reusing grammar.animations.
Enter/exit transitions for overlay entries (ties into item 1).

**Effort:** S–M. **Risk:** low — additive; per-property opt-in keeps the
driver deterministic (specs can assert the END state; add a
`settle`/no-animation env for CI like GSK_RENDERER=cairo).

### 7. Layout: flex weights, wrap, split panes, `on_layout`

**Hand-off brief: `briefs/layout.md`** (2026-07-12, ready for execution).

**Borrowed from:** Flutter `Expanded(flex:)`/`Flexible` (the constraints-
down-sizes-up model's user face); SwiftUI `layoutPriority` +
`GeometryReader`; QML anchors; every desktop toolkit's splitter
(GtkPaned exists and is unwrapped).

**Evidence:** gp's three panes are fixed-width in one canvas — no
splitters; `spacer()` is the only flex tool; the canvas resize hook we
built for the viewBox remap is a bespoke `GeometryReader` begging to be
generalized.

**Shape:** `weight(2)` modifier on stack children; `ui.splitview(h/v)`
wrapping GtkPaned/NSSplitView/Win32 splitter; `ui.wrap {}` flow
container; `on_layout(handle) callback |w,h|` (generalizing the canvas
resize hook). **Effort:** M. **Risk:** low. **Depends on:** nothing.

### 8. Declarative bindings + typed state

**Hand-off brief: `briefs/bindings.md`** (2026-07-12 — Phase A is a design memo).

**Borrowed from:** SwiftUI `@State`/`@Binding`; QML property bindings
(the whole language is bindings); our own vg.grammar.bind
(`bind_fill/bind_text/bind_pos`) — the pattern is already in-repo.

**Evidence:** `ui_state` is doubles-only (the calculator display reads
`42.000000`); everything else is imperative `set_text` from callbacks;
vg and ui have two different reactivity stories.

**Shape:** typed state (string/int/bool alongside float), `bind_text
(handle, state)`/`bind_enabled(handle, state)` on the ui side delegating
to the same refresh machinery vg uses; driver `/state` grows typed
routes. **Effort:** M. **Risk:** low-medium (unifying two reactivity
systems is the design work, not the code).

### 9. Focus, tab order, shortcuts

**Hand-off brief: `briefs/focus.md`** (2026-07-12, ready for execution).

**Borrowed from:** Swing's second great contribution: `InputMap`/
`ActionMap` (declarative keystroke→action, per focus scope). SwiftUI
`.keyboardShortcut`; QML `Shortcut`.

**Evidence:** the canvas grabs focus with a bespoke map-signal dance +
a re-grab on click; gp's keyboard nav is wired per-app; the sommelier
focus-click gesture never fires (legacy-controller lesson). No
accelerators (menu items show no Ctrl+…).

**Shape:** `ui.shortcut("Ctrl+R") callback {}` per window (InputMap,
essentially), sane default tab order from build order + `focus_group`,
driver route to query/set focus so specs can assert it. **Effort:** M.
**Risk:** low.

### Backlog (real, smaller, or gated)

- **File dialogs** (`ui.open_file`/`save_file` → GtkFileDialog/NSPanel/
  IFileDialog) — gp shells out to xdg-open today. S, do opportunistically.
- **Tab view** (`ui.tabs`) — navstack exists; tabs don't. S–M.
- **Drag & drop** — inter-widget first (list reorder), inter-app later. M.
- **Multi-window** — one window per app today (surface table is
  single-window by design). M, needs a driver story (window ids in
  `/widgets`). Defer until an app needs it.
- **Accessibility** — native widgets get GTK/AppKit a11y free; anything
  vg-DRAWN (item 1's dropdown, item 4's plan-B table) needs a semantics
  bridge eventually — this is the real cost of the drawn path, and why
  Flutter maintains a semantics tree. Track it; don't block on it.
- **Backdrop blur / materials** — after 1 + 5.

## The strategic fork (not scheduled): vg-drawn controls

The Flutter turn — a widget set *drawn by vg* — would make every control
pixel-identical across backends, fully themeable, effect-capable, and
immune to compositor politics. The costs are exactly Flutter's costs:
you take on a11y (semantics tree), IME/text input (brutal), and
"platform-feel" drift. SwiftUI's hybrid is the likelier right answer for
a three-backend toolkit: **native text inputs, drawn chrome** — draw
what natives do worst across our platforms (menus, dropdowns, overlays,
maybe tables), keep native what they do best (entries, IME, a11y).
Items 1, 2, and 5 are deliberately the foundations of that hybrid, so
this fork stays open without being committed to. If/when it's serious,
it gets its own comparison-doc treatment first (the re-namespace plan's
format: comparisons, verdict, phased ci-gated migration).

## House rules (carry-overs from this month, now policy)

1. **Driver-first widgets:** every new widget/effect ships with its
   `/widgets` JSON representation, driver routes, uidriver helpers, and
   an Aeocha spec in the same commit (the `toggle_group` precedent).
2. **Sommelier is a release gate** for anything compositor-adjacent —
   test on the Chromebook before calling it done; never let a Crostini
   workaround become the default (gate on `$SOMMELIER_VERSION`).
3. **Idle must cost zero** — the static-until-dirty discipline
   (region_set_animated lesson) applies to transitions and overlays too.
4. **Headless parity:** everything renderable must render via
   canvas_write_png so specs can screenshot it (the /screenshot path).

## Suggested sequence

| Order | Item | Size | Why this order |
|-------|------|------|----------------|
| 1 | Overlay layer ✅ | M | DONE 2026-07-12 (526bd6a/27ad331/a9d73dc) — host + toast + modal scrim + drawn tooltip + drawn dropdown; sommelier-proof by construction |
| 2 | Typography ✅ | M | DONE 2026-07-12 (9e55d0c/12c32cc/aa78062/f299b06) — +17 debt gone, metrics API + driver route shipped |
| 3 | `each` ✅ | M | DONE 2026-07-13 (7216239/a552550 + aether PRs #1125/#1127) — verb + spec + gp crumb pool retired |
| 4 | Table/list ✅ | L | DONE 2026-07-13 (345a916/04f9daf/4b5762c) — listbox + table + gp left pane migrated; virtualization/delegate cells deferred |
| 5 | Shadows + group opacity ✅ | S–M | DONE 2026-07-13 (2ebec4a) — vg.shadow cached + true group opacity + chrome shadows; backdrop blur deferred |
| 6 | Implicit transitions | S–M | Perceived quality; machinery exists in vg |
| 7 | Flex/split/on_layout | M | Unblocks real multi-pane apps |
| 8 | Bindings + typed state | M | Unify ui/vg reactivity |
| 9 | Focus/shortcuts | M | Polish + testability |
