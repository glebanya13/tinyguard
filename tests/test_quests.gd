extends SceneTree
## Daily quests: the list depends on the date only, three different templates, progress
## from battle counters, a quest pays once, the day rolls over, the tracker batches.
## godot --headless --path . --script res://tests/test_quests.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_quests.cfg"
	LevelCatalog.erase_all()
	_run.call_deferred()


func _run() -> void:
	_check_lists()
	_check_progress()
	_check_tracker()
	LevelCatalog.erase_all()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _check_lists() -> void:
	var a: Array[Dictionary] = Quests.for_day("2026-10-17")
	check(a.size() == 3, "3 quests a day")
	check(a == Quests.for_day("2026-10-17"), "the same day, the same list")
	var distinct := true
	var ids := {}
	for def in a:
		ids[def["id"]] = true
	distinct = ids.size() == a.size()
	check(distinct, "the three quests are different kinds")
	var varied := {}
	for d in 60:
		var day: String = Daily.key_of_day(Daily.day_index("2026-10-01") + d)
		var list: Array[Dictionary] = Quests.for_day(day)
		var sig: Array = list.map(
			func(q: Dictionary) -> String: return "%s%d" % [q["id"], q["target"]]
		)
		varied[str(sig)] = true
		for q in list:
			var csv: String = FileAccess.get_file_as_string("res://translations/strings.csv")
			if not csv.contains("\n" + str(q["key"]) + ","):
				check(false, "quest text %s is translated" % q["key"])
	check(
		varied.size() > 15,
		"the list changes from day to day (%d variants in 60 days)" % varied.size()
	)
	var rewards: Array = Wallet.data()["quests"]["rewards"]
	check(
		a[0]["reward"] == rewards[0] and a[2]["reward"] == rewards[2],
		"rewards come from economy.json"
	)
	for q in a:
		check(int(q["target"]) > 0 and Quests.text(q) != "", "quest text: " + Quests.text(q))


func _check_progress() -> void:
	var day: String = "2026-10-17"
	var defs: Array[Dictionary] = Quests.for_day(day)
	check(Quests.progress(day).is_empty(), "no progress on a new day")
	# Give every metric far more than any target: all three quests finish at once.
	var done: Array[Dictionary] = Quests.add(
		day, {"kills": 1000, "towers": 1000, "upgrades": 1000, "wave": 1000}
	)
	check(done.size() == 3, "three quests finish")
	var paid: int = 0
	for item in done:
		paid += int(item["gems"])
	var expected: int = 0
	for q in defs:
		expected += int(q["reward"])
	check(paid == expected, "they pay their rewards (%d)" % paid)
	check(Economy.balance() == expected, "the wallet has the gems")
	check(Quests.add(day, {"kills": 5}).is_empty(), "a finished quest does not pay again")
	check(Quests.is_done(day, defs[0]), "reported done")
	# The same quests again from another device's wallet: the claim exists, so nothing more.
	var other: Dictionary = Wallet.local()
	check(Wallet.has_claim(other, "q:%s:0" % day), "the claim key is recorded")
	# A new day starts from zero.
	var next: String = "2026-10-18"
	check(Quests.progress(next).is_empty(), "the next day has no progress")
	var part: Array[Dictionary] = Quests.add(next, {"kills": 1})
	check(
		(
			part.is_empty()
			or Quests.for_day(next).any(
				func(q: Dictionary) -> bool: return q["metric"] == "kills" and int(q["target"]) <= 1
			)
		),
		"one kill does not finish a quest"
	)
	check(Quests.progress(next).get("kills", -1) in [1, -1], "progress restarted")
	# Wave counts the highest wave, other metrics add up.
	var d3: String = "2026-10-19"
	Quests.add(d3, {"wave": 5})
	Quests.add(d3, {"wave": 3})
	var metrics: Array = Quests.for_day(d3).map(func(q: Dictionary) -> String: return q["metric"])
	if metrics.has("wave"):
		check(int(Quests.progress(d3)["wave"]) == 5, "wave keeps the maximum")
	Quests.add(d3, {"kills": 4})
	Quests.add(d3, {"kills": 6})
	if metrics.has("kills"):
		check(int(Quests.progress(d3)["kills"]) == 10, "kills add up")
	check(
		Economy.award_quest("2026-10-17", 7) == 0 and Economy.award_quest("bad", 0) == 0,
		"bad quest slot or day pays nothing"
	)


func _check_tracker() -> void:
	var tracker := QuestTracker.new()
	root.add_child(tracker)
	var finished: Array = []
	tracker.quest_done.connect(
		func(def: Dictionary, gems: int) -> void: finished.append([def, gems])
	)
	var day: String = Daily.today_key()
	var defs: Array[Dictionary] = Quests.for_day(day)
	for i in 400:
		tracker._count("kills")
	for i in 40:
		tracker._count("towers")
		tracker._count("upgrades")
	tracker._on_wave_cleared(30)
	var want: int = 0
	for q in defs:
		want += 1 if q["metric"] in ["kills", "towers", "upgrades", "wave"] else 0
	check(finished.size() == want, "the tracker finished %d quests" % finished.size())
	tracker._on_wave_cleared(31)
	check(finished.size() == want, "and nothing twice")
	tracker.queue_free()
