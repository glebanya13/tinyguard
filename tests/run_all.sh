#!/usr/bin/env bash
# Runs every headless test on every level. Usage: tests/run_all.sh [path/to/godot]
set -u
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1
status=0
run() {
	local out
	out=$("$@" 2>&1)
	echo "$out" | grep -E "FAIL|RESULT|SCRIPT ERROR"
	echo "$out" | grep -q "RESULT: PASS" || status=1
}
for level in 1 2 3; do
	echo "== level $level"
	LEVEL=$level run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_gameplay.gd
	LEVEL=$level run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_walk.gd
done
echo "== pause / speed / stars"
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_pause.gd
exit $status
