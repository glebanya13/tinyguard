extends SceneTree
## Retention v2 test suite (Stages A and B):
##   - Camp offline passive treasury coins accumulation, rates, upgrade, cap
##   - Time monotonicity and rollback protection (never award coins when time goes backward)
##   - 28-day cumulative visit calendar: 28 reward steps, daily idempotence, skips don't reset
##   - First Run Bonus: +5 gems under "fw:<date>" and x2 treasury coins on first win of the day
##   - Profile persistence and merge (local / cloud)
## Run:
##   mkdir -p /tmp/godot-test && env HOME=/tmp/godot-test /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/test_retention.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_retention.cfg"
	_wipe()
	_run.call_deferred()


func _wipe() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = ProjectSettings.globalize_path(LevelCatalog.save_path + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	LevelCatalog.erase_all()


func _run() -> void:
	_check_camp_accumulation()
	_check_camp_cap()
	_check_camp_monotonicity()
	_check_camp_upgrades()
	_check_calendar_28()
	_check_first_run_bonus()
	_check_profile_save_and_merge()
	_wipe()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _check_camp_accumulation() -> void:
	var state: Dictionary = Camp.empty()
	check(state["level"] == 1 and state["coins"] == 0, "fresh camp starts at level 1 with 0 coins")
	var rate: int = Camp.rate_for_level(1)
	check(rate == 10, "level 1 production rate is 10 coins/h (%d)" % rate)

	# Initial collection initializes last_collect without free coins
	var init: Dictionary = Camp.collect(state, 1000)
	check(init["collected"] == 0 and int(state["last_collect"]) == 1000, "init collection sets last_collect")

	# 1 hour elapsed (3600 s) -> 10 coins
	var pending_1h: int = Camp.pending_coins(state, 1000 + 3600)
	check(pending_1h == 10, "1 hour elapsed yields 10 coins (%d)" % pending_1h)

	# 30 minutes elapsed (1800 s) -> 5 coins
	var pending_30m: int = Camp.pending_coins(state, 1000 + 1800)
	check(pending_30m == 5, "30 minutes elapsed yields 5 coins (%d)" % pending_30m)

	# 2 hours elapsed (7200 s) -> 20 coins
	var pending_2h: int = Camp.pending_coins(state, 1000 + 7200)
	check(pending_2h == 20, "2 hours elapsed yields 20 coins (%d)" % pending_2h)

	# Collect 2 hours
	var res: Dictionary = Camp.collect(state, 1000 + 7200)
	check(res["collected"] == 20 and state["coins"] == 20, "collected 20 coins into balance")
	check(int(state["last_collect"]) == 1000 + 7200, "last_collect updated after collection")
	check(Camp.pending_coins(state, 1000 + 7200) == 0, "pending reset to 0 right after collection")

	# Another collection immediately after pays 0
	var immediate: Dictionary = Camp.collect(state, 1000 + 7200)
	check(immediate["collected"] == 0 and state["coins"] == 20, "immediate collection pays 0")


func _check_camp_cap() -> void:
	var state: Dictionary = Camp.empty()
	Camp.collect(state, 1000)
	var cap_h: int = Camp.cap_hours_for_level(1)
	check(cap_h == 8, "level 1 accumulation cap is 8 hours (%d)" % cap_h)
	var max_coins: int = cap_h * Camp.rate_for_level(1)  # 80

	# 8 hours elapsed: exactly at cap
	var pending_8h: int = Camp.pending_coins(state, 1000 + 8 * 3600)
	check(pending_8h == max_coins, "8 hours yields max cap (%d == %d)" % [pending_8h, max_coins])

	# 12 hours elapsed: capped at 8 hours (80 coins), does not exceed
	var pending_12h: int = Camp.pending_coins(state, 1000 + 12 * 3600)
	check(pending_12h == max_coins, "12 hours is capped at %d coins (%d)" % [max_coins, pending_12h])

	# 48 hours elapsed (2 days): still capped at 80 coins
	var pending_48h: int = Camp.pending_coins(state, 1000 + 48 * 3600)
	check(pending_48h == max_coins, "48 hours remains capped at %d coins" % max_coins)

	# Collect at cap
	var col: Dictionary = Camp.collect(state, 1000 + 48 * 3600)
	check(col["collected"] == max_coins and state["coins"] == max_coins, "collect at cap pays 80 coins")


func _check_camp_monotonicity() -> void:
	var state: Dictionary = Camp.empty()
	Camp.collect(state, 10000)

	# Device clock moves backward to 5000 (< 10000)
	var pending_back: int = Camp.pending_coins(state, 5000)
	check(pending_back == 0, "time went backward: 0 pending coins")

	var col_back: Dictionary = Camp.collect(state, 5000)
	check(col_back["collected"] == 0, "time went backward: collect pays 0")
	check(int(state["last_collect"]) == 10000, "last_collect never rolls back (monotonic)")

	# Forward to 13600 (1 hour after 10000) -> 10 coins
	var col_fwd: Dictionary = Camp.collect(state, 13600)
	check(col_fwd["collected"] == 10 and state["coins"] == 10, "advancing time pays 10 coins")
	check(int(state["last_collect"]) == 13600, "last_collect advanced to 13600")

	# Backward again to 12000 -> 0
	check(Camp.pending_coins(state, 12000) == 0, "rollback after collect gives 0")


func _check_camp_upgrades() -> void:
	var state: Dictionary = Camp.empty()
	state["coins"] = 100

	# Level 1 -> 2 costs 150 coins; player only has 100
	var cost_lvl1: int = Camp.upgrade_cost(1)
	check(cost_lvl1 == 150, "upgrade to level 2 costs 150 coins")
	var fail_up: bool = Camp.upgrade(state)
	check(not fail_up and state["level"] == 1 and state["coins"] == 100, "upgrade fails without sufficient funds")

	# Add coins to 200 and upgrade
	state["coins"] = 200
	var ok_up: bool = Camp.upgrade(state)
	check(ok_up and state["level"] == 2 and state["coins"] == 50, "upgrade succeeds, coins deducted (200 - 150 = 50)")

	# Level 2 stats: 15 coins/h, 10h cap
	var rate_lvl2: int = Camp.rate_for_level(2)
	var cap_lvl2: int = Camp.cap_hours_for_level(2)
	check(rate_lvl2 == 15 and cap_lvl2 == 10, "level 2 has rate 15 and cap 10h")

	Camp.collect(state, 1000)
	# 1h at level 2 -> 15 coins
	check(Camp.pending_coins(state, 1000 + 3600) == 15, "level 2 pending for 1h is 15 coins")
	# 12h at level 2 -> capped at 10h * 15 = 150 coins
	check(Camp.pending_coins(state, 1000 + 12 * 3600) == 150, "level 2 pending for 12h is capped at 150")

	# Upgrade through all levels up to MAX_LEVEL
	state["coins"] = 100000
	for lvl in range(2, Camp.MAX_LEVEL):
		check(Camp.upgrade(state), "upgrade to level %d succeeds" % (lvl + 1))
	check(state["level"] == Camp.MAX_LEVEL, "camp reached MAX_LEVEL (5)")
	check(not Camp.upgrade(state), "cannot upgrade past MAX_LEVEL")


func _check_calendar_28() -> void:
	var cal: Dictionary = Calendar28.empty()
	check(cal["claimed_days"] == 0 and cal["last_claim"] == "", "fresh calendar starts at 0 claimed days")
	var rewards: Array = Calendar28.rewards()
	check(rewards.size() == 28, "calendar has 28 reward steps (%d)" % rewards.size())

	# Day 1 claim
	var wallet: Dictionary = Wallet.empty()
	var camp: Dictionary = Camp.empty()
	check(Calendar28.can_claim(cal, "2026-10-20", wallet), "can claim day 1 on 2026-10-20")

	var step1: Dictionary = Calendar28.claim(cal, "2026-10-20", wallet, camp)
	check(step1["success"] and step1["step"] == 1, "claimed step 1")
	check(step1["coins"] > 0 and step1["gems"] > 0, "step 1 awards both coins and gems (%d, %d)" % [step1["coins"], step1["gems"]])
	check(camp["coins"] == step1["coins"], "coins credited to camp")
	check(Wallet.gems(wallet) == step1["gems"], "gems credited to wallet")
	check(Wallet.has_claim(wallet, "cal:2026-10-20"), "idempotent claim key cal:2026-10-20 present in wallet")

	# Claiming again on the SAME day: fails
	check(not Calendar28.can_claim(cal, "2026-10-20", wallet), "cannot claim again on the same day")
	var again: Dictionary = Calendar28.claim(cal, "2026-10-20", wallet, camp)
	check(not again["success"] and again["coins"] == 0 and again["gems"] == 0, "repeated claim returns failure and 0 rewards")

	# Skip 5 days (gap): visiting on 2026-10-25 advances to step 2, does NOT reset
	check(Calendar28.can_claim(cal, "2026-10-25", wallet), "can claim on 2026-10-25 after a 5-day gap")
	var step2: Dictionary = Calendar28.claim(cal, "2026-10-25", wallet, camp)
	check(step2["success"] and step2["step"] == 2, "skipping days does not reset calendar; advances to step 2")
	check(cal["claimed_days"] == 2, "claimed_days is 2")

	# Clock rollback check
	check(not Calendar28.can_claim(cal, "2026-10-21", wallet), "cannot claim with an earlier date than last claim (anti-cheat)")

	# Milestone steps
	var day7_rew: Dictionary = Calendar28.reward_for_step(7)
	check(int(day7_rew["coins"]) >= 100 and int(day7_rew["gems"]) >= 50, "day 7 is a weekly milestone")
	var day28_rew: Dictionary = Calendar28.reward_for_step(28)
	check(int(day28_rew["coins"]) >= 300 and int(day28_rew["gems"]) >= 150, "day 28 is the grand milestone")

	# Cycle wrap-around after 28 days
	var simulated: Dictionary = Calendar28.empty()
	simulated["claimed_days"] = 28
	check(Calendar28.next_step(int(simulated["claimed_days"])) == 1, "day 29 wraps around to step 1")
	check(Calendar28.step_of(28) == 28, "step_of 28 is 28")
	check(Calendar28.step_of(29) == 1, "step_of 29 is 1 (cycle)")


func _check_first_run_bonus() -> void:
	_wipe()
	Economy.reset_tally()
	var day: String = "2026-10-20"

	var p: Dictionary = PlayerProfile.local()
	check(not Wallet.has_claim(p["wallet"], "fw:" + day), "first win of day not claimed yet")

	# First win of the day
	var res1: Dictionary = Economy.award_first_run(day)
	check(res1["first_win"], "first run of the day awarded first_win=true")
	check(res1["gems"] == 5, "first run bonus awards 5 gems (%d)" % res1["gems"])
	check(res1["coins"] == Camp.battle_reward() * 2, "first run bonus awards x2 treasury coins (%d == %d)" % [res1["coins"], Camp.battle_reward() * 2])
	check(Economy.balance() == 5, "wallet balance reflects +5 gems")
	check(Camp.local()["coins"] == Camp.battle_reward() * 2, "camp balance reflects x2 coins")

	# Second win on the SAME day: no gems, normal 1x coins
	var res2: Dictionary = Economy.award_first_run(day)
	check(not res2["first_win"], "second run on same day has first_win=false")
	check(res2["gems"] == 0, "second run does not award gems")
	check(res2["coins"] == Camp.battle_reward(), "second run awards 1x base coins (%d)" % res2["coins"])
	check(Economy.balance() == 5, "wallet gems unchanged")
	check(Camp.local()["coins"] == Camp.battle_reward() * 3, "camp coins increased by 1x base coins")

	# Next day (2026-10-21): first win bonus is available again
	var next_day: String = "2026-10-21"
	var res3: Dictionary = Economy.award_first_run(next_day)
	check(res3["first_win"], "next day grants first_win=true again")
	check(res3["gems"] == 5, "next day awards +5 gems")
	check(res3["coins"] == Camp.battle_reward() * 2, "next day awards x2 coins")


func _check_profile_save_and_merge() -> void:
	_wipe()
	var p: Dictionary = PlayerProfile.local()
	check(p["schemaVersion"] == PlayerProfile.SCHEMA_VERSION and PlayerProfile.SCHEMA_VERSION >= 4, "schema version is at least 4")

	# Populate camp and calendar
	p["camp"]["level"] = 2
	p["camp"]["coins"] = 250
	p["camp"]["last_collect"] = 12345
	p["calendar"]["claimed_days"] = 6
	p["calendar"]["last_claim"] = "2026-10-20"
	PlayerProfile.save_local(p)

	# Reload from save file
	LevelCatalog._save = null
	LevelCatalog._save_loaded_from = ""
	var loaded: Dictionary = PlayerProfile.local()
	check(loaded["camp"]["level"] == 2 and loaded["camp"]["coins"] == 250, "camp state persists through save and reload")
	check(int(loaded["camp"]["last_collect"]) == 12345, "camp last_collect persists")
	check(loaded["calendar"]["claimed_days"] == 6 and loaded["calendar"]["last_claim"] == "2026-10-20", "calendar persists through save and reload")

	# Merge with another device profile
	var cloud: Dictionary = PlayerProfile.empty()
	cloud["camp"]["level"] = 3
	cloud["camp"]["coins"] = 400
	cloud["camp"]["last_collect"] = 20000
	cloud["calendar"]["claimed_days"] = 10
	cloud["calendar"]["last_claim"] = "2026-10-24"

	var merged: Dictionary = PlayerProfile.merge(loaded, cloud)
	check(merged["camp"]["level"] == 3 and merged["camp"]["coins"] == 400, "merge takes higher camp level and coins")
	check(int(merged["camp"]["last_collect"]) == 20000, "merge takes later last_collect")
	check(merged["calendar"]["claimed_days"] == 10 and merged["calendar"]["last_claim"] == "2026-10-24", "merge takes higher calendar days and later claim date")
