# aether-ui docs

Two audiences, two directories.

## `guide/` — using aether-ui

End-user DX: how to write apps against the widget DSL (`ui`) and the
vector layer (`vg`).

- [**dsl-with-scope.md**](guide/dsl-with-scope.md) — the builder-block
  style the whole toolkit is written in: nested blocks that read
  declaratively but are executed code, with an implicit receiver.
- [**typography.md**](guide/typography.md) — drawing, measuring, and
  fitting text in `vg`: baselines, `text_extent`, centring, ellipsize.

## `design/` — how it's built (and where it's going)

Internal architecture notes, plans, and cross-platform handoffs. Not
needed to *use* aether-ui; read these to change it.

- [**retained-compositor.md**](design/retained-compositor.md) — the
  rendering north star (aspirational; the current backend is
  immediate-mode).
- [**aevg-live-regions-plan.md**](design/aevg-live-regions-plan.md) —
  glitch-free live content (video/games) composited inside one AeVG scene.
- [**aevg-resize-native-followup.md**](design/aevg-resize-native-followup.md)
  — the `vg{}`-scene resize contract for the AppKit / Win32 backends
  (GTK reference to mirror).
- [**getting-windows-and-macos-green-via-remote-agents.md**](design/getting-windows-and-macos-green-via-remote-agents.md)
  — proving the Win32 + AppKit backends compile and run on real hardware
  via remote build agents.
