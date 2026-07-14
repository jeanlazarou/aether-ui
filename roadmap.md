# Roadmap: what remains

**Status: PARED DOWN.** 2026-07-14. The nine-item ranked roadmap of
2026-07-12 (overlay layer, typography, `each`, table/list, effects,
transitions, layout, bindings, focus) was executed in full on
2026-07-12/13 — see git history for the original document with its
per-item DONE blocks, evidence tables, and commit trails (last full
version at 1ade88b; the wound-driven method writeup lives there too).
This document now lists ONLY what is not done, in three buckets:
platform parity, deferred follow-ups, and the backlog/strategic fork.

## 1. Platform parity

### macOS — DONE 2026-07-14. Full parity; `./ci.sh` all phases pass.

The AppKit backend is no longer the stubbed one. Every item that was
listed here as a macOS gap is real, and the spec matrix is **81/81
green on the Mac** (`./tests/spec_matrix.sh`), including all five
grand_perspective app suites.

| Feature | macOS today |
|---|---|
| Driver introspection + `/focus` `/window/key` `/window/resize` | **shared server** — the private one is deleted (see below) |
| Text metrics (`vg.text_extent`) | CoreText (`CTLineGetTypographicBounds`) on the SAME font the canvas draws with |
| splitview | real `NSSplitView`, draggable divider (NB its `vertical` is the INVERSE of GTK's) |
| weight / on_layout / wrap | Auto Layout multiplier constraints / frame-change observer / `AetherWrapView` flow layout |
| shortcut (accelerators) | one `NSEvent` local monitor + a normalized-combo registry |
| focus (grab / `GET /focus` / Tab) | `makeFirstResponder:`; **Tab follows BUILD order** (matches GTK — see below) |
| Overlay layer (toast/modal/tooltip/dropdown) | `AetherOverlayHost` interposed under the window; real scrim, hit-test-blocking |
| Context menus | `-[NSView setMenu:]` (the native right-click shape) |
| Canvas on_click/on_key/on_release/on_resize, clip_rect, `canvas_write_png` | all real; write_png is headless (CGBitmapContext) |
| Implicit transitions (`ui.transition`) | hand-driven tween (NOT `-[NSView animator]` — see below) |
| toggle_group | real radio exclusivity |

**The big structural change: macOS adopted the shared test server.**
It used to carry its own ~370-line HTTP server, which had drifted badly
(no `enabled`/geometry/`classes` fields, no `/focus`, `/window/key`,
`/window/resize`, no tray/notification routes, no URL-decoding, and it
read NSView state straight off the server thread). It is gone; macOS now
fills in `AetherDriverHooks` exactly as win32 does. **The "three-servers
rule" is back to two** — GTK4's embedded one, and the shared one behind
both other backends.

**Routes added to the SHARED server** (so win32 gained them too — they
had been GTK4-only, which is why split/overlay/canvas specs were red on
*both* non-Linux backends regardless of backend quality):
`/text_extent`, `/overlays`, `/window/pick`, `/canvas/{id}/click|move|key`,
`/widget/{id}/split_position`, `/widget/{id}/context_menu[/{idx}]`,
`/shutdown`, plus `splitPosition` and `selected` in the widget JSON.

Traps found the hard way, all now commented at their site:
- **Tab order.** AppKit's key-view loop only walks text fields unless the
  user has *Full Keyboard Access* on system-wide — Tab order would depend
  on a setting outside the app. macOS therefore walks the widget registry,
  whose order IS build order. **macOS matches GTK here where win32 cannot.**
- **Geometry must report the ALIGNMENT rect, not the frame.** An
  `NSTextField`'s frame is ~2px wider per side than the box Auto Layout
  positions; reporting frames made adjacent siblings look like they
  *overlapped* by 4px and a row's widths sum past its container.
- **Expand must propagate UP, retroactively.** GTK: a box holding an
  expanding child expands. AppKit has no such rule, and the DSL assembles
  top-down (a container joins its parent *before* its children arrive) —
  so the canvas announces "I expand" long after its row was already
  height-chained to its siblings. `aeui_mark_expand` walks up and retracts
  those chains. Without it, Grand Perspective's treemap was pinned to the
  toolbar's height and everything below the fold was unclickable.
- **`-[NSView animator]` is invisible to the driver.** It sets the model
  value immediately and animates the *presentation* layer, so every
  mid-tween screenshot already shows the settled frame. Transitions are
  hand-stepped on a timer so intermediate states are real and assertable.
- **`ui.style_opacity` travels as CSS**, not through the `set_opacity` ABI
  call. Miss that in `apply_css` and every declared transition snaps.

Not fixed (cosmetic, pre-existing, not spec-covered): **buttons stretch
vertically** to absorb a vstack's slack (they carry contentHugging 200),
so a table header or a lone button row renders very tall. The calculator
*depends* on this for its grid look. The principled fix is to give buttons
natural vertical hugging and let apps opt into stretch via `ui.weight` —
but that changes how the calculator renders, so it wants a look at GTK
side-by-side first.

### win32 — the gaps that remain

Real: focus/Tab (dialog order, not build order), driver introspection,
state/bindings, and now everything the shared server gained above.
Still stubbed: **splitview** (plain stack, no divider — `split_position`
honestly answers -1), **overlay layer**, **shortcuts** (`/window/key`
answers `fired:false` honestly), **text metrics** (GDI), **weight /
on_layout / wrap**, canvas `on_click`/`on_key` (only `on_move` is wired).

**Windows spec-matrix baseline (2026-07-14, winbaz):** calculator 9/9,
each 6/6, listbox 6/6, table 4/4, bindings 6/6. Red: testable (shortcuts
unwired; Tab is Windows dialog order), split + overlay (stub features).
NB this baseline PREDATES the shared-server route additions above — it is
worth re-running, since several of those reds were the server missing the
route rather than the backend missing the feature.

**Re-running the matrix:** `./tests/spec_matrix.sh [suite...]` — committed
now, and portable across all three backends. (The Windows equivalent lived
in a session scratchpad and was never committed, which is why this note
used to say "see session scratchpad / memory".)

## 1b. Bugs the macOS pass turned up that were NOT macOS bugs

Three of these are real defects that Linux/gcc was simply kind enough to
hide. They are fixed, and they are worth knowing about.

- **`aeb` timed builds died on any BSD `date`** (`tools/aeb-driver.ae`).
  `date +%s%3N 2>/dev/null || date +%s000` reads like a fallback but isn't:
  BSD `date` does not understand `%N`, yet it *succeeds* and prints a
  literal `"1784014092N"`. Exit status 0, so the `||` branch never runs,
  and `$((_e-_s))` then dies with *"value too great for base"* — failing
  the make target with error 127 on every timed node. Now validates the
  OUTPUT, not the exit code. (Fixed in the `aeb` repo, not this one.)

- **A real heap-buffer-overflow in `vg/test/test_live_region.ae`.**
  `struct Rec { int, float, int }` is 24 bytes (the `int` at offset 16),
  but was allocated with `malloc(16)`. glibc rounds a 16-byte request up
  to a 32-byte bin, so the overflow lands in slack and nothing complains;
  macOS's allocator uses a 16-byte bin, the write corrupts the free list,
  and the process aborts several statements later. ASan named it in one
  run. **The bug was always there — only one libc was hiding it.**

- **`string_char_at` sign-extends binary bytes.** libaether's header
  declares it returning `char`, but codegen prototypes it as `int`. On
  x86-64 only `AL` is defined for a `char` return: gcc happens to
  zero-extend (Linux reads 255), Apple clang sign-extends (macOS read -1).
  Any Aether code reading image/base64 bytes ≥128 through it is silently
  wrong. The two affected tests now mask to 0..255. **The real fix belongs
  in libaether** — either make the declaration honest or add an unsigned
  `string.byte_at`. Worth raising upstream.

- **Apple clang makes `-Wint-conversion` an ERROR** where gcc warns, so a
  latent type bug in `apps/analog_clock_png` (a variable reused for both a
  string error-slot and an int) failed the build outright on macOS.

## 2. Deferred from the ranked items (recorded at each closeout)

- **Typography:** multi-line wrap (`text_wrapped`), text-anchor
  middle/end.
- **Table/list:** virtualization (the GtkColumnView / recycled-cell vs
  handle-registry question), delegate cells (%-bars, chips), row
  double-click, multi-select, **tree mode**.
- **Effects:** shadows on paths/text (rect+circle only today),
  **backdrop blur** / materials (frosted scrim).
- **Transitions:** enter/exit transitions on overlay ENTRIES (the
  chrome fade-ins exist; per-entry slide/fade doesn't).
- **Layout:** weight-share min-clamping (weighted children can be
  squeezed below their minimum), RTL.
- **Bindings:** list-typed state (`each_bind`/`table_bind` — an update
  to a list state drives today's explicit `each_update`/`table_update`
  internally), two-way binding (textfield ⇄ string state), computed/
  derived state. Design notes in docs/design/reactivity-unification.md §5.
- **Focus/shortcuts:** per-widget/conditional shortcut scopes, chorded
  shortcuts, auto menu↔shortcut binding (accel display exists; wiring
  is two lines by hand today).
- **Menus:** GTK4 native menu wiring (GMenu/GActionGroup) is still the
  recorded stub — menu items don't fire on GTK4; the drawn context menu
  is the working surface.

## 3. Backlog (real, smaller, or gated)

- **File dialogs** (`ui.open_file`/`save_file` → GtkFileDialog/NSPanel/
  IFileDialog) — gp shells out to xdg-open today. S, do opportunistically.
- **Tab view** (`ui.tabs`) — navstack exists; tabs don't. S–M.
- **Drag & drop** — inter-widget first (list reorder), inter-app later. M.
- **Multi-window** — one window per app today (surface table is
  single-window by design). M, needs a driver story (window ids in
  `/widgets`). Defer until an app needs it.
- **Accessibility** — native widgets get GTK/AppKit a11y free; anything
  vg-DRAWN (the dropdown, a plan-B table) needs a semantics bridge
  eventually — this is the real cost of the drawn path, and why Flutter
  maintains a semantics tree. Track it; don't block on it.

## The strategic fork (not scheduled): vg-drawn controls

The Flutter turn — a widget set *drawn by vg* — would make every control
pixel-identical across backends, fully themeable, effect-capable, and
immune to compositor politics. The costs are exactly Flutter's costs:
you take on a11y (semantics tree), IME/text input (brutal), and
"platform-feel" drift. SwiftUI's hybrid is the likelier right answer for
a three-backend toolkit: **native text inputs, drawn chrome** — draw
what natives do worst across our platforms (menus, dropdowns, overlays,
maybe tables), keep native what they do best (entries, IME, a11y).
The overlay, typography, and effects layers were deliberately built as
the foundations of that hybrid, so this fork stays open without being
committed to. If/when it's serious, it gets its own comparison-doc
treatment first (the re-namespace plan's format: comparisons, verdict,
phased ci-gated migration).

## House rules (policy, carried forward)

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
5. **Both-servers rule** (item 8's lesson): driver route changes land in
   the GTK4 embedded server AND backend/aether_ui_test_server.c. There are
   exactly TWO servers again (macOS gave up its private one, 2026-07-14),
   and the shared one now backs both win32 and macOS — so a route added
   there lands on two backends at once, and a route added ONLY to GTK4 is
   a spec that is red on two platforms for no reason. That is precisely
   how split/overlay/canvas/text_extent stayed red on both.
6. **Geometry specs pin the window** (item 7's lesson): GTK4 on a cold
   Xvfb can map windows at natural size — /window/resize first, then
   assert.
