extends SceneTree
## The day streak: UTC day boundaries, one forgiven day per week, the 7-day reward
## cycle, merge of two devices, the save, and the reward being paid once per day.
## godot --headless --path . --script res://tests/test_streak.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_streak.cfg"
	_wipe()
	_run.call_deferred()


func _wipe() -> void:
	LevelCatalog.erase_all()


func _run() -> void:
	_check_days()
	_check_forgiveness()
	_check_rewards()
	_check_merge_and_save()
	_check_economy()
	_wipe()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _visit(state: Dictionary, day: String) -> Dictionary:
	return Streak.check_in(state, day)


func _check_days() -> void:
	var r: Dictionary = _visit(Streak.empty(), "2026-10-17")
	check(r["result"] == Streak.Result.FIRST and r["state"]["len"] == 1, "first visit: day 1")
	check(r["reward"] == Streak.reward_for(1), "first visit pays the day 1 reward")
	var again: Dictionary = _visit(r["state"], "2026-10-17")
	check(again["result"] == Streak.Result.SAME_DAY and again["reward"] == 0, "the same day: nothing")
	check(again["state"] == r["state"], "the same day changes nothing")
	var next: Dictionary = _visit(r["state"], "2026-10-18")
	check(next["result"] == Streak.Result.NEXT and next["state"]["len"] == 2, "the next day: 2")
	# UTC day boundaries: 23:59:59 and 00:00:00 are different days.
	var late: String = Daily.key_for(1792281599)  # 2026-10-17 23:59:59 UTC
	var early: String = Daily.key_for(1792281600)  # 2026-10-18 00:00:00 UTC
	check(late == "2026-10-17" and early == "2026-10-18", "UTC keys at midnight: %s %s" % [late, early])
	check(_visit(_visit(Streak.empty(), late)["state"], early)["state"]["len"] == 2, "across midnight: +1")
	# A month and a year boundary.
	var m: Dictionary = _visit(_visit(Streak.empty(), "2026-12-31")["state"], "2027-01-01")
	check(m["state"]["len"] == 2, "across the new year: +1")
	var leap: Dictionary = _visit(_visit(Streak.empty(), "2028-02-28")["state"], "2028-02-29")
	check(leap["state"]["len"] == 2, "a leap day is a day")
	# The device clock goes back: no change, no reward.
	var back: Dictionary = _visit(next["state"], "2026-10-10")
	check(back["result"] == Streak.Result.CLOCK_BACK and back["reward"] == 0 and back["state"] == next["state"], "clock back: ignored")
	check(_visit(Streak.empty(), "garbage")["reward"] == 0, "a bad date pays nothing")
	check(Streak.live_length(next["state"], "2026-10-18") == 2, "live on the day")
	check(Streak.live_length(next["state"], "2026-10-19") == 2, "live the next day")
	check(Streak.live_length(next["state"], "2026-10-20") == 2, "live after one missed day (forgiveness available)")
	check(Streak.live_length(next["state"], "2026-10-22") == 0, "dead after more")


func _check_forgiveness() -> void:
	# Epoch weeks are 7 days of the day count; 2026-10-08 .. 2026-10-14 is one of them.
	var s: Dictionary = _visit(_visit(Streak.empty(), "2026-10-09")["state"], "2026-10-10")["state"]
	var skip: Dictionary = _visit(s, "2026-10-12")  # missed the 11th
	check(skip["result"] == Streak.Result.FORGIVEN and skip["state"]["len"] == 3, "one missed day is forgiven")
	var again: Dictionary = _visit(skip["state"], "2026-10-14")  # missed the 13th, same week
	check(again["result"] == Streak.Result.RESET and again["state"]["len"] == 1, "a second miss in the same week resets")
	check(again["state"]["best"] == 3, "the best length survives a reset")
	var week_later: Dictionary = {"last": "2026-10-23", "len": 5, "best": 5, "grace": skip["state"]["grace"]}
	var w2: Dictionary = _visit(week_later, "2026-10-25")  # missed the 24th, another week
	check(w2["result"] == Streak.Result.FORGIVEN and w2["state"]["len"] == 6, "a miss in a later week is forgiven again")
	var long_gap: Dictionary = _visit(s, "2026-10-14")
	check(long_gap["result"] == Streak.Result.RESET and long_gap["state"]["len"] == 1, "3+ days away resets")


func _check_rewards() -> void:
	var rewards: Array = Streak.rewards()
	check(rewards.size() == 7, "7 rewards")
	var rising := true
	for i in 6:
		rising = rising and int(rewards[i]) < int(rewards[i + 1])
	check(rising, "rewards rise through the week, day 7 is the gift")
	check(int(rewards[6]) >= 2 * int(rewards[5]), "day 7 is a real gift")
	check(Streak.day_of_cycle(1) == 1 and Streak.day_of_cycle(7) == 7 and Streak.day_of_cycle(8) == 1, "cycle")
	check(Streak.reward_for(14) == Streak.reward_for(7), "the cycle repeats")
	var s: Dictionary = Streak.empty()
	var total: int = 0
	for d in 7:
		var r: Dictionary = _visit(s, Daily.key_of_day(Daily.day_index("2026-10-10") + d))
		s = r["state"]
		total += int(r["reward"])
	check(s["len"] == 7 and total == rewards.reduce(func(a: int, b: int) -> int: return a + b, 0), "a full week pays %d" % total)


func _check_merge_and_save() -> void:
	var a: Dictionary = {"last": "2026-10-17", "len": 3, "best": 5, "grace": 100}
	var b: Dictionary = {"last": "2026-10-18", "len": 4, "best": 4, "grace": 120}
	var m: Dictionary = Streak.merge(a, b)
	check(m["last"] == "2026-10-18" and m["len"] == 4 and m["best"] == 5 and m["grace"] == 120, "merge: later wins, best/grace grow")
	check(Streak.merge(b, a) == m, "merge is symmetric")
	check(Streak.merge(a, Streak.empty()) == Streak.sanitize(a), "merge with an empty one")
	var same: Dictionary = Streak.merge({"last": "2026-10-18", "len": 2, "best": 2, "grace": -1}, b)
	check(same["len"] == 4, "the same day: the longer")
	check(Streak.sanitize({"last": "x", "len": 9}) == Streak.empty(), "sanitize drops a bad date")
	check(Streak.sanitize({"last": "2026-10-18", "len": 99999999, "best": 1})["len"] == Streak.MAX_LEN, "sanitize clamps")
	var cfg := ConfigFile.new()
	Streak.write_to_save(a, cfg)
	check(Streak.from_save(cfg) == a, "save round trip")


func _check_economy() -> void:
	_wipe()
	var open1: Dictionary = Economy.on_app_open()
	var today: String = Daily.today_key()
	check(open1["streak"]["state"]["last"] == today and int(open1["gems"]) == Streak.reward_for(1), "first open pays day 1")
	var open2: Dictionary = Economy.on_app_open()
	check(int(open2["gems"]) == 0 and int(open2["streak"]["reward"]) == 0, "a second open the same day pays nothing")
	var balance: int = Economy.balance()
	# The same day on another device: its wallet has the claim, so merging pays nothing twice.
	var other: Dictionary = Wallet.empty()
	Wallet.claim(other, "streak:" + today, Streak.reward_for(1))
	var merged: Dictionary = Wallet.merge(Wallet.local(), other)
	check(Wallet.gems(merged) == balance, "the same day on two devices pays once")
	check(Streak.local()["len"] == 1, "the save holds the streak")
