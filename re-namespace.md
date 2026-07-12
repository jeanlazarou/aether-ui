# Re-namespace plan: AeVG to the root, widgets to a subtree

**Status: DONE.** 2026-07-12.
- **P1** (e85eafb): `aevg/` → `vg/` tree; 41/41 units + full ci green.
- **P2** (4829185): `vg/apps` → root `apps/`.
- **P3** (d002b06): widget DSL `aether_ui.ae` → `ui/module.ae` (`import ui`);
  the 213 `aether_ui_*` C-ABI externs + `aetherui` aeb module unchanged.
- **fight_flash_fraud** (that repo's 76ab9d6): `import aether_ui` → `import ui`;
  unit 4/4, UI spec 2/2.
- **P4** (this commit): docs/memory sweep.
Full ci.sh green after every phase.

## The question

`aevg/` (the SVG-faithful vector grammar, by way of Tsyne) arrived second,
so it lives in a subdirectory while the older native-widget DSL
(`aether_ui.ae`) squats at the repo root. If AeVG is the crown jewels —
the thing no other GTK-era toolkit has: a 1:1 SVG grammar, declarative
scenes, live regions, driver-testable, ~86% pixel-parity with librsvg —
should the namespaces say so?

Short answer: **yes, invert the prestige, but don't nest either tech
inside the other.** Make `vg` the root-level *tree* (it has ~30 modules
and deserves internal structure) and `ui` a root-level *module* (the
widget DSL is one file and should stay one import). That is SwiftUI's
answer, not Swing's — see the comparisons.

## What we have today (and what's wrong with it)

```
aether_ui.ae          ← widget DSL at the root (the incumbent)
backend/*.c           ← shared C backends (GTK4 / AppKit / Win32)
aevg/                 ← 30+ flat modules + 40+ tests + apps/
  vg.ae vg_live.ae live_region.ae
  grammar_{context,element,shapes,style,css,defs,events,factories,
           rendering,reactive,bind,animations,utils}.ae
  parser.ae loader.ae normalizer.ae transpiler.ae
  transform.ae bbox.ae path_builder.ae easing.ae
  rasterize.ae blur.ae render_as_raster.ae refresh.ae
  aevg_backend.ae aevg_gtk_backend.ae backend_dispatch.ae
  apps/               ← the showcase apps (grand_perspective, boing, …)
examples/             ← widget-DSL examples
tests/                ← Aeocha driver specs
```

Two real problems beyond prestige:

1. **Flat-namespace squatting.** With `lib("${root}/aevg")`, every AeVG
   internal is importable by a bare generic name: `parser`, `loader`,
   `transform`, `easing`, `blur`, `bbox`, `normalizer`, `refresh`. Any
   consumer app that wants its own `parser.ae` collides with ours. The
   `grammar_` prefix on 13 modules is a hand-rolled namespace — the exact
   thing directory-dotted imports exist to replace.
2. **The names don't teach the architecture.** A newcomer reading
   `import vg_live (vg, canvas_region)` next to `import grammar_events`
   can't see the layering (grammar core < scene/DSL < live surface). A
   `vg.grammar.*` / `vg` / `vg.live` tree would.

Import-site counts (whole repo, for effort sizing): `aether_ui` 54,
`vg` 42, `grammar_context` 42, `transform` 37, `grammar_element` 22,
`aevg_backend` 20, `vg_live` 17, `parser` 14, remainder ≤ 11 each.
Nothing outside `aevg/` imports the vector modules today — the blast
radius of renaming AeVG internals is contained to `aevg/` itself.

## The three comparisons

### Swing — the cautionary tale (this is the inversion we're drifting into)

AWT shipped first (1995, heavyweight native widgets). Swing shipped second
(1997) — lightweight, *drawn*, strictly more capable — and was punished
for its birth order with the `javax.swing` extension ghetto while AWT kept
`java.awt` forever. Worse, Swing never escaped AWT: `Graphics2D`, `Point`,
`Rectangle`, the event pump — the "old" tech stayed load-bearing inside
the "new" one, and the namespaces lied about which was the product.
Nobody ever fixed it; after a few years of ecosystem growth nobody could.

**Lesson:** root ownership defaults to the incumbent and calcifies. If the
namespace should reflect what the project *is*, invert it while the repo
is young and single-author — i.e. now. aether-ui is pre-1.0 with every
consumer in-tree; this is the last cheap moment.

### Flutter — the layered ideal

`dart:ui` (engine: `Canvas`, `Scene`, compositing) at the bottom, then one
package with strictly layered libraries: `painting` → `rendering` →
`widgets` → `material`/`cupertino`. The *drawing/scene layer is the
foundation* and the widget sets are literally built from it; apps import
one umbrella (`material.dart`) and never see the layers unless they want
to.

**Lesson (and an honest caveat):** Flutter earns the vector-layer-at-the-
base namespace because its widgets really are drawn by it. Ours are not —
aether-ui's widgets are native GTK/AppKit/Win32, and AeVG rides inside a
canvas widget. So we cannot claim Flutter's layering *today*. But the
namespace can reflect the architecture's centre of gravity and its
direction of travel: the scene layer is where the invention is, and a
future drawn-widget skin (`vg`-rendered controls) would slot under the
`vg` tree without any further renaming.

### SwiftUI — the shape to copy

Apple did not nest UIKit inside SwiftUI, nor SwiftUI inside UIKit. Two
top-level frameworks; the *new* one got the flagship name; interop is
explicit adapters (`UIViewRepresentable`, `NSHostingView`). And note
where vector drawing lives: `Canvas`, `Shape`, `Path` are first-class
citizens *inside* SwiftUI, not an annex.

**Lesson:** peers-with-adapters, prestige to the new name. Our adapter
point already exists and works: the `vg { … }` scope hosted inside a
`ui` window (an `NSHostingView` in reverse). Neither tech should be
namespaced inside the other — Swing shows how that curdles.

## Verdict

AeVG is the crown jewels — it's the differentiator, the largest body of
code, the deepest test suite, and the thing the showcase apps are built
on. The plan:

- **`vg` becomes the root-level tree** and keeps the name users already
  type at every call site (`vg.rect`, `vg.fill`) — "AeVG" stays the
  brand/marketing name, `vg` the code name.
- **The widget DSL becomes `ui`** — a root-level *module* (one file, one
  import, `ui.` prefix), positioned as the native-chrome peer, not the
  headline.
- **Neither nests inside the other** (SwiftUI's shape). The subtree
  structure goes where the mass is: under `vg`.

## Target layout

```
ui/
  module.ae            ← aether_ui.ae   (import ui → ui.window, ui.btn, …)
vg/
  module.ae            ← vg.ae          (import vg → vg.rect — UNCHANGED call sites)
  live.ae              ← vg_live.ae     (import vg.live → live.canvas_region…)
  region.ae            ← live_region.ae
  grammar/             ← the 13 grammar_*.ae, prefix dropped
    context.ae element.ae shapes.ae style.ae css.ae defs.ae events.ae
    factories.ae rendering.ae reactive.ae bind.ae animations.ae utils.ae
  svg/                 ← the SVG pipeline
    parser.ae loader.ae normalizer.ae transpiler.ae
  geom/
    transform.ae bbox.ae path_builder.ae easing.ae
  raster/
    rasterize.ae blur.ae render_as_raster.ae refresh.ae
  backend/
    dispatch.ae        ← backend_dispatch.ae
    gtk.ae             ← aevg_gtk_backend.ae
    record.ae          ← aevg_backend.ae (the Phase-0 recording stub)
  test/                ← the 40+ test_*.ae (paths in ci.sh AEVG_TESTS update)
apps/                  ← aevg/apps promoted to the root (they are the
                         showcase, not an appendix of the vector lib)
examples/              ← unchanged (widget-DSL examples)
backend/               ← unchanged (C backends are files, not modules)
tests/                 ← unchanged (Aeocha driver specs)
```

Import table (consumer-visible):

| Today                                   | After                          | Call prefix    |
|-----------------------------------------|--------------------------------|----------------|
| `import aether_ui`                      | `import ui`                    | `ui.` (was `aether_ui.`) |
| `import vg`                             | `import vg`                    | `vg.` — **unchanged** |
| `import vg_live (vg, canvas_region)`    | `import vg.live (vg, canvas_region)` | selective, unchanged |
| `import live_region`                    | `import vg.region`             | `region.`      |
| `import grammar_shapes`                 | `import vg.grammar.shapes`     | `shapes.`      |
| `import parser` / `loader` / …          | `import vg.svg.parser` / …     | `parser.` / …  |
| `import transform` / `bbox` / …         | `import vg.geom.transform` / … | `transform.` / … |
| `import backend_dispatch`               | `import vg.backend.dispatch`   | `dispatch.`    |
| `lib("${root}/aevg")` in .build.ae      | `lib("${root}")`               | one lib root   |

Mechanics, verified by probe on ae 0.368 (2026-07-11): dotted imports for
user libs resolve `<lib>/a/b/c.ae` (and `<lib>/a/module.ae` for
`import a`), the qualified call prefix is the **last** segment, and
exported structs cross dotted module boundaries. So `vg/module.ae` keeps
`import vg` + every `vg.rect` call site byte-identical — the highest-churn
surface (42 imports, hundreds of call sites) moves without an edit.

## Alternatives considered

- **B — one umbrella (`aui.vg.*`, `aui.widgets.*`), Flutter-style.**
  Cleanest hygiene, but every single import in every consumer changes,
  `vg.rect` call sites included, for no expressive gain until there's a
  second package to disambiguate against. Rejected: maximum churn,
  minimum payoff.
- **C — hygiene only (move internals under `vg.*`, leave `aether_ui` at
  root).** Fixes squatting, dodges the question. The Swing outcome with
  better manners. Rejected as the end state; it is, however, exactly
  Phase 1 below — so we get its value on the way.
- **Nesting widgets under `vg.widgets`.** Namespace fiction — the widgets
  don't use vg — and Swing-in-reverse. Rejected.

## Migration plan

Each phase lands as its own baby commit(s) with full ci.sh green
(Phase 0 units + fan-out build + smoke + 4 driver-spec phases). Phases
are independently shippable; stop anywhere and the repo is coherent.

**P1 — vg tree (internal, ~65 files, the big one).**
Move/rename inside `aevg/` → `vg/` per the table; drop the `grammar_`
prefixes; sed the internal imports and qualified prefixes
(`grammar_element.` → `element.`, `backend_dispatch.` → `dispatch.`, …).
Watch shadowing when prefixes shorten: locals named `context`, `parser`,
`transform` exist — sed by qualified-call pattern (`grammar_context.` →
`context.`), never by bare word. Update `aevg/test/` module paths and
ci.sh's `AEVG_TESTS` list + compile line. `.build.ae` nodes:
`lib("${root}/aevg")` → `lib("${root}")`. Consumer-visible change for the
apps only (`vg_live` → `vg.live`, `live_region` → `vg.region`).
Estimated: half a day, mechanical, gated by the 41 unit tests + fan-out.

**P2 — apps to the root.**
`aevg/apps/*` → `apps/*` (grand_perspective keeps its gp_*.ae split and
its GPL-island header; the provenance note references move with it).
Update the fan-out `.all.ae` scan, ci.sh Phase 6 binary path, and the
`tests/grand_perspective` specs' launch docs. Trivial after P1.

**P3 — widgets to `ui` (consumer-visible, ~36 files).**
`aether_ui.ae` → `ui/module.ae`. Repo-wide: `import aether_ui` →
`import ui`; qualified `aether_ui.` → `ui.`; extern names
(`aether_ui_*_impl`, the C ABI) **do not change** — the C backends and
the `aetherui` aeb builder module keep their names (build-side identity,
not a language namespace). Flag-day rename; no deprecation shim (Aether
has no re-export mechanism, every consumer is in-tree, and a wrapper
module would be 100+ stub functions of drag).

**P4 — docs, memory, siblings.**
README/LLM.md/TODO diagrams and snippets; the `.aeb` builder docs;
CLAUDE-memory notes; re-clone/pull on GhostBSD (.204) and winbaz before
their next ci run — P1–P3 are source-only, so those boxes just rebuild.

**Explicit non-goals:** no C-file renames (`backend/aether_ui_gtk4.c` and
the `aether_ui_*` ABI stay), no behaviour changes, no aeb changes beyond
`lib()` paths, no new deprecation machinery.

## Risks and open questions

- **Last-segment prefix collisions.** `import vg.svg.parser` and a
  hypothetical `import foo.parser` in one file would both want `parser.`.
  Within our tree the last segments are unique; the convention to adopt:
  *last segments must be unique within any one importing file* —
  acceptable for a pre-1.0 toolkit, same constraint Go packages live with.
- **Compile-cache staleness during the migration.** The ae cache doesn't
  notice imported-module changes; expect one `rm -rf ~/.aether/cache`
  per phase (documented wart, hit repeatedly this week).
- **`import vg` shadowing the `vg` verb-scope symbol.** `vg_live` exports
  a fn named `vg` (the `vg { … }` scope opener) while `import vg` names
  the module — this coexists today and P1 keeps both spellings; verify
  early in P1 that `vg/module.ae` + `vg.live`'s exported `vg` fn still
  coexist (probe before the bulk sed).
- **Windows/macOS**: source-only change; the win32/macos backends compile
  the same C. The Windows `ae build` module-resolution quirk (MINGW) predates
  this and is unaffected, but P1 should be smoke-checked on winbaz anyway.

## Why now

Every consumer of both DSLs lives in this repo. The GhostBSD and Windows
checkouts are `git pull`-and-rebuild. Aeocha specs pin behaviour across
the whole surface. There will never be less inertia than today — the
Swing lesson is that this window closes silently.
