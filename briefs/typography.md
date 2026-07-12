# Brief: the typography layer (roadmap item 2)

**Status: READY FOR EXECUTION.** 2026-07-12. Self-contained hand-off —
everything needed is in this file or at the cited file:line anchors.
Written for an autonomous session; escalation triggers are explicit.

## Mission

Give vg real text metrics and fix the baseline bug, then delete every
hand-tuned compensation that bug forced. Concretely:

1. Correct baseline semantics in the one text render path.
2. New API: `vg.text_extent(size, s) -> (w, h, baseline)` (measurement),
   plus ellipsize-to-width. (Multi-line wrap + alignment = stretch goals.)
3. Sweep the compensation call sites (inventory below).
4. Prove it: SVG conformance ≥ baseline, 41 vg units, full ci.sh, and
   the visual spot-checks listed in Phase E.

## Ground truth (verified 2026-07-12 — start from here, not from digging)

- **There is exactly one text render path.** The CPU rasterizer
  (`vg/raster/rasterize.ae`) has **no text support at all**. All text goes:
  `vg.text/text_sized` → shape factory (`vg/grammar/shapes.ae`) → gtk
  backend (`vg/backend/gtk.ae` `canvas_text`, ~line 447) →
  `ui.canvas_fill_text` (`ui/module.ae:1005`) → C
  `aether_ui_canvas_fill_text_impl` → `CANVAS_FILL_TEXT` replay
  (`backend/aether_ui_gtk4.c`, ~line 1722): `cairo_set_font_size` +
  `cairo_move_to(x, y)` + `cairo_show_text`.
- **Cairo's text origin IS the baseline.** `cairo_show_text` draws with
  the current point as the baseline-left origin — same convention as
  SVG's `<text y=…>`.
- **The offset:** `vg/grammar/shapes.ae:949`:
  `baseline_offset = text_size * 1.07`, subtracted from the mapped y at
  lines ~980 and ~1067 (`my - baseline_offset`). For 16px text that's
  ~17.1px — the "renderer draws ~17px above the requested baseline"
  behavior every consumer compensates for.
- **Working hypothesis (verify in Phase A, do not assume):** this is a
  double correction — SVG y is already the baseline and cairo already
  consumes a baseline origin, so subtracting ~1.07em shifts all text up
  by roughly one em. If true, the fix is deleting the offset (both
  subtraction sites), and W3C *text* samples may currently be among the
  conformance failures — the fix could *raise* the score.
