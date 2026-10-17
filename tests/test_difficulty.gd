extends SceneTree
## Difficulty multipliers, the Record Run's wave growth (monotone, finite up to wave 500),
## difficulty crowns in the save and the profile (schema 2 migration, cloud clamp).
## godot --headless --path . --script res://tests/test_difficulty.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_difficulty.cfg"
	LevelCatalog.erase_all()
	_check_multipliers()
	_check_record_growth()
	_check_crowns()
	_check_profile()
	LevelCatalog.erase_all()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _count(list: Array[Dictionary]) -> int:
	return list.size()


func _check_multipliers() -> void:
	check(Balance.difficulty_count() == 3, "three difficulties")
	var level: Dictionary = LevelCatalog.get_level(3)
	var normal := WavePlan.new(level["waves"])
	var last_hp: float = 0.0
	var last_count: int = 0
	for i in Balance.difficulty_count():
		var plan := WavePlan.new(level["waves"])
		plan.set_difficulty(i)
		var row: Dictionary = Balance.difficulty(i)
		check(
			is_equal_approx(plan.health_factor(10), normal.health_factor(10) * float(row["hp"])),
			"difficulty %d: health x%s" % [i, row["hp"]]
		)
		check(plan.difficulty == i, "difficulty %d is remembered" % i)
		var n: int = _count(plan.spawns(12))
		check(n >= last_count, "difficulty %d: no fewer enemies (%d)" % [i, n])
		check(plan.health_factor(10) >= last_hp, "difficulty %d: no weaker enemies" % i)
		last_hp = plan.health_factor(10)
		last_count = n
	var hard := WavePlan.new(level["waves"])
	hard.set_difficulty(2)
	check(_count(hard.spawns(20)) > _count(normal.spawns(20)), "Nightmare sends more enemies at 20")
	var lives_hard: float = float(Balance.difficulty(2)["lives"])
	check(lives_hard < 1.0 and float(Balance.difficulty(0)["lives"]) == 1.0, "castle lives shrink")
	check(
		is_equal_approx(
			normal.reward_scale(0), 1.0 * float(level["waves"].get("reward_mult", 1.0))
		),
		"Normal reward is the level's"
	)
	check(normal.reward_scale(2) < normal.reward_scale(0), "Nightmare pays less")
	# Out-of-range indexes are clamped, never crash.
	check(Balance.difficulty(99) == Balance.difficulty(2), "difficulty index is clamped")


func _check_record_growth() -> void:
	for level: Dictionary in LevelCatalog.levels():
		var plan := WavePlan.new(level["waves"], true, true)
		var id: int = int(level["id"])
		check(plan.record_run and plan.endless, "level %d: record plan" % id)
		var last_hp: float = 0.0
		var ok_hp := true
		var ok_finite := true
		var ok_count := true
		var surprises := 0
		var bosses := 0
		var last_boss_gap: int = 1000
		var last_boss: int = 0
		var biggest_boss_gap: int = 0
		var kinds := {}
		for w in range(1, 501):
			var hp: float = plan.health_factor(w)
			if hp < last_hp or (hp == last_hp and w < 300):
				ok_hp = false
			last_hp = hp
			if not is_finite(hp) or hp <= 0.0:
				ok_finite = false
			var list: Array[Dictionary] = plan.spawns(w)
			if list.is_empty() or list.size() > 200:
				ok_count = false
			for entry in list:
				if not is_finite(float(entry["hp"])):
					ok_finite = false
				kinds[(entry["data"] as EnemyData).resource_path] = true
			if not plan.surprise_key(w).is_empty():
				surprises += 1
			if plan.is_boss_wave(w):
				bosses += 1
				if last_boss > 0 and w < 150:
					biggest_boss_gap = maxi(biggest_boss_gap, w - last_boss)
					last_boss_gap = mini(last_boss_gap, w - last_boss)
				last_boss = w
		check(ok_hp, "level %d: record health never falls (strictly up to 300)" % id)
		check(ok_finite, "level %d: no overflow up to wave 500" % id)
		check(ok_count, "level %d: wave sizes stay sane (<= 200)" % id)
		check(surprises > 40, "level %d: surprise waves on schedule (%d)" % [id, surprises])
		check(kinds.size() >= 8, "level %d: all enemy kinds appear (%d)" % [id, kinds.size()])
		check(biggest_boss_gap <= 10, "level %d: bosses at least every 10 waves" % id)
		check(last_boss_gap <= 6, "level %d: bosses get more frequent" % id)
		check(plan.spawns(40).size() > plan.spawns(2).size(), "level %d: waves grow" % id)
		check(plan.window_for(5) < plan.window_for(40), "level %d: spawn window stretches" % id)
		check(
			plan.window_for(80) <= plan.wave_duration + 0.001, "level %d: no gap between waves" % id
		)
		check(plan.wave_count == WavePlan.ENDLESS_WAVES and not plan.is_elite_wave(1), "endless")


