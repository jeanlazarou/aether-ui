#!/bin/bash
# Build an Aether UI application.
# Usage: ./build.sh <source.ae> [output_binary]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AETHERC="aetherc"

# System-wide Aether headers/libraries
AETHER_INCLUDES="-I/usr/local/include/aether/runtime -I/usr/local/include/aether/runtime/actors -I/usr/local/include/aether/std -I/usr/local/include/aether/std/collections"
AETHER_LIB_PATH="/usr/local/lib/aether"

SOURCE="${1:?Usage: $0 <source.ae> [output_binary]}"
OUTPUT="${2:-build/$(basename "$SOURCE" .ae)}"
C_FILE="${OUTPUT}.c"

echo "Compiling $SOURCE -> $C_FILE"
"$AETHERC" "$SOURCE" "$C_FILE"

OS="$(uname -s)"
case "$OS" in
    Darwin)
        echo "Platform: macOS (AppKit)"
        clang -O0 -g -fobjc-arc \
            $AETHER_INCLUDES \
            "$C_FILE" "$SCRIPT_DIR/aether_ui_macos.m" \
            "$SCRIPT_DIR/aether_ui_system_extras.c" \
            -L"$AETHER_LIB_PATH" -laether \
            -o "$OUTPUT" \
            -framework AppKit -framework Foundation -framework QuartzCore -pthread -lm
        ;;
    Linux)
        if ! pkg-config --exists gtk4 2>/dev/null; then
            echo "Error: GTK4 dev libraries not found."
            exit 1
        fi
        echo "Platform: Linux (GTK4)"
        # libnotify is optional — if present, the GTK4 backend wires real
        # OS notifications via NotifyNotification; otherwise notify*()
        # land in the registry only (still drivable via AetherUIDriver).
        LIBNOTIFY_CFLAGS=""
        LIBNOTIFY_LIBS=""
        if pkg-config --exists libnotify 2>/dev/null; then
            LIBNOTIFY_CFLAGS="-DAEUI_HAVE_LIBNOTIFY=1 $(pkg-config --cflags libnotify)"
            LIBNOTIFY_LIBS="$(pkg-config --libs libnotify)"
        fi
        # GDBus for StatusNotifierItem + DBusMenu is part of GIO, which
        # is a transitive dep of GTK4 — no extra pkg-config probe needed.
        #
        # AETHER_LIBS pulls in libaether's transitive deps (PCRE2 / SSL /
        # zlib / nghttp2) via `ae cflags --libs`. Examples that import
        # std.regex-using modules (e.g. the AeVG port's rasterize/parser)
        # need -lpcre2-8 at link time; plain -laether doesn't pull it in.
        AETHER_LIBS="$(ae cflags --libs 2>/dev/null || true)"
        gcc -O0 -g -pipe \
            $(pkg-config --cflags gtk4) \
            $AETHER_INCLUDES \
            $LIBNOTIFY_CFLAGS \
            "$C_FILE" "$SCRIPT_DIR/aether_ui_gtk4.c" \
            "$SCRIPT_DIR/aether_ui_system_extras.c" \
            "$SCRIPT_DIR/aether_ui_sni.c" \
            -L"$AETHER_LIB_PATH" -laether \
            -o "$OUTPUT" \
            -pthread -lm $(pkg-config --libs gtk4) $LIBNOTIFY_LIBS $AETHER_LIBS
        ;;
    MINGW*|MSYS*|CYGWIN*)
        echo "Platform: Windows (native Win32)"
        OUT_EXE="${OUTPUT}.exe"
        [[ "$OUTPUT" != *.exe ]] && ACTUAL_OUT="$OUT_EXE" || ACTUAL_OUT="$OUTPUT"
        gcc -O2 -g -pipe \
            $AETHER_INCLUDES \
            "$C_FILE" "$SCRIPT_DIR/aether_ui_win32.c" \
            "$SCRIPT_DIR/aether_ui_test_server.c" \
            "$SCRIPT_DIR/aether_ui_system_extras.c" \
            -L"$AETHER_LIB_PATH" -laether \
            -o "$ACTUAL_OUT" \
            -luser32 -lgdi32 -lgdiplus -lcomctl32 -lcomdlg32 \
            -lshell32 -lole32 -luuid -ldwmapi -luxtheme \
            -lws2_32 -pthread -lm
        OUTPUT="$ACTUAL_OUT"
        ;;
    *)
        echo "Error: Unsupported platform '$OS'."
        echo "Aether UI supports macOS (AppKit), Linux (GTK4), and Windows (Win32)."
        exit 1
        ;;
esac

echo "Built: $OUTPUT"
