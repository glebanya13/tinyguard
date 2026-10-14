#!/usr/bin/env bash
# Runs every headless test on every level. Usage: tests/run_all.sh [path/to/godot]
# Exit code is non-zero if any test fails, errors out, times out, or if no test ran.
# Env: TEST_TIMEOUT (seconds per test, default 600).
set -u
GODOT="${1:-godot}"
TIMEOUT_SEC="${TEST_TIMEOUT:-600}"
cd "$(dirname "$0")/.."

# Portable time limit: GNU timeout / gtimeout (Homebrew coreutils) / perl alarm.
if command -v timeout >/dev/null 2>&1; then
	limit() { timeout "$TIMEOUT_SEC" "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then
	limit() { gtimeout "$TIMEOUT_SEC" "$@"; }
elif command -v perl >/dev/null 2>&1; then
	limit() { perl -e 'alarm shift; exec @ARGV or die "exec failed: $!\n"' "$TIMEOUT_SEC" "$@"; }
else
	echo "warning: no timeout/gtimeout/perl, running without a time limit" >&2
	limit() { "$@"; }
fi

if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "FATAL: Godot not found: $GODOT" >&2
	exit 2
fi

limit "$GODOT" --headless --path . --import >/dev/null 2>&1

ran=0
failed=0
run() {
	local out rc name
	name="${*: -1}"
	out=$(limit "$@" 2>&1)
	rc=$?
	ran=$((ran + 1))
	echo "$out" | grep -E "FAIL|RESULT|SCRIPT ERROR"
	if ! echo "$out" | grep -q "RESULT: PASS"; then
		failed=$((failed + 1))
		echo "!! NOT PASSED: ${LEVEL:+level $LEVEL }$name (exit code $rc)"
		if [ "$rc" -ge 124 ]; then
			echo "!! (possibly timed out after ${TIMEOUT_SEC}s)"
		fi
	fi
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
echo "== co-op network (fake transport)"
run "$GODOT" --headless --path . --script res://tests/test_coop_net.gd
echo "== accounts / onboarding / tutorial"
run "$GODOT" --headless --path . --script res://tests/test_accounts.gd
run "$GODOT" --headless --path . --script res://tests/test_email_accounts.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_tutorial.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_pause.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_endgame.gd

echo "== summary: $ran run, $failed not passed"
if [ "$ran" -eq 0 ]; then
	echo "FATAL: no tests were run" >&2
	exit 1
fi
if [ "$failed" -ne 0 ]; then
	exit 1
fi
