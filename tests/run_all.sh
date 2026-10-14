#!/usr/bin/env bash
# Runs every headless test on every level. Usage: tests/run_all.sh [path/to/godot]
set -u
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1
status=0
run() {
	local out
	out=$(timeout 600 "$@" 2>&1)
	echo "$out" | grep -E "FAIL|RESULT|SCRIPT ERROR"
	echo "$out" | grep -q "RESULT: PASS" || status=1
}
for level in 1 2 3 4 5 6; do
	echo "== level $level"
	LEVEL=$level run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_gameplay.gd
	LEVEL=$level run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_walk.gd
	LEVEL=$level run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_villagers.gd
done
echo "== pause / speed / stars / perks / endless"
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_meta.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_combat.gd
run "$GODOT" --headless --path . --script res://tests/test_online.gd
echo "== accounts / onboarding / tutorial"
run "$GODOT" --headless --path . --script res://tests/test_accounts.gd
run "$GODOT" --headless --path . --script res://tests/test_email_accounts.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_tutorial.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_pause.gd
exit $status
