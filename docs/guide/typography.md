# Text in vg — baselines, metrics, and fitting

How to place, measure, and fit text in an AeVG (`vg`) scene. If you draw a
label and it lands where you expect, you can skip this; come back when you
need to *centre* text in a row, *fit* it to a column, or you're wondering
where a baseline sits.

## Drawing text

```aether
vg(view_box(0, 0, 400, 300), 400, 300) {
    text(10, 40, "hello")                 // engine-default size
    text_sized(10, 80, 24.0, "bigger")    // explicit font size (viewBox units)
}
```

`text_sized(x, y, size, content)` draws `content` at font `size`, with
`(x, y)` as the **text baseline origin** — the same convention as SVG's
`<text x= y=>`. `text(x, y, content)` is `text_sized` with size 0 (the
engine default). Set a `fill` in the trailing block or the label defaults
to black:

```aether
text_sized(10, 40, 16.0, "titled") { fill("#3366cc") }
```

### What "baseline" means (and the one gotcha)

`y` is the baseline: the line the letters *sit on*. Descenders — the tails
of `g`, `y`, `p`, `q` — dip **below** `y`; ascenders and capitals rise
**above** it. So to place a 16px label whose top edge is at `box_top`, you
draw at `y = box_top + ascent` (see `text_extent` below), **not** at
`box_top`.

> Historical note: before 2026-07, vg subtracted a `1.07 × size` "baseline
> correction" that pushed every glyph ~1em too high, and every call site
> hand-compensated with a `+17`. That's gone — `y` is now honestly the
> baseline. If you find old code adding a magic constant to a text `y`,
> it's stale; delete it and seat the baseline from `ascent`.

## Measuring text

Four measurement functions, all taking a font `size` in viewBox units.
They measure the exact font the scene renders with, so measurement agrees
with drawing.

```aether
w = vg.text_width(16.0, "hello")          // pen advance width (px)

asc  = vg.font_ascent(16.0)               // top → baseline
desc = vg.font_descent(16.0)              // baseline → bottom (descenders)
h    = vg.font_height(16.0)               // recommended line height

// All three at once, plus width:
w, height, ascent = vg.text_extent(16.0, "hello")
```

`text_extent(size, s) -> (width, height, ascent)` — note the tuple is
`(width, line-height, ascent)`. `width` is `s`'s pen advance; `height` is
the font's line height (use it to stack lines); `ascent` seats the
baseline.

## Two things you'll actually reach for

### Vertically centre text in a row

The idiom that replaced every hand-tuned offset. To centre `size`px text
in a row of height `row_h`, the baseline offset from the row's top is:

```aether
row_baseline(size: float, row_h: float) -> float {
    asc = vg.font_ascent(size)
    desc = vg.font_descent(size)
    return (row_h - (asc + desc)) / 2.0 + asc
}

// then, for a row whose top is at `ry`:
vg.text_sized(root, x, ry + row_baseline(13.0, 25.0), 13.0, label)
```

This centres the glyph box (ascent+descent) in the row and returns the
baseline. It's how `grand_perspective`'s list and legend rows sit level
with their colour chips at any size.

### Fit text to a column width

`ellipsize(size, s, max_w)` returns `s` if it fits `max_w` pixels, else a
shortened `"prefix…"` that does. Use it instead of clipping by character
count — a character count can't know that `iiii` and `MMMM` have very
different widths.

```aether
name = vg.ellipsize(13.0, entry.name, 118.0)   // fit the 118px name column
vg.text_sized(root, 26.0, base, 13.0, name)
```

## Driving text metrics from a test (AetherUIDriver)

A driver-armed app exposes `GET /text_extent?size=&s=`, so a test can
assert metrics over HTTP without a bespoke probe:

```
$ curl 'http://127.0.0.1:9222/text_extent?size=16&s=hello'
{"width":37.000,"ascent":18.000,"descent":5.000,"height":22.000}
```

The `uidriver` test library wraps it: `uidriver.text_width(size, s)` and
`uidriver.font_ascent(size)`. See `tests/text_metrics/spec_text_metrics.ae`
for an Aeocha spec that asserts the metrics behave (monotonic in length,
scale with size, ascent below line height).

## Platform support

Real metrics are cairo-backed on the **GTK4** backend. **Win32** and
**macOS** currently return **0** from all metric calls (documented stubs;
real GDI / CoreText metrics land when those backends are next worked on a
real box). The degrade is safe: `ellipsize` treats everything as fitting
(no truncation), and `row_baseline` returns `row_h / 2` — text still
draws, it just isn't measured. Code that calls the metrics compiles and
runs everywhere.

## Not yet (open follow-ups)

- **Multi-line wrap** — no `text_wrapped` yet; wrap by measuring words
  with `text_width` and emitting one `text_sized` per line at
  `y + n*font_height`.
- **`text-anchor: middle | end`** in the SVG `<text>` path — leading
  (left) only for now.
- **Font family / weight / style** — size-only metrics; the renderer uses
  cairo's default sans.
