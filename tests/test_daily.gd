extends SceneTree
## The daily challenge: the level, seed and modifiers follow from the UTC date alone,
## the day changes exactly at UTC midnight, the record book keeps the best wave, the
## streak of days in a row and a bonus star that cannot be farmed.
## godot --headless --path . --script res://tests/test_daily.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_daily.cfg"
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path + suffix))
	_run.call_deferred()


func _unix(text: String) -> int:
	return int(Time.get_unix_time_from_datetime_string(text))


func _run() -> void:
	_check_dates()
	_check_determinism()
	_check_data()
	_check_record_book()
	_check_profile()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _check_dates() -> void:
	check(
		Daily.key_for(_unix("2026-10-14T23:59:59")) == "2026-10-14", "23:59:59 UTC is still today"
	)
	check(
		Daily.key_for(_unix("2026-10-15T00:00:00")) == "2026-10-15", "00:00:00 UTC is the next day"
	)
	check(Daily.key_for(_unix("2026-12-31T23:59:59") + 1) == "2027-01-01", "year change")
	check(Daily.key_for(_unix("2028-02-28T23:59:59") + 1) == "2028-02-29", "leap day exists")
	check(Daily.key_for(_unix("2027-02-28T23:59:59") + 1) == "2027-03-01", "no leap day in 2027")
	check(Daily.is_valid_key("2026-10-15"), "valid key")
	for bad in [
		"", "2026-10-5", "2027-02-29", "2026-13-01", "26-10-15", "abcd-ef-gh", "2026/10/15"
	]:
		check(not Daily.is_valid_key(bad), "invalid key '%s'" % bad)
	check(
		Daily.day_index("2026-10-15") == Daily.day_index("2026-10-14") + 1, "day index counts days"
	)
	check(Daily.yesterday_key("2026-03-01") == "2026-02-28", "yesterday over a month end")
	check(Daily.yesterday_key("2028-03-01") == "2028-02-29", "yesterday over a leap day")
	check(Daily.today_key() == Daily.key_for(int(Time.get_unix_time_from_system())), "today key")


func _check_determinism() -> void:
	# The same date gives the same trial, however often it is asked.
	for key in ["2026-10-15", "2026-11-02", "2027-01-01"]:
		var first := [Daily.level_for(key), Daily.seed_for(key), Daily.preset_for(key)["id"]]
		Daily._data = {}  # reload the data file: the answer must not depend on a cache
		var second := [Daily.level_for(key), Daily.seed_for(key), Daily.preset_for(key)["id"]]
		check(first == second, "%s: level, seed and preset are stable %s" % [key, first])
	# Golden values: they must never change (a change rewrites the past days).
	var h: int = Daily.hash_text("seed:2026-10-15")
	check(h == Daily.hash_text("seed:2026-10-15") and h > 0 and h <= 0xFFFFFFFF, "hash is 32 bit")
	check(Daily.fnv1a("") == 2166136261, "FNV-1a of the empty text is its basis")
	check(Daily.fnv1a("a") == 0xE40C292C, "FNV-1a of 'a' (reference value)")
	check(Daily.seed_for("2026-10-15") == (Daily.hash_text("seed:2026-10-15") & 0x7FFFFFFF), "seed")
	var golden := [
		["2026-10-15", 3, 118934415, "iron_hide"],
		["2026-10-16", 3, 206781533, "archers_frost"],
		["2026-10-17", 4, 1199552166, "tough_rich"],
		["2027-01-01", 1, 1326841045, "iron_hide"],
	]
	for row: Array in golden:
		var got := [Daily.level_for(row[0]), Daily.seed_for(row[0]), Daily.preset_for(row[0])["id"]]
		check(got == row.slice(1), "%s: golden level, seed, preset %s" % [row[0], got])
	var levels: Dictionary = {}
	var seeds: Dictionary = {}
	var presets: Dictionary = {}
	var base: int = Daily.day_index("2026-10-15")
	var consecutive_equal := false
	var in_range := true
	var prev: String = ""
	for i in 60:
		var key: String = Daily.key_of_day(base + i)
		levels[Daily.level_for(key)] = true
		seeds[Daily.seed_for(key)] = true
		var id: String = str(Daily.preset_for(key)["id"])
		presets[id] = true
		consecutive_equal = consecutive_equal or id == prev
		prev = id
		in_range = in_range and Daily.seed_for(key) >= 0 and Daily.seed_for(key) <= 0x7FFFFFFF
	check(in_range, "seeds fit 31 bits")
	check(levels.size() >= 4, "60 days visit most levels (%d)" % levels.size())
	check(seeds.size() == 60, "every day has its own seed")
	check(presets.size() == Daily.data()["presets"].size(), "every preset comes up")
	check(not consecutive_equal, "two days in a row never share a preset")
	for level_id: Variant in levels:
		check(not LevelCatalog.get_level(int(level_id)).is_empty(), "level %s exists" % level_id)


func _check_data() -> void:
	var tower_ids: Array[String] = []
	for file in DirAccess.get_files_at("res://resources/towers"):
		if file.ends_with(".tres"):
			tower_ids.append(file.get_basename())
	var csv: String = FileAccess.get_file_as_string("res://translations/strings.csv")
	for preset: Dictionary in Daily.data()["presets"]:
		var id: String = str(preset["id"])
		check(
			float(preset["hp_mult"]) > 0.0 and float(preset["reward_mult"]) > 0.0,
			"%s: multipliers" % id
		)
		check(float(preset["wave_duration_mult"]) >= 0.5, "%s: waves not absurdly fast" % id)
		for name: Variant in preset["towers"]:
			check(str(name) in tower_ids, "%s: tower '%s' exists" % [id, name])
		check(
			csv.contains(str(preset["key"]) + ",") and csv.contains(str(preset["key"]) + "_DESC,"),
			"%s: name and description are translated" % id
		)
	check(Daily.star_wave() >= 5 and Daily.max_stars() <= 10, "bonus stars are limited")


