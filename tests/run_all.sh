#!/usr/bin/env bash
# Runs every headless test on every level.
# Usage: tests/run_all.sh [path/to/godot] [--only <regex>]
#   --only <regex>  run only tests whose script name matches (extended regex), e.g.
#                   --only 'accounts|records' or --only test_replay (levels still loop).
# Exit code is non-zero if any test fails, errors out, times out, or if no test ran.
# Env: TEST_TIMEOUT (seconds per test, default 600).
# Isolation: every test process gets its own empty HOME / XDG_DATA_HOME, so user://
# (saves, sessions, logs) is private to that one run. Tests never touch the real game's
# user://progress.cfg and can run next to a normal game launch or another run_all.sh.
set -u
GODOT="godot"
ONLY=""
while [ $# -gt 0 ]; do
	case "$1" in
		--only)
			if [ $# -lt 2 ]; then
				echo "FATAL: --only needs a pattern" >&2
				exit 2
			fi
			ONLY="$2"
			shift 2
			;;
		--only=*)
			ONLY="${1#--only=}"
			shift
			;;
		*)
			GODOT="$1"
			shift
			;;
	esac
done
# Tests must never use a local firebase.cfg (it points at the real Firebase project).
export BIMBLEGUARD_OFFLINE=1
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
leaky=0
ERRORS_FILE="tests/expected_errors.txt"
# Leaks at exit are reported in the summary but never fail a test.
LEAK_RE='ObjectDB instances were leaked|resources still in use at exit'
run() {
	local out rc name bad leaks iso
	name="${*: -1}"
	if [ -n "$ONLY" ] && ! echo "$name" | grep -Eq "$ONLY"; then
		return 0
	fi
	iso=$(mktemp -d "${TMPDIR:-/tmp}/bimbleguard-test.XXXXXX")
	out=$(limit env HOME="$iso" XDG_DATA_HOME="$iso/xdg" "$@" 2>&1)
	rc=$?
	rm -rf "$iso"
	ran=$((ran + 1))
	echo "$out" | grep -E "FAIL|RESULT|SCRIPT ERROR"
	# Engine errors/warnings that the test did not announce in expected_errors.txt.
	bad=$(echo "$out" | grep -E '^(SCRIPT ERROR|ERROR|WARNING|USER ERROR|USER WARNING)|Parse Error' \
		| grep -Ev "$LEAK_RE" \
		| { if [ -f "$ERRORS_FILE" ]; then grep -Evf <(grep -Ev '^[[:space:]]*(#|$)' "$ERRORS_FILE") || true; else cat; fi; })
	leaks=$(echo "$out" | grep -E "$LEAK_RE" || true)
	if [ -n "$leaks" ]; then
		leaky=$((leaky + 1))
		echo "-- leak warning (not a failure): ${LEVEL:+level $LEVEL }$name"
	fi
	if ! echo "$out" | grep -q "RESULT: PASS"; then
		failed=$((failed + 1))
		echo "!! NOT PASSED: ${LEVEL:+level $LEVEL }$name (exit code $rc)"
		if [ "$rc" -ge 124 ]; then
			echo "!! (possibly timed out after ${TIMEOUT_SEC}s)"
		fi
	elif [ -n "$bad" ]; then
		failed=$((failed + 1))
		echo "!! ERRORS IN OUTPUT: ${LEVEL:+level $LEVEL }$name"
		echo "$bad" | head -10 | sed 's/^/   /'
	fi
}
for level in 1 2 3 4 5 6; do
	echo "== level $level"
	LEVEL=$level run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_gameplay.gd
	LEVEL=$level run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_walk.gd
	LEVEL=$level run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_villagers.gd
	LEVEL=$level run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_wood_economy.gd
	LEVEL=$level run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_card_select.gd
	LEVEL=$level run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_forge_button.gd
	LEVEL=$level run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_lane_hint.gd
	LEVEL=$level run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_replay.gd
	LEVEL=$level run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_command_validation.gd
	LEVEL=$level run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_coop_integration.gd
done
echo "== pause / speed / stars / perks / endless"
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_meta.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_combat.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_hero_target.gd
run "$GODOT" --headless --path . --script res://tests/test_online.gd
run "$GODOT" --headless --path . --script res://tests/test_records.gd
run "$GODOT" --headless --path . --script res://tests/test_waves.gd
run "$GODOT" --headless --path . --script res://tests/test_difficulty.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_units.gd
run "$GODOT" --headless --path . --script res://tests/test_i18n.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_fx.gd
run "$GODOT" --headless --path . --script res://tests/test_quality_guard.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_memory_budget.gd
run "$GODOT" --headless --path . --script res://tests/test_exit_reasons.gd
echo "== co-op network (fake transport)"
run "$GODOT" --headless --path . --script res://tests/test_coop_net.gd
run "$GODOT" --headless --path . --script res://tests/test_coop_lobby_ui.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_coop_flow.gd
echo "== daily challenge / achievements"
run "$GODOT" --headless --path . --script res://tests/test_daily.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_daily_replay.gd
run "$GODOT" --headless --path . --script res://tests/test_daily_online.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_achievements.gd
echo "== gems: wallet / streak / quests"
run "$GODOT" --headless --path . --script res://tests/test_wallet.gd
run "$GODOT" --headless --path . --script res://tests/test_streak.gd
run "$GODOT" --headless --path . --script res://tests/test_quests.gd
run "$GODOT" --headless --path . --script res://tests/test_economy_balance.gd
run "$GODOT" --headless --path . --script res://tests/test_shop.gd
run "$GODOT" --headless --path . --script res://tests/test_shop_ui.gd
echo "== accounts / onboarding / tutorial"
run "$GODOT" --headless --path . --script res://tests/test_accounts.gd
run "$GODOT" --headless --path . --script res://tests/test_email_accounts.gd
run "$GODOT" --headless --path . --script res://tests/test_email_errors.gd
run "$GODOT" --headless --path . --script res://tests/test_signup_flow.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_tutorial.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_pause.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_hud_layout.gd
echo "== device matrix (screens, languages, cutouts)"
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_device_matrix.gd
run "$GODOT" --headless --path . --script res://tests/test_map_layout.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_endgame.gd
run "$GODOT" --headless --fixed-fps 60 --path . --script res://tests/test_end_to_map.gd

echo "== summary: $ran run, $failed not passed, $leaky with leak warnings at exit"
if [ "$ran" -eq 0 ]; then
	echo "FATAL: no tests were run" >&2
	exit 1
fi
if [ "$failed" -ne 0 ]; then
	exit 1
fi