- **The comment at `vg/backend/gtk.ae` line ~445** ("the shape factory
  already applied baseline correction") documents the current wrong
  contract; update it with the new one.
- **No measurement API exists anywhere** (`cairo_text_extents` appears
  nowhere in `backend/aether_ui_gtk4.c`). Labels clip by *character
  count* (`clip_name`/`clip_list_name` in
  `apps/grand_perspective/gp_model.ae`), not by width.

## Compensation call-site inventory (the sweep list)

All marked with comments mentioning "17" or "baseline" — re-grep before
sweeping in case more landed since:
`grep -rn "17px\|~17\|baseline" apps/ vg/svg/transpiler.ae --include="*.ae"`

- `apps/grand_perspective/gp_render.ae:168` — treemap tile labels:
  `r.y + 44.0` chosen so 16px text clears the tile top. With correct
  baselines this becomes `r.y + <ascent+pad>` via text_extent.
- `apps/grand_perspective/gp_render.ae:219` area — list-pane header block
  (`hd` at y=30, `hs` at y=48, `inf` at y=62) — positioned low to dodge
  the clip; recompute from real metrics.
- `apps/grand_perspective/gp_render.ae:322` area — legend + list ROW
  text at `ry + 31.0` (a +17 carried into the row math); with the fix
  these become `ry + <row-centering from metrics>`.
- `apps/grand_perspective/gp_render.ae` ".." row at `LIST_TOP() + 11.0`
  (was moved INTO its click zone to compensate — see gp memory; re-derive).
- `vg/svg/transpiler.ae` emits no baseline compensation (checked) but
  regenerated apps (trajans_column geometry) embed *positions* computed
  under the old behavior — see the trajans_column note in Phase E.

**Sweep rule:** never sed these blindly. Each site gets re-derived from
`text_extent` (or plain baseline semantics) and visually spot-checked in
Phase E. The comments make them findable; the grep above is the census.

## Deliverables

### D1 — corrected baseline semantics
Delete/replace the `baseline_offset` math in `vg/grammar/shapes.ae` (both
subtraction sites) so the y passed to the backend is the SVG baseline,
which cairo consumes natively. Update the contract comment in
`vg/backend/gtk.ae` (~445).

### D2 — measurement API
- New C externs in `backend/aether_ui_gtk4.c` (measurement must work
  headless — use a static 1×1 scratch `cairo_t`, created on first use):
  - `aether_ui_text_measure(size, text) -> width` (double)
  - `aether_ui_font_metrics(size) -> ascent, descent, height` (however
    tuples are best expressed — three getters after a measure call is
    fine; keep the ABI dumb)
- Win32/AppKit: documented no-op stubs returning zeros (house pattern —
  `toggle_group` precedent), so the fan-out still links everywhere.
- vg surface: `vg.text_extent(size: float, s: string) -> (w, h, baseline)`
  exported from `vg/module.ae`; `vg.ellipsize(size, s, max_w) -> string`
  (binary-search or greedy on measure).
- Unit test `vg/test/test_text_metrics.ae` (add to ci.sh `AEVG_TESTS`):
  monotonicity (longer string ⇒ wider), size scaling (bigger size ⇒
  bigger extent), ellipsize respects max_w, empty-string = 0 width.
  Do NOT assert absolute pixel values — fonts differ across boxes.

### D3 — the sweep
Re-derive each inventory site with metrics; delete the compensation
comments as each dies. `clip_name`/`clip_list_name` become
width-ellipsized via `vg.ellipsize` (keep the fns, change the internals —
call sites don't churn).

### D4 — stretch (only if A–E are green with time left)
Multi-line wrap (`vg.text_wrapped(x, y, w, size, s)` drawing N baselines)
and `text-anchor` middle/end support in the SVG path. Separate commit(s);
skip freely.

## Execution phases — each ends with a commit; gates are hard

**Phase A — characterize before touching.**
1. `rm -rf ~/.aether/cache` (ALWAYS after touching imported modules —
   the cache does not notice module edits and will gaslight you).
2. Record the conformance baseline:
   `cd vg/test && python3 svg-compare-aevg.py 2>&1 | tail -20`
   (env `AEVG_SIZE=400` is the harness norm; the script's docstring may
   still cite old `aevg/` paths — paths INSIDE the script may need a
   one-line fix post-re-namespace; that's in scope, keep it minimal.)
   Save the summary line + the CSV it writes. Baseline ≈ 86% pixel-good
   over ~208 W3C samples. Note which FAILING samples contain `<text`.
3. Write a 20-line probe app (scratchpad, not committed) drawing one
   16px string at y=100 next to a `vg.line` at y=100; screenshot via the
   driver; confirm the glyphs sit ~17px above the line. This is the
   before-photo and your regression oracle for D1.

**Phase B — D1, the baseline fix.**
Delete the offset; rebuild (`aeb .all.ae` — cache-clear first); re-run
the probe: glyph baselines now ON the line. Re-run conformance: score
must be ≥ baseline (expect flat or better; text-bearing samples may
flip to passing). 41 units:
`ROOT=$PWD; for t in …` — or simply run `./ci.sh` Phase 0 via the full
pipeline. **Gate: conformance ≥ baseline AND ci.sh Phase 0 green.**
Commit. NOTE: at this commit, gp/apps text will sit ~17px LOWER than
before (their compensations now overshoot) — that's expected mid-flight;
phases C/D restore them. Do not "fix" it in B.

**Phase C — D2, metrics API.** New externs + vg surface + unit test +
stubs. Gate: new test green in ci.sh Phase 0; fan-out builds. Commit.

**Phase D — D3, the sweep.** Re-derive the inventory sites. Gate: full
`./ci.sh` green (all 5 gp specs especially — they assert click zones and
status text that move with row geometry; if a spec asserts a now-shifted
coordinate, fix the APP geometry to be metrics-derived, and only touch
spec coordinates when the ROW LAYOUT ITSELF legitimately changed —
document any such change in the commit message). Commit.

**Phase E — visual verification (screenshots, not vibes).**
Screenshot via driver (`GET /screenshot`) and EYEBALL each:
1. grand_perspective at default size (list header unclipped, row text
   beside chips, legend aligned, tile labels inside tiles).
2. grand_perspective after `POST /window/resize?w=1716&h=830` (scaled).
3. `apps/analog_clock_png` or `svg_render_png` over 2–3 text-bearing W3C
   samples (compare against librsvg PNGs the harness produces).
4. trajans_column (transpiled positions predate the fix — if its text
   looks wrong, note it in the commit and regenerate via the transpiler
   rather than hand-editing; if regeneration is heavy, file it as a
   follow-up note in roadmap.md instead).
Attach findings to the final commit message. Update the gp memory-file
claim about the ~17 quirk if you have memory access; otherwise note it.

## Acceptance checklist (all machine-checkable except E)

- [ ] `vg/grammar/shapes.ae` has no `baseline_offset` compensation.
- [ ] `grep -rn "~17\|17px" apps/ vg/ ui/ --include="*.ae"` → no hits
      (except historical mentions in briefs/roadmap).
- [ ] `vg.text_extent` + `vg.ellipsize` exported, unit-tested, in
      ci.sh `AEVG_TESTS`.
- [ ] Conformance ≥ the Phase-A baseline number (attach both numbers).
- [ ] Full `./ci.sh` green (Phase 0 units, fan-out, smoke, 9+5+4 example
      specs, 5 gp specs).
- [ ] fight_flash_fraud still builds+passes (its app uses ui text but no
      vg text — expect no change; verify:
      `cd ~/scm/fight_flash_fraud && AETHER_UI_DIR=~/scm/aether-ui make test-unit`
      and the UI spec per its scripts with AEOCHA_DIR=~/scm/aeocha).
- [ ] Phase E screenshots reviewed and described in the final commit.

## Environmental traps (every one of these cost a real debugging session)

- **Compiler cache:** `rm -rf ~/.aether/cache` after ANY edit to an
  imported module. Stale caches produce impossible E0301s and silently
  run old code.
- **Driver apps:** end them with `curl -X POST :9222/shutdown` — NEVER
  by killing the xvfb-run wrapper (the app survives, holds port 9222,
  and the next test interrogates the wrong app). Port is always 9222;
  `AETHER_UI_TEST_PORT` must be SET to arm the server (value ignored).
- **One driver app at a time.** Check `curl -sf :9222/widgets || echo
  free` before launching. Kill strays by binary path, and beware
  `pgrep -f <pattern>` matching your own shell's command line.
- **Xvfb:** `xvfb-run -a -s "-screen 0 3200x2000x24"` + `GSK_RENDERER=
  cairo` (NGL on llvmpipe leaks GBs). The big screen keeps the parked
  pointer out of the window (GTK synthesizes motion events at it).
- **Screenshots:** `GET /screenshot` 500s transiently — retry once.
- **Aeocha:** specs need `~/scm/aeocha` (AEOCHA_DIR); run specs via
  `tests/run_spec.sh` (UI_SPEC=<app>/<spec>), not `ae run` directly.
- **Conformance CSV:** `vg/test/svg-conformance-aevg.csv` is harness
  OUTPUT — regenerating it is fine; hand-editing it to make numbers
  pass is the one unforgivable move.
- **Multi-line strings/regex in .ae:** no leading-`+` continuation
  lines; `${}` interpolation can't contain string literals — use temp
  vars.

## Out of scope — do not do these even if tempting

- No renaming of existing text APIs (`text_sized` stays).
- No Windows/macOS metric IMPLEMENTATIONS (stubs only; those backends
  get real metrics when we're next on winbaz / the Mac mini).
- No CPU-rasterizer text support (rasterize.ae stays text-free).
- No font-family/weight/style work — size-only metrics this pass.
- No touching the GPL-island provenance headers in apps/grand_perspective.
- No aeocha/aether (sibling repo) changes. If blocked by a suspected
  compiler bug: minimal probe in the scratchpad, document it, STOP and
  report rather than working around it in ugly ways.

## Escalation triggers — stop and report instead of pushing through

1. Conformance drops >0.5% after D1 and the delta isn't obviously
   text-sample noise → the hypothesis is wrong; report findings.
2. The offset turns out to be load-bearing for NON-text layout (nothing
   suggests this, but if deleting it moves non-text pixels, stop).
3. Any memory-corruption-shaped symptom (garbage strings, segfaults) —
   this codebase has closure/string-lifetime history; don't guess.
4. ci.sh gp specs fail on coordinates by exactly a text-height — that's
   the expected Phase-B intermediate state leaking into D; finish the
   sweep site rather than editing the spec.

## Working agreements

Baby commits per phase with the gate results in the message; push to
`main` (house norm). Follow the four house rules in roadmap.md
("Driver-first widgets", "sommelier gate" — N/A here, no compositor
surface — "idle costs zero", "headless parity"). When done, update
roadmap.md item 2 to DONE-with-commits (re-namespace.md precedent) and
delete this brief in the same commit.
