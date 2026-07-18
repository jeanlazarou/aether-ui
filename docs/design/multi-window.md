# Multi-window — design

**Status:** design (2026-07-18). Implementation phased below.

Today aether-ui is **single-window by construction**: one `window(){}` surface
opens one OS window, and its `app_run_raw` *owns the event loop* (blocks until
that window closes). ~50 sites across the three backends resolve "the window"
via a single global (`primary_window` on GTK4/macOS, `apps[0]` on win32):
overlays, menus, sheets, shortcuts, the driver's `/window/*` routes, geometry.

Goal: **co-equal top-level windows** — any number, each a real OS window, all
sharing one event loop, with a clean lifecycle (open, close, "last window
closed → app exits") and a driver story that lets specs target a specific
window.

---

## 1. The loop model (the crux)

The single blocking `app_run_raw` is the root constraint. Every backend already
has a native app object that owns N windows — we've just been using one:

| Backend | App object | Native N-window support |
|---|---|---|
| GTK4 | `GtkApplication` | Yes — `gtk_application_window_new(app)` any time the loop runs; app exits when its last window closes (unless held) |
| macOS | `NSApplication` | Yes — `[[NSWindow alloc] …]`; `applicationShouldTerminateAfterLastWindowClosed` |
| win32 | the message loop | Yes — multiple top-level HWNDs pump one `GetMessage` loop; quit when the count hits 0 |

**Decision: keep ONE blocking run, own N windows under it.**
- The FIRST `window(){}` (or `app_start`) still starts + owns the loop — source
  compatibility, zero change for single-window apps.
- Additional windows are created **while the loop runs**, via a non-blocking
  `open_window(...) -> win_handle`. They join the same app object.
- The loop exits when the **last** window closes (each backend's natural rule),
  not when any one does. This is the behavior change: today win32 `WM_CLOSE`
  does `PostQuitMessage(0)` unconditionally; it must instead close that window
  and only quit when the live-window count reaches 0.

Rejected: a thread-per-window model (native UI toolkits are single-UI-thread;
cross-thread window ops are undefined). Rejected: a custom loop multiplexer
(the native app objects already multiplex correctly).

---

## 2. Window registry + handles

A small `Window` registry, 1-based handles, parallel to the widget registry:

```
struct Window { <native window>; title; live; root_handle; }
```

- Handle 1 = the primary window (what `primary_window`/`apps[0]` mean today).
- `open_window(title,w,h) -> handle` registers + creates + presents a window.
- `window_set_body(handle, root)` mounts a root widget.
- `close_window(handle)` closes it (fires an on-close hook; last-close → quit).
- `window_is_open(handle) -> int`.

**Parameterizing the ~50 single-window sites.** Everything that resolves "the
window" (overlays, menus, sheets, geometry, shortcuts) grows an explicit
window-handle parameter, defaulting to the window the anchor widget lives in
(walk the widget up to its top-level) or handle 1. Concretely:
`overlay(win, …)` already takes a `win` arg (0 = main) — extend that to a real
handle; `menu_bar_attach(app, bar)` becomes per-window; sheets attach to the
anchor's window. This is mechanical but broad — Phase 2/3 work.

---

## 3. Widget ↔ window association

Widgets already live in one flat registry. Add a resolve: a widget's window =
its top-level ancestor's Window handle. The driver's `/widgets` JSON gains a
`"window":N` field (0 = not yet mounted / detached). This lets a spec assert
"row X is in window 2" and target clicks unambiguously.

No second registry — the association is derived from the native parent chain at
report time (GTK: walk to `GtkWindow` → handle; win32: `GetAncestor(GA_ROOT)`;
macOS: `[view window]`).

---

## 4. Driver story

The driver assumes one app on one port; that stays (one process, one port).
What changes is window-scoping:

- `GET /windows` → `[{"id":1,"title":"Main","live":true}, …]`.
- Widget JSON carries `"window":N`.
- Existing `/window/resize`, `/window/key`, `/window/pick` gain an optional
  `?win=N` (default 1 = primary), so a spec can drive a specific window.
- `POST /window/{id}/close` — close a window from the driver (lifecycle test).

Headless stays headless: secondary windows realize but don't present (same
`AETHER_UI_HEADLESS` rule as the primary), so specs run without a display and
assert structure/geometry/lifecycle.

---

## 5. Phased implementation

1. **Window registry + open_window/close_window/window_is_open + last-close
   loop rule**, GTK4 first. Primary window becomes handle 1 in the registry.
   `open_window` creates a `GtkApplicationWindow` on the running app. win32:
   `WM_CLOSE` decrements a live count, `PostQuitMessage` only at 0.
2. **Driver window-scoping**: `/windows`, `"window":N` in widget JSON,
   `/window/{id}/close`, `?win=` on the existing window routes. Both servers.
3. **Parameterize the single-window sites**: overlays/menus/sheets/shortcuts
   resolve to the anchor's window. This is the broad-but-mechanical phase.
4. **win32 + macOS parity** for phases 1–3.
5. **Spec + example**: `multiwindow_demo` — a main window with a button that
   opens a second window; the spec asserts `/windows` lists both, widgets carry
   the right `window` id, and closing the second leaves the first live.

Cross-window state already works (the state/binding layer is window-agnostic —
a state cell bound to widgets in two windows updates both). No new work there;
the spec should demonstrate it.

---

## 6. Risks / open questions

- **win32 last-close semantics**: getting the live-count right (a window that
  fails to create, a window closed twice) — guard with the registry `live` flag.
- **macOS `applicationShouldTerminateAfterLastWindowClosed`**: default YES is
  what we want, but headless/park mode must not exit early.
- **Overlay/menu globals**: `primary_window` is used by the overlay host as the
  scrim parent — a secondary window's overlays must parent to IT, not the
  primary. This is the most error-prone part of Phase 3.
- **Modal sheets** currently `beginSheet` on `primary_window`; must target the
  anchor's window.
