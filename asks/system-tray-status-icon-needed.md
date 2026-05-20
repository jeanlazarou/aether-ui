# System tray / status icon widget needed

**Reporter**: avn port (Claude session, 2026-05-20)
**Toolchain**: aether-ui at `~/scm/AetherThings/aether-ui/`
(GTK4 / AppKit / Win32 backends)
**Use case**: AvnSync v2 — background filesystem-sync app patterned
on OxenSync (Go) / Dropbox / Syncthing. The user expects an icon
in the system tray (Linux notification area / macOS menu-bar
extras / Windows taskbar notification area), right-clickable to
get a popup menu, that surfaces sync status (clean / syncing /
conflict) without occupying a window.

## What aether-ui has today

A full in-window widget surface — vstack/hstack/grid layout,
text/textfield/toggle/picker/etc., reactive state cells,
clipboard, alert, sheet, dark-mode detection, menu_bar (top of
window), AetherUIDriver HTTP test server.

What it doesn't have: any way to put an icon *outside* a window
in the OS-level status/tray area, or to attach a popup menu to
that icon.

```
$ grep -in "tray\|status.icon\|systray" aether_ui*.{ae,c,h,m} 2>/dev/null
(no matches)
```

## What's missing

Per-platform reference for what this maps to:

| Platform | Underlying API                                                                |
|----------|-------------------------------------------------------------------------------|
| Linux    | `libayatana-appindicator` (modern; `GtkStatusIcon` is deprecated in GTK4)     |
| macOS    | `NSStatusItem` + `NSStatusBar.system`                                         |
| Windows  | `Shell_NotifyIcon(NIM_ADD, NIF_ICON \| NIF_TIP \| NIF_MESSAGE)`               |

These three APIs differ in lifecycle, click vs context-menu
semantics, and per-display behaviour, but they share a common
shape: register an icon → optionally attach a menu → receive
callback when clicked or when a menu item is chosen.

## Proposed DSL shape

```aether
import aether_ui

main() {
    sync_status = aether_ui.ui_state(0)   // 0=clean 1=syncing 2=conflict

    // Build the popup menu first (re-uses existing menu* DSL).
    m = aether_ui.menu("AvnSync")
    aether_ui.menu_item(m, "Sync now") callback {
        // ...
    }
    aether_ui.menu_item(m, "Open folder") callback {
        // ...
    }
    aether_ui.menu_separator(m)
    aether_ui.menu_item(m, "Quit") callback {
        aether_ui.app_quit()
    }

    // Attach to the OS tray. Three icons selected per status.
    tray = aether_ui.tray_icon("avnsync") callback {
        // Optional: left-click handler. Right-click is implicitly
        // the popup menu. On Linux/Win some platforms only emit
        // right-click → leave left-click handler optional.
    }
    aether_ui.tray_set_tooltip(tray, "AvnSync — synced")
    aether_ui.tray_set_menu(tray, m)

    // Optional reactive icon swap on state change.
    aether_ui.tray_set_icon_for_state(tray, sync_status,
                                      "icons/clean.png",
                                      "icons/syncing.png",
                                      "icons/conflict.png")

    // No app_run with a root — this is a "tray-only" process.
    // app_run_headless keeps the GLib/AppKit/Win32 main loop alive
    // without opening a window.
    aether_ui.app_run_headless()
}
```

Open shape questions for the implementer:

1. **Right-click vs left-click semantics.** GTK4 + AppKit emit
   both as distinct events; Win32's Shell_NotifyIcon emits both
   as `WM_LBUTTONUP` / `WM_RBUTTONUP`. The default `tray_set_menu`
   should bind the menu to the platform-conventional gesture
   (right-click on Linux/Win, left-click on macOS).

2. **Icon source.** PNG path, NSImage name, or `.ico` resource?
   Recommend filesystem PNG path for cross-platform simplicity
   (let the backend handle conversion). For macOS template-style
   icons (mono with adaptive light/dark), add a
   `tray_set_icon_template(tray, 1)` knob.

3. **Process-lifecycle.** Tray-only apps don't have a root widget,
   so `app_run(title, w, h, root)` doesn't fit. A new
   `app_run_headless()` (or `app_run_tray_only(tray)`) is needed
   to keep the main loop alive without opening a window. Existing
   `enable_test_server` should still work in this mode.

4. **Linux fallback.** Modern GNOME hides the system tray by
   default; the user needs to install the AppIndicator extension
   or run another DE. The DSL surface stays the same — failure
   mode is "icon never appears." Document but don't try to fix.

## Headless mode

Honour `AETHER_UI_HEADLESS=1` per the LLM.md convention:
`tray_icon` returns a fake handle (non-zero), `tray_set_*` are
no-ops, `app_run_headless()` short-circuits to keep CI from
hanging. The AetherUIDriver test server should still come up so
HTTP-driven tests can `POST /tray/{handle}/click` and
`POST /tray/{handle}/menu_item/{label}/activate` to exercise the
callback wiring without a display.

## AetherUIDriver surface

Following the existing `/widget/{id}/click | set_text | toggle`
pattern, add:

```
GET  /tray/{id}                 → state + menu structure
POST /tray/{id}/click           → invoke the left-click callback
POST /tray/{id}/menu/activate   → with JSON body {"label": "..."}
POST /tray/{id}/set_tooltip     → with JSON body {"text": "..."}
GET  /tray/{id}/icon            → current icon path / template flag
```

Same `seal_widget` semantics as the rest — `tray_seal(tray)`
returns 403 from the driver for the tray and its menu items.

## Concrete ask

Phase 1: ship `tray_icon`, `tray_set_tooltip`, `tray_set_menu`,
`app_run_headless` in all three backends. AetherUIDriver
coverage for `/tray/{id}/click` and `/tray/{id}/menu/activate`.
Headless guard.

Phase 2 (separable, separate ask): icon-template / reactive icon
swap (`tray_set_icon_for_state`). Phase 1 unblocks AvnSync v2;
phase 2 is polish.

## Cross-references

- `~/scm/AetherThings/avn/TODO.md` §AvnSync v2 — the upstream
  ask comes from there. v2 is a roadmap item not yet started.
- `~/scm/AetherThings/avn/README.md` — top-level project context.
- OxenSync (Go reference) used Fyne's `desktop.App` tray API
  via `systray.NewItem`; that's the shape AvnSync's user-facing
  UX is patterned on.

## Parallel-work note

This is independent of the desktop-notifications ask
(`desktop-notifications-needed.md`) — separate widget surface,
separate backend code paths, separate AetherUIDriver endpoints.
Either can land first.
