# Desktop notification surface needed

**Reporter**: avn port (Claude session, 2026-05-20)
**Toolchain**: aether-ui at `~/scm/AetherThings/aether-ui/`
(GTK4 / AppKit / Win32 backends)
**Use case**: AvnSync v2 — background filesystem-sync app patterned
on OxenSync / Dropbox / Syncthing. When a sync completes, a push
gets rejected with a conflict, or a remote change touches a file
the user has open locally, the app needs to surface a
non-modal, non-window-stealing notification — the OS-level
notification system (notification-area toast on
Linux/Windows, NSUserNotification banner on macOS).

## What aether-ui has today

`alert(title, message)` — modal, in-app, blocks the main thread
until dismissed. Right shape for "user must confirm before
proceeding"; wrong shape for "FYI, three files just synced."

There is no system-notification surface today:

```
$ grep -in "notify\|notification\|toast\|nsusernotif\|libnotify" \
      aether_ui*.{ae,c,h,m} 2>/dev/null
(no matches)
```

## What's missing

Per-platform reference for what this maps to:

| Platform | Underlying API                                                                   |
|----------|----------------------------------------------------------------------------------|
| Linux    | `libnotify` (`notify_send`) or `org.freedesktop.Notifications` D-Bus interface   |
| macOS    | `UNUserNotificationCenter` (modern) — fallback `NSUserNotification` (deprecated) |
| Windows  | `Windows.UI.Notifications.ToastNotificationManager` via Toast XML + AUMID        |

All three share the same shape: app emits a notification with
title/body/optional-icon, OS schedules display in its notification
area, user may click to invoke a callback or dismiss. Sound /
priority / replace-by-tag are common knobs.

## Proposed DSL shape

```aether
import aether_ui

main() {
    // ... existing app setup ...

    // Simple form — fire-and-forget.
    aether_ui.notify("AvnSync", "5 files synced to demo@HEAD")

    // With icon + click callback + tag for dedupe-replace.
    aether_ui.notify_full("AvnSync",
                         "Push rejected — conflict in README.md",
                         "icons/conflict.png",
                         "avnsync-conflict-README.md") callback {
        // Open the conflict view in the main window.
        aether_ui.window_focus(main_window)
        aether_ui.window_navigate(main_window, "/conflicts/README.md")
    }
}
```

Open shape questions for the implementer:

1. **Sync vs async.** `notify` should be fire-and-forget. The
   callback in `notify_full` fires later (potentially after
   `notify_full` has returned) on the platform's notification
   handler thread; the backend marshals it back to the main
   thread before invoking the Aether closure. Same pattern as
   button callbacks.

2. **Tag / replace semantics.** Each platform's notification
   system supports replacing-by-tag (Linux freedesktop spec's
   `replaces_id`; macOS `UNNotificationRequest.identifier`;
   Windows Toast `tag` + `group`). Expose as the fourth
   `notify_full` arg — empty string = no replace.

3. **Permission prompt.** macOS Catalina+ requires user permission
   on first notification. Default behaviour: best-effort, return
   silently if denied. Add `notify_request_permission()` for apps
   that want to prompt at startup; on Linux/Windows it's a no-op.

4. **Sound.** Default to platform-conventional (silent on Linux
   if not configured; "Glass" or default on macOS; default toast
   sound on Windows). No need to expose at v1.

5. **Click vs dismiss vs action buttons.** v1: click-callback
   only. Action buttons (e.g. "Retry" / "Ignore") are a v2 ask;
   each platform supports them via different mechanisms.

## Headless mode

Honour `AETHER_UI_HEADLESS=1` per the LLM.md convention:
`notify` returns immediately, `notify_full`'s callback is
registered against an in-memory queue but the OS-level
notification call is suppressed. CI never blocks on a
notification banner that never gets dismissed.

## AetherUIDriver surface

```
GET  /notifications                        → list of pending/queued notifications
POST /notifications/{id}/click             → simulate user click → fires callback
POST /notifications/{id}/dismiss           → simulate dismissal
```

`/notifications` lets a test assert "exactly one notification was
emitted matching tag=avnsync-conflict-README.md after a push";
`/click` validates the callback wiring without a real desktop
session.

## Concrete ask

Phase 1: ship `notify(title, message)` and
`notify_full(title, message, icon, tag) callback { … }` in all
three backends. AetherUIDriver coverage for the three endpoints.
Headless guard. macOS permission flow (return silently on first
deny, no prompt by default).

Phase 2 (separable, separate ask): notification action buttons,
explicit permission-prompt entry, sound knobs.

## Cross-references

- `~/scm/AetherThings/avn/TODO.md` §AvnSync v2 — the upstream ask
  comes from there. v2 is a roadmap item not yet started.
- OxenSync (Go reference) called `fyne.CurrentApp().SendNotification`;
  that's the same fire-and-forget shape proposed above.

## Parallel-work note

This is independent of the system-tray ask
(`system-tray-status-icon-needed.md`) — separate widget surface,
separate backend code paths, separate AetherUIDriver endpoints.
Either can land first. (Most "tray-app" apps want both, but
they're loosely coupled — a tray app without notifications still
works, a notification-emitting app without a tray still works.)