func _check_record_book() -> void:
	var d1 := "2026-10-15"
	check(Daily.best_wave(d1) == 0 and Daily.streak() == 0, "empty book")
	var r: Dictionary = Daily.record_result(d1, 4, 130)
	check(
		r["new_best"] and r["streak"] == 1 and not r["star"], "first run: best, streak 1, no star"
	)
	check(Daily.best_wave(d1) == 4 and Daily.best_time(d1) == 130, "best wave and time stored")
	r = Daily.record_result(d1, 3, 100)
	check(not r["new_best"] and Daily.best_wave(d1) == 4, "a worse run keeps the best")
	check(
		r["streak"] == 1 and Daily.days_played() == 1, "a second run the same day is not a new day"
	)
	r = Daily.record_result(d1, 4, 90)
	check(
		not r["new_best"] and Daily.best_time(d1) == 90,
		"the same wave faster improves the time only"
	)
	r = Daily.record_result(d1, Daily.star_wave(), 400)
	check(
		r["new_best"] and r["star"] and Daily.bonus_stars() == 1,
		"reaching the star wave gives a star"
	)
	r = Daily.record_result(d1, Daily.star_wave() + 5, 600)
	check(not r["star"] and Daily.bonus_stars() == 1, "no second star the same day")
	check(Daily.best_wave_ever() == Daily.star_wave() + 5, "best wave ever")
	# Streak: next day continues, a gap restarts, the best is kept.
	check(Daily.live_streak("2026-10-16") == 1, "the streak is still alive the next day")
	check(Daily.live_streak("2026-10-17") == 0, "...and has run out two days later")
	r = Daily.record_result("2026-10-16", 2, 60)
	check(r["streak"] == 2, "the next day: streak 2")
	r = Daily.record_result("2026-10-17", 2, 60)
	check(r["streak"] == 3 and Daily.best_streak() == 3, "streak 3")
	r = Daily.record_result("2026-10-20", 2, 60)
	check(r["streak"] == 1 and Daily.best_streak() == 3, "a gap restarts the streak, best stays 3")
	check(Daily.days_played() == 4, "days played")
	# Month and year borders.
	Daily.record_result("2026-12-31", 1, 10)
	r = Daily.record_result("2027-01-01", 1, 10)
	check(r["streak"] == 2, "the streak crosses the new year")
	# A run without a wave or on a broken key counts for nothing.
	var before: int = Daily.days_played()
	Daily.record_result("2027-01-02", 0, 10)
	Daily.record_result("nonsense", 5, 10)
	check(Daily.days_played() == before, "no wave / bad key: nothing recorded")
	# The star cap: no farming of stars over many days.
	var base: int = Daily.day_index("2027-02-01")
	for i in 30:
		Daily.record_result(Daily.key_of_day(base + i), Daily.star_wave(), 100)
	check(
		Daily.bonus_stars() == Daily.max_stars(), "stars stop at the cap (%d)" % Daily.bonus_stars()
	)
	check(Perks.earned_stars() == Daily.max_stars(), "the stars count in the treasury")
	check(
		Perks.max_stars() >= LevelCatalog.levels().size() * 8 + Daily.max_stars(),
		"maximum includes the cap"
	)
	# Old days are pruned, the lifetime numbers stay.
	check(
		Daily.best_wave("2026-10-15") == 0,
		"results older than %d days are pruned" % Daily.KEEP_DAYS
	)
	check(Daily.best_wave_ever() >= Daily.star_wave() + 5, "lifetime best survives pruning")
	# The save file survives a reload.
	LevelCatalog._save = null
	check(
		Daily.bonus_stars() == Daily.max_stars() and Daily.best_streak() >= 3, "persisted to disk"
	)


func _check_profile() -> void:
	# The bonus stars and the achievements travel with the profile.
	var p: Dictionary = PlayerProfile.local()
	check(
		int(p["progression"]["dailyStars"]) == Daily.max_stars(), "profile carries the bonus stars"
	)
	var cloud: Dictionary = PlayerProfile.from_cloud(
		{"schemaVersion": 1, "progression": {"dailyStars": 9999}, "achievements": 0x7FFFFFFF}
	)
	check(int(cloud["progression"]["dailyStars"]) == Daily.max_stars(), "cloud stars are clamped")
	check(
		int(cloud["achievements"]) == Achievements.known_mask(), "cloud mask keeps known bits only"
	)
	var merged: Dictionary = PlayerProfile.merge(
		{
			"progression":
			{"unlocked": 1, "stars": {}, "endless": {}, "perks": {}, "dailyStars": 3},
			"achievements": 1,
			"onboardingCompleted": false,
			"tutorialVersionCompleted": 0,
			"nickname": "",
			"nicknameVerified": false,
			"nicknameNormalized": "",
			"createdAt": 0,
			"updatedAt": 0,
			"settings": {"sound": true}
		},
		{"progression": {"dailyStars": 5}, "achievements": 4}
	)
	check(int(merged["progression"]["dailyStars"]) == 5, "merge keeps the larger star count")
	check(int(merged["achievements"]) == 5, "merge unites the achievements")
