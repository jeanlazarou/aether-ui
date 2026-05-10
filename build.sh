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
        gcc -O0 -g -pipe \
            $(pkg-config --cflags gtk4) \
            $AETHER_INCLUDES \
            "$C_FILE" "$SCRIPT_DIR/aether_ui_gtk4.c" \
            -L"$AETHER_LIB_PATH" -laether \
            -o "$OUTPUT" \
            -pthread -lm $(pkg-config --libs gtk4)
        ;;
    MINGW*|MSYS*|CYGWIN*)
        echo "Platform: Windows (native Win32)"
        OUT_EXE="${OUTPUT}.exe"
        [[ "$OUTPUT" != *.exe ]] && ACTUAL_OUT="$OUT_EXE" || ACTUAL_OUT="$OUTPUT"
        gcc -O2 -g -pipe \
            $AETHER_INCLUDES \
            "$C_FILE" "$SCRIPT_DIR/aether_ui_win32.c" \
            "$SCRIPT_DIR/aether_ui_test_server.c" \
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
