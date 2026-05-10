# Notes to self (LLM assisting on Aether UI)

Not a CLAUDE.md — short, opinionated, written for a future LLM picking up mid-task. Re-read at start of every session.

## What Aether UI is
A declarative widget DSL for Aether, porting the Perry UI framework. It supports Linux (GTK4), macOS (AppKit), and Windows (native Win32), sharing a common backend ABI in `aether_ui_backend.h`.

## Development Principles
- **Config IS Code**: Aether UI follows the trailing-block builder pattern. Don't add config loaders; use the DSL.
- **Cross-Platform ABI**: Any new widget functionality must be implemented in all three backends (GTK4, AppKit, Win32). Use the `aether_ui_backend.h` ABI as the single source of truth.
- **Headless Testing**: All UI operations that would normally show a modal (alerts, file pickers) MUST honor the `AETHER_UI_HEADLESS` environment variable by returning early on CI to prevent hanging the test runner.
- **AetherUIDriver**: The built-in HTTP test server is the primary way to test UI interactions. It must be maintained to expose widget state and mutations consistently across platforms.

## Building / Testing
- **Compiler**: Uses system-wide `aetherc` (v0.140.0+).
- **Environment**: Headers are in `/usr/local/include/aether/`, libraries in `/usr/local/lib/aether/`.
- **Build**: `./build.sh <source.ae> [output]`
- **CI**: `./ci.sh` runs the full lifecycle: build, smoke test, and HTTP driver integration tests.
- **Bootstrap**: If Aether is missing from `/usr/local/`, use `./bootstrap_aether.sh` to fetch and build it locally.

## Files/dirs worth knowing
- `aether_ui.ae`: The Aether-facing surface (imports, DSL wrappers).
- `aether_ui_backend.h`: The backend ABI.
- `aether_ui_<platform>.c/m`: The native platform implementations.
- `aether_ui_test_server.c/h`: The shared HTTP test server implementation.
- `ci.sh`: The canonical source of truth for the CI test pipeline.
- `examples/`: The source of all example apps.

## Idioms that keep biting
- **Widget Registry**: Native widgets (GtkWidget*, NSView*) are registered in a flat global array and referenced via 1-based integers (`handle`). Never leak these handles.
- **Sealing**: Use `aether_ui.seal_widget()` and `aether_ui.seal_subtree()` to protect widgets from automation in test environments.
- **Imports**: All examples must use `import aether_ui`.
- **CSS**: In the GTK4 backend, avoid global CSS. Apply styling using `aether_ui_apply_css` which scopes rules to a specific widget via a handle-derived class name (`.aui-{handle}`).
