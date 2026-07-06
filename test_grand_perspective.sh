#!/bin/bash
# AetherUIDriver script for grand_perspective — exercises the three-pane
# disk-usage app end to end over HTTP. The harness (ci.sh) exports
# AEVG_DIR pointing at a fixture this script also knows via $GP_FIXTURE
# (both set by the caller); the app scans it on launch.
#
#   fixture/
#     big.bin   400KB   (list row 0)
#     mid.bin   250KB   (list row 1)
#     sub/      200KB   (one file inside)
#
# Usage:  GP_FIXTURE=/path ./test_grand_perspective.sh [port]

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

status_line() {
    curl -s "$BASE/widgets" | python3 -c "
import json,sys
ws=json.load(sys.stdin)
best=''
for w in ws:
    t=w.get('text','')
    if w['type']=='text' and any(k in t for k in ('Scan','Folder','File:','Highlight','trash','Select','Copied','—')):
        best=t
print(best)"
}

crumbs() {
    curl -s "$BASE/widgets" | python3 -c "
import json,sys
print(' / '.join(w['text'] for w in json.load(sys.stdin) if w['type']=='button' and w['visible'] and w['text'] not in ('Zoom In','Zoom Out','Rescan','Stop','Open','Reveal','Delete','Confirm delete?','by Size','by Depth','by Type')))"
}

wid_of() {
    curl -s "$BASE/widgets" | python3 -c "
import json,sys
print(next(w['id'] for w in json.load(sys.stdin) if w.get('text')==sys.argv[1]))" "$1"
}

echo "=== AetherUIDriver: grand_perspective ==="
echo "Target: $BASE   fixture: $GP_FIXTURE"

echo "Waiting for test server + scan..."
for _ in $(seq 1 40); do
    curl -sf -o /dev/null "$BASE/widgets" && break
    sleep 0.3
done
for _ in $(seq 1 40); do
    status_line | grep -q "Scan complete" && break
    sleep 0.3
done

echo ""
echo "--- Test 1: async scan completed with correct totals ---"
S=$(status_line)
assert_contains "scan completed" "Scan complete" "$S"
assert_contains "sees 3 files" "3 files" "$S"

echo ""
echo "--- Test 2: list row click selects with %-of-parent ---"
curl -s -X POST "$BASE/canvas/1/click?x=100&y=90" > /dev/null; sleep 0.4
S=$(status_line)
assert_contains "row 0 selected (big.bin)" "big.bin" "$S"
assert_contains "shows % of parent" "% of parent" "$S"

echo ""
echo "--- Test 3: Zoom In drills the selected dir; '..' returns ---"
# select the sub dir row (row 2: 400k, 250k, 200k-dir sorted desc)
curl -s -X POST "$BASE/canvas/1/click?x=100&y=140" > /dev/null; sleep 0.3
ZI=$(wid_of "Zoom In")
curl -s -X POST "$BASE/widget/$ZI/click" > /dev/null; sleep 0.4
assert_contains "crumbs show root / sub" "sub" "$(crumbs)"
curl -s -X POST "$BASE/canvas/1/click?x=100&y=68" > /dev/null; sleep 0.4   # ".." row
C=$(crumbs)
if echo "$C" | grep -q "sub"; then
    echo "  FAIL: '..' did not return (crumbs: $C)"; FAIL=$((FAIL+1))
else
    echo "  PASS: '..' returned to root"; PASS=$((PASS+1))
fi

echo ""
echo "--- Test 4: legend row click toggles a type highlight ---"
curl -s -X POST "$BASE/canvas/1/click?x=1100&y=65" > /dev/null; sleep 0.4
assert_contains "highlight on" "Highlighting" "$(status_line)"
curl -s -X POST "$BASE/canvas/1/click?x=1100&y=65" > /dev/null; sleep 0.4
assert_contains "highlight off" "Highlight off" "$(status_line)"

echo ""
echo "--- Test 5: map context menu Copy path (canvas widget route) ---"
CW=$(curl -s "$BASE/widgets" | python3 -c "import json,sys; print(next(w['id'] for w in json.load(sys.stdin) if w['type']=='canvas'))")
curl -s -X POST "$BASE/canvas/1/click?x=100&y=90" > /dev/null; sleep 0.3    # select big.bin
R=$(curl -s -X POST "$BASE/widget/$CW/context_menu/3")                       # item 3 = Copy path
assert_contains "menu activated" '"activated":0' "$R"
sleep 0.3
assert_contains "status shows Copied" "Copied" "$(status_line)"

echo ""
echo "--- Test 6: Delete guard, arm, confirm — file leaves the disk ---"
DEL=$(wid_of "Delete")
# clear selection via Escape-equivalent: select then delete flow needs selection;
# first prove the guard with no selection (fresh select cleared by nav above? select then clear via legend off leaves selection... use guard by deleting AFTER trash removes selection)
curl -s -X POST "$BASE/canvas/1/click?x=100&y=115" > /dev/null; sleep 0.3   # select mid.bin (row 1)
curl -s -X POST "$BASE/widget/$DEL/click" > /dev/null; sleep 0.3
BTN=$(curl -s "$BASE/widgets" | python3 -c "import json,sys; print(next(w['text'] for w in json.load(sys.stdin) if w['id']==$DEL))")
assert_contains "armed: button relabelled" "Confirm" "$BTN"
curl -s -X POST "$BASE/widget/$DEL/click" > /dev/null; sleep 1.5
if [ -f "$GP_FIXTURE/mid.bin" ]; then
    echo "  FAIL: mid.bin still on disk"; FAIL=$((FAIL+1))
else
    echo "  PASS: mid.bin moved to trash"; PASS=$((PASS+1))
fi
curl -s -X POST "$BASE/widget/$DEL/click" > /dev/null; sleep 0.3
assert_contains "guard after trash (no selection)" "Select" "$(status_line)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