func _check_crowns() -> void:
	check(LevelCatalog.crown(1) == 0, "no crown at the start")
	check(LevelCatalog.is_difficulty_open(1, 0), "Normal is always open")
	check(not LevelCatalog.is_difficulty_open(1, 1), "Hard is locked before a win")
	LevelCatalog.complete(1, 2, 0)
	check(LevelCatalog.is_difficulty_open(1, 1), "Hard opens after a win")
	check(not LevelCatalog.is_difficulty_open(1, 2), "Nightmare needs a Hard win")
	LevelCatalog.complete(1, 1, 1)
	check(LevelCatalog.crown(1) == 1 and LevelCatalog.stars(1) == 2, "Hard crown, stars kept")
	check(LevelCatalog.is_difficulty_open(1, 2), "Nightmare opens after Hard")
	LevelCatalog.complete(1, 3, 2)
	LevelCatalog.complete(1, 3, 1)
	check(LevelCatalog.crown(1) == 2, "the crown only goes up")
	check(LevelCatalog.stars(1) == 3, "stars from a harder win count")


func _check_profile() -> void:
	var p: Dictionary = PlayerProfile.local()
	check(int(p["schemaVersion"]) == PlayerProfile.SCHEMA_VERSION, "current schema")
	check(p["progression"]["crowns"] == {"1": 2}, "crown is in the profile")
	# An old (schema 1) profile without crowns migrates.
	var old: Dictionary = PlayerProfile.empty()
	old["schemaVersion"] = 1
	(old["progression"] as Dictionary).erase("crowns")
	var migrated: Dictionary = PlayerProfile.migrate(old)
	check(int(migrated["schemaVersion"]) == PlayerProfile.SCHEMA_VERSION, "schema 1 migrates")
	check(migrated["progression"].get("crowns") == {}, "migration adds crowns")
	# The cloud is not trusted.
	var cloud: Dictionary = PlayerProfile.from_cloud(
		{"schemaVersion": 2, "progression": {"crowns": {"1": 9, "2": -3, "3": 1}}}
	)
	var crowns: Dictionary = cloud["progression"]["crowns"]
	check(int(crowns["1"]) == 2 and int(crowns["2"]) == 0 and int(crowns["3"]) == 1, "clamped")
	# Merge keeps the higher crown.
	var local: Dictionary = PlayerProfile.empty()
	local["progression"]["crowns"] = {"1": 1, "2": 2}
	var merged: Dictionary = PlayerProfile.merge(local, cloud)
	var mc: Dictionary = merged["progression"]["crowns"]
	check(int(mc["1"]) == 2 and int(mc["2"]) == 2 and int(mc["3"]) == 1, "merge takes the max")
	# Round trip through the save file.
	var cfg := ConfigFile.new()
	PlayerProfile.write_to_save(merged, cfg)
	var back: Dictionary = PlayerProfile.from_save(cfg)
	check(int(back["progression"]["crowns"]["3"]) == 1, "crowns survive the save file")
