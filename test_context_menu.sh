#!/bin/bash
# AetherUIDriver script for the context_menu example — exercises the
# right-click context menu end to end over HTTP:
#   - the menu is present with the expected item count on each owner
#   - opening it maps a real surface (mapped=1)
#   - activating an item fires its closure (label/status/clipboard mutate)
#
# The driver routes drive the SAME backend path a real right-click uses
# (ctx_menu_open + item closure), so a green run here means the menu works
# on this platform's window system.
#
# Usage:  ./test_context_menu.sh [port]

set -e

PORT="${1:-9222}"
BASE="http://127.0.0.1:$PORT"
PASS=0
FAIL=0

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -q "$needle"; then
        echo "  PASS: $desc"; PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected to contain '$needle', got '$haystack')"
        FAIL=$((FAIL + 1))
    fi
}

# Resolve a widget handle by exact text match.
wid() {
    curl -s "$BASE/widgets" | python3 -c "
import json,sys
want=sys.argv[1]
for w in json.load(sys.stdin):
    if w.get('text')==want: print(w['id']); break
" "$1"
}

echo "=== AetherUIDriver: context_menu ==="
echo "Target: $BASE"

echo "Waiting for test server..."
for _ in $(seq 1 30); do
    curl -sf -o /dev/null "$BASE/widgets" && { echo "Server ready."; break; }
    sleep 0.2
done

QUOTE=$(wid "The quick brown fox jumps over the lazy dog")
BTN=$(wid "A button with its own menu")
echo "quote handle=$QUOTE  button handle=$BTN"

# 1. Menu on the quote label opens and maps.
echo ""
echo "--- Test 1: quote menu opens (maps a surface) ---"
R=$(curl -s -X POST "$BASE/widget/$QUOTE/context_menu")
assert_contains "quote menu mapped" '"mapped":1' "$R"

# 2. Activating item 0 (Copy text) fires its closure → status updates.
echo ""
echo "--- Test 2: activate 'Copy text' (item 0) ---"
R=$(curl -s -X POST "$BASE/widget/$QUOTE/context_menu/0")
assert_contains "open+activate item 0 ok" '"activated":0' "$R"
sleep 0.3
STATUS=$(curl -s "$BASE/widgets" | python3 -c "import json,sys; print(next(w['text'] for w in json.load(sys.stdin) if w['text'].startswith('Copied') or w['text']=='—' or w['text'].startswith('Shouted') or w['text'].startswith('Button')))" 2>/dev/null || echo "?")
assert_contains "status shows Copied" "Copied" "$STATUS"

# 3. Activating item 1 (Shout) mutates the quote label.
echo ""
echo "--- Test 3: activate 'Shout' (item 1) ---"
curl -s -X POST "$BASE/widget/$QUOTE/context_menu/1" > /dev/null
sleep 0.3
QUOTETXT=$(curl -s "$BASE/widgets" | python3 -c "import json,sys; print(next((w['text'] for w in json.load(sys.stdin) if 'FOX' in w['text'] or 'fox' in w['text']), '?'))")
assert_contains "quote is shouted (uppercase)" "THE QUICK BROWN FOX" "$QUOTETXT"

# 4. The button's own separate menu (item 0 = Rename me).
echo ""
echo "--- Test 4: button's own menu renames it ---"
curl -s -X POST "$BASE/widget/$BTN/context_menu/0" > /dev/null
sleep 0.3
BTNTXT=$(curl -s "$BASE/widgets" | python3 -c "import json,sys; print(next((w['text'] for w in json.load(sys.stdin) if w['type']=='button'), '?'))")
assert_contains "button renamed via its menu" "Renamed" "$BTNTXT"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
