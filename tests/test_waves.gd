extends SceneTree
## Wave line-ups from the level data: counts, health growth, unlocks, bosses,
## endless siege. Uses only WavePlan's public interface and resources/levels.json.
## godot --headless --path . --script res://tests/test_waves.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	for level: Dictionary in LevelCatalog.levels():
		_check_level(level)
	_check_endless(LevelCatalog.levels()[0])
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _bosses(list: Array[Dictionary]) -> int:
	var n := 0
	for s in list:
		if (s["data"] as EnemyData).is_boss:
			n += 1
	return n


func _check_level(level: Dictionary) -> void:
	var id: int = int(level["id"])
	var waves: Dictionary = level["waves"]
	var plan := WavePlan.new(waves)
	var total: int = plan.wave_count
	check(total == int(waves["count"]) and not plan.endless, "level %d: wave count" % id)
	var ok_counts := true
	var ok_hp := true
	var ok_boss := true
	var ok_order := true
	var last_hp: float = 0.0
	for w in range(1, total + 1):
		var list: Array[Dictionary] = plan.spawns(w)
		var base: float = float(waves["count_base"]) + float(waves["count_step"]) * (w - 1)
		var bosses: int = _bosses(list)
		var elites: int = 0
		for entry in list:
			elites += 1 if entry.get("elite", false) else 0
		if list.size() - bosses - elites != roundi(base):
			ok_counts = false
		var hp: float = plan.health_factor(w)
		if hp <= last_hp:
			ok_hp = false
		last_hp = hp
		var boss_wave: bool = w % int(waves["boss_every"]) == 0
		boss_wave = boss_wave or (bool(waves["boss_last"]) and w == total)
		if (bosses > 0) != boss_wave or plan.is_boss_wave(w) != boss_wave:
			ok_boss = false
		if boss_wave and bosses != 1 + floori(w / 30.0):
			ok_boss = false
		for i in list.size():
			var is_boss: bool = (list[i]["data"] as EnemyData).is_boss
			if is_boss and i < list.size() - bosses:
				ok_order = false  # bosses close the wave
			# (below factor 1 the boss exponent works the other way round: no check there)
			if (
				is_boss
				and hp >= 1.0
				and float(list[i]["hp"]) > hp * float(waves.get("boss_hp_mult", 1.0)) + 0.0001
			):
				ok_boss = false  # bosses grow slower than the crowd
	check(ok_counts, "level %d: enemies per wave follow count_base + step" % id)
	check(ok_hp, "level %d: health factor grows every wave" % id)
	check(ok_boss, "level %d: bosses only on boss waves, 1 + wave/30 of them" % id)
	check(ok_order, "level %d: bosses come last in the wave" % id)
	check(_same(plan, 5), "level %d: the line-up is deterministic" % id)
	_check_unlocks(id, waves, plan, total)


func _same(plan: WavePlan, wave: int) -> bool:
	var a: Array[Dictionary] = plan.spawns(wave)
	var b: Array[Dictionary] = plan.spawns(wave)
	for i in a.size():
		if a[i]["data"] != b[i]["data"] or a[i]["hp"] != b[i]["hp"]:
			return false
	return a.size() == b.size()


## A kind never appears before its "<kind>_from" wave; the fast slime shows up on it.
func _check_unlocks(id: int, waves: Dictionary, plan: WavePlan, total: int) -> void:
	var names := {
		"golem_from": "stone_golem",
		"tank_from": "slime_tank",
		"shield_from": "slime_shield",
		"healer_from": "slime_healer",
		"splitter_from": "slime_splitter",
		"bat_from": "slime_bat",
		"fast_from": "slime_fast",
	}
	var early_ok := true
	for key: String in names:
		var data: EnemyData = load("res://resources/enemies/%s.tres" % names[key])
		var from: int = int(waves.get(key, WavePlan.NEVER))
		for w in range(1, mini(from, total + 1)):
			for s in plan.spawns(w):
				if s["data"] == data:
					early_ok = false
		if key == "fast_from" and from <= total:
			var seen := false
			for s in plan.spawns(from):
				if s["data"] == data:
					seen = true
			check(seen, "level %d: fast slimes appear on wave %d" % [id, from])
	check(early_ok, "level %d: no kind before its unlock wave" % id)
	var plain := load("res://resources/enemies/slime.tres") as EnemyData
	var has_plain := false
	for s in plan.spawns(1):
		if s["data"] == plain:
			has_plain = true
	check(has_plain, "level %d: wave 1 has plain slimes" % id)


func _check_endless(level: Dictionary) -> void:
	var plan := WavePlan.new(level["waves"], true)
	check(
		plan.endless and plan.wave_count == WavePlan.ENDLESS_WAVES, "endless: waves never run out"
	)
	check(not plan.is_boss_wave(7), "endless: ordinary wave has no boss")
	check(
		plan.is_boss_wave(10) and not plan.is_boss_wave(WavePlan.ENDLESS_WAVES),
		"endless: boss every boss_every waves, no extra last boss"
	)
	check(_bosses(plan.spawns(60)) == 3, "endless: wave 60 has three bosses")
	check(
		(
			plan.spawns(50).size() > plan.spawns(10).size()
			and plan.health_factor(50) > plan.health_factor(10)
		),
		"endless: waves keep growing"
	)
