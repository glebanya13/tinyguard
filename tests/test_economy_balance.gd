extends SceneTree
## Gem economy balance: income against the shop catalog (first and last item reachable in a
## sane time), one-time income and daily income within the bounds the Firestore rules
## assume. Prints the table used in docs/GAME_DESIGN.md.
## godot --headless --path . --script res://tests/test_economy_balance.gd

## Model of a player: minutes per wave at x1 (wave_duration 30 s), average game speed, tries.
const MINUTES_PER_WAVE := 0.5
const AVG_SPEED := 1.3
const TRIES := 1.5
## An engaged player plays this many minutes a day; a casual one a third of that.
const ENGAGED_MINUTES := 35.0

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var levels: Array = LevelCatalog.levels()
	var eco: Dictionary = Wallet.data()
	# One-time income and the minutes to earn it, per level (3 stars, both crowns, siege milestones).
	var one_time := 0
	var minutes := 0.0
	var rows: Array[String] = []
	for level: Dictionary in levels:
		var id: int = int(level["id"])
		var stars: int = 0
		for s in range(1, 4):
			stars += Economy.level_star_reward(id, s)
		var crowns: int = Economy.crown_reward(id, 1) + Economy.crown_reward(id, 2)
		var siege: int = 0
		for step in range(1, int(eco["siege"]["max_steps"]) + 1):
			siege += Economy.siege_reward(step)
		var waves: int = int(level["waves"]["count"])
		# Normal win, Hard win, Nightmare win, plus a siege run to 60 waves.
		var level_minutes: float = (
			(waves * 3 * MINUTES_PER_WAVE * TRIES + 60 * MINUTES_PER_WAVE) / AVG_SPEED
		)
		one_time += stars + crowns + siege
		minutes += level_minutes
		rows.append(
			(
				"  level %d: %3d waves, stars %3d, crowns %3d, siege %3d, ~%3.0f min"
				% [id, waves, stars, crowns, siege, level_minutes]
			)
		)
	var achievements: int = 0
	for def in Achievements.all():
		achievements += Economy.achievement_reward(def)
	one_time += achievements
	print("\n".join(rows))
	print(
		(
			"  achievements: %d, one-time total: %d gems in ~%.1f h"
			% [achievements, one_time, minutes / 60.0]
		)
	)

	# Daily income of an engaged player: streak week average, daily challenge, quests, repeats.
	var streak_week: int = 0
	for r in Streak.rewards():
		streak_week += int(r)
	var quests: int = 0
	for r in eco["quests"]["rewards"]:
		quests += int(r)
	var daily_cfg: Dictionary = eco["daily_challenge"]
	var daily: int = int(daily_cfg["base"]) + int(daily_cfg["wave_bonus_cap"])
	var repeat: int = int(eco["repeat_win"]["daily_cap"])
	var per_day: float = float(streak_week) / 7.0 + daily + quests + repeat
	var worst_day: int = (
		int(Streak.rewards().max())
		+ daily
		+ quests
		+ repeat
		+ levels.size() * int(eco["siege"]["record_bonus"])
	)
	print(
		(
			"  daily income (engaged, ~%d min): %.0f gems; casual: %.0f; worst day: %d"
			% [ENGAGED_MINUTES, per_day, per_day / 3.0, worst_day]
		)
	)

	var prices: Array[int] = []
	var total := 0
	for item: Dictionary in Cosmetics.items():
		prices.append(int(item["price"]))
		total += int(item["price"])
	prices.sort()
	var first_hours: float = _hours_to(prices[0], one_time, minutes, per_day)
	var last_hours: float = _hours_to(total, one_time, minutes, per_day)
	var casual_days: float = _days_to(total, one_time, per_day / 3.0)
	var engaged_days: float = _days_to(total, one_time, per_day)
	print("  catalog: %d items, %d gems; cheapest %d" % [prices.size(), total, prices[0]])
	var summary := "  first item after ~%.1f h of play; the whole catalog after ~%.0f h "
	summary += "(%.0f days engaged, %.0f casual)"
	print(summary % [first_hours, last_hours, engaged_days, casual_days])
	check(first_hours <= 1.5, "the first item is within 1.5 h of play (%.1f h)" % first_hours)
	check(
		engaged_days <= 30.0,
		"the whole catalog within 30 days of engaged play (%.0f)" % engaged_days
	)
	check(casual_days <= 120.0, "and within 120 days of casual play (%.0f)" % casual_days)
	check(
		engaged_days >= 7.0,
		"but not within a week: there is something to work towards (%.0f)" % engaged_days
	)
	# The cheapest item is not free and not above the first one-time rewards of level 1.
	check(prices[0] >= 50 and prices[0] <= 200, "cheapest price %d" % prices[0])

	# Bounds the Firestore rules assume (resources/economy.json rules_bounds).
	var bounds: Dictionary = eco["rules_bounds"]
	var rules: String = FileAccess.get_file_as_string("res://firestore.rules")
	check(
		(
			rules.contains("20000 + 700 *")
			and int(bounds["one_time_total"]) == 20000
			and int(bounds["per_day"]) == 700
		),
		"rules and economy.json agree on the bounds"
	)
	var max_levels: int = 20  # levelKeys() in the rules
	var max_one_time := 0
	for id in range(1, max_levels + 1):
		for s in range(1, 4):
			max_one_time += Economy.level_star_reward(id, s)
		max_one_time += Economy.crown_reward(id, 1) + Economy.crown_reward(id, 2)
		for step in range(1, int(eco["siege"]["max_steps"]) + 1):
			max_one_time += Economy.siege_reward(step)
	max_one_time += achievements
	check(
		max_one_time <= int(bounds["one_time_total"]),
		(
			"one-time income of 20 levels (%d) fits the rules' lump (%d)"
			% [max_one_time, int(bounds["one_time_total"])]
		)
	)
	check(
		worst_day * 2 <= int(bounds["per_day"]),
		(
			"the worst day with a x2 event (%d) fits the daily allowance (%d)"
			% [worst_day * 2, int(bounds["per_day"])]
		)
	)
	check(Events.MAX_MULT <= 2.0, "events multiply by at most 2")
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


## Hours of play until `target` gems: the one-time income comes with the campaign hours, the
## rest at the engaged daily rate per play hour.
func _hours_to(target: int, one_time: int, campaign_minutes: float, per_day: float) -> float:
	if target <= one_time:
		return campaign_minutes / 60.0 * float(target) / float(one_time)
	var extra: float = float(target - one_time)
	return campaign_minutes / 60.0 + extra / per_day * ENGAGED_MINUTES / 60.0


func _days_to(target: int, one_time: int, per_day: float) -> float:
	return maxf(float(target - one_time), 0.0) / per_day
