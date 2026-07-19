# Backdrop blur / materials (frosted scrim)

A modal overlay's scrim can be given a **material** — the visual treatment of
the layer between the dimmed app and the floating card. The honest truth is
that a real *backdrop blur* (frosting what's behind an in-window layer) is only
natively available on one of our three backends, so this feature ships as
"real where the platform allows it, an honest degrade elsewhere, and a driver
signal that says which."

## Why it isn't uniform

- **macOS** — `NSVisualEffectView` is a first-class frosted material that
  samples and blurs what's behind it. Real backdrop blur, for free.
- **win32** — acrylic (`SetWindowCompositionAttribute` /
  `ACCENT_ENABLE_ACRYLICBLURBEHIND`) and `DwmEnableBlurBehind` blur only
  **top-level** windows. Our scrim is a CHILD HWND inside the app window, so
  neither applies to it. There is no native API to blur what's behind an
  in-window child. → degrade.
- **GTK4** — no `backdrop-filter` equivalent; CSS can dim/tint a layer but not
  sample-and-blur what's under it. → degrade.

## API

A setter on a modal overlay handle (mirrors `transition_overlay`):

```
h = overlay_modal(win, card, "center", 0, 0)
overlay_material(h, "blur")     // ask for a frosted backdrop
```

Materials:
- `"dim"` — the default scrim (translucent black). What overlays already do.
- `"blur"` — a frosted backdrop. macOS: real `NSVisualEffectView`. win32/GTK4:
  degrades to `"tint"` (see below) — there is no in-window blur there.
- `"tint"` — a stronger, lighter-tinted scrim (a deliberate non-blur material,
  and the degrade target for `"blur"` off-macOS).

## Effective mode (the driver contract)

Because `"blur"` degrades, the driver reports the material the backend
**actually applied**, not what was requested. `/overlays` entries gain
`"material"`:

- macOS: `"blur"` when blur was requested (real), else `"dim"`/`"tint"`.
- win32/GTK4: `"tint"` when blur/tint requested (blur→tint degrade), else
  `"dim"`.

So a spec asserts `material == "blur"` on macOS and `material == "tint"` on the
others for the same `overlay_material(h, "blur")` call — the degrade is visible
and tested, nobody over-claims a frost that isn't there.

## Backend notes

- **macOS**: swap the scrim's plain layer-backed view for an
  `NSVisualEffectView` (`.hudWindow`/`.underWindowBackground` material,
  `behindWindow` blending) when material is blur; keep click-eating.
- **win32**: `"blur"`/`"tint"` raise the scrim's layered alpha and shift its
  tint lighter (a heavier frosted-looking dim) — honest, not a real blur.
- **GTK4**: a `.aui-overlay-scrim-tint` CSS class (lighter, higher-blur-looking
  gradient tint) — again a tint, not a backdrop-filter.
