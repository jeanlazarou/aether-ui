# CVG → Aether UI port

Port of **CVG (Cosyne Vector Graphics)** from TypeScript
(`~/scm/tsyne/tsyne/cosyne/src/cvg/`) to Aether. The driving inventory and
port plan live in the source repo:
`~/scm/tsyne/tsyne/cosyne/src/cvg/PORT_INVENTORY.md`.

These are **pure-Aether** modules (compile to C, no GTK/AppKit/Win32
coupling) — the Tier A layer of the port. They build and run headless and
are wired into `ci.sh` as **Phase 0** (runs even with no display).

## Status

| Module | Source (TS) | Aether | Test | State |
|--------|-------------|--------|------|-------|
| transform | `transform.ts` (346 LoC) | `transform.ae` | `test_transform.ae` (30 asserts) | ✅ matrix algebra + factories + projective. `parseTransform` (string→matrix) **not yet** — needs a hand-rolled tokenizer (no regex in Aether). |

Next per the inventory's Tier A order: `types`, `grammar-types` (easing),
`normalizer` (path data → absolute M/L/C/Z), `bbox`, then `parser`.

## Running a test by hand

```sh
aetherc cvg/test_transform.ae /tmp/t.c && gcc /tmp/t.c $(ae cflags) -o /tmp/t && /tmp/t
```

Or run the whole Phase 0 gate via `./ci.sh` (it's the first phase).

## Aether idioms this port leans on

Found empirically against `aetherc v0.181.0`; not all are in the language
reference. Capturing them here so the next module doesn't rediscover them.

- **No classes.** TS classes (`AffineMatrix`) → a `struct` plus free
  functions (`affine_mul(a, b)`), prefixed by the type (`affine_*`,
  `proj_*`).
- **Structs are heap pointer-structs across function boundaries.** A
  by-value `-> Struct {` return trips the parser. Allocate with `malloc(N)
  as *T` and thread `*T`. Sizes: count fields × 8 (every `float` is a
  C `double`; `48` for affine's 6, `64` for projective's 8).
- **No float tuple returns.** `return x, y` lowers to `int` and emits
  broken C. Return a small struct instead — `apply()` returns `*Pt`.
- **Module surface needs an `exports (...)` block**; otherwise `import`
  surfaces nothing and the parser derails at the import site.
- **`import` resolves sibling `.ae` files** relative to the compiled
  source's directory (`import transform` next to `test_transform.ae`).
- **`std.math` qualified names drop the `math_` prefix**: the raw extern
  is `math_cos`, but you call `math.cos`. Likewise `math.abs_float`,
  `math.sqrt`, `math.tan`. Constants are zero-arg function-calls:
  `math.pi()`, `math.tau()`, `math.deg_to_rad()`, `math.rad_to_deg()`.
  (Landed in CHANGELOG `[current]` as part of the CVG-port batch — same
  PR added `std.floatarr`, `bytes.copy_from_bytes`, `os.now_monotonic_ms`.)
- **No `sizeof`** — still hardcode struct sizes (`malloc(48)` for affine).
- **`std.floatarr` is the typed float array** (mirror of `std.intarr`).
  Go-style wrappers: `a, err = floatarr.new(n)`, `v, _ = floatarr.get(a, i)`;
  `floatarr.set(a, i, v)` returns just an error string. `_unchecked`
  variants are tuple-free for hot loops.
