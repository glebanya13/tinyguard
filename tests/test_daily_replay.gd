extends SceneTree
## The daily challenge battle is reproducible: a bot plays the trial of three different
## days (three presets), the journal is recorded, and two replays of it with other frame
## times give the same state hashes. The day's modifiers hold (forbidden towers cannot
## be built, rewards and health are scaled) and are part of what a journal reproduces.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_daily_replay.gd

const TOTAL_TICKS := 1500
const HASH_EVERY := 30
const PRESETS: Array[String] = ["archers_frost", "tough_rich", "fast_waves"]

var fails := 0
var _trace: Array[int] = []


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_daily_replay.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	node_added.connect(
		func(node: Node) -> void:
			if node is Hero:
				(node as Hero).auto_action = false
	)
	_run.call_deferred()


func _load_level(day: String) -> Node:
	paused = false
	DailyRun.select(day)
	var old_scene: Node = current_scene
	change_scene_to_file("res://scenes/main.tscn")
	var sim: Sim = null
	while sim == null:
		await process_frame
		if current_scene != null and current_scene != old_scene and current_scene.has_node("Sim"):
			sim = current_scene.get_node("Sim")
	sim.manual = true
	for i in 200:
		if sim.running:
			break
		await process_frame
	return current_scene


func _collect(sim: Sim) -> void:
	_trace.clear()
	sim.ticked.connect(
		func(t: int) -> void:
			if t % HASH_EVERY == 0:
				_trace.append(sim.state_hash())
	)


## First day on or after 2026-10-15 whose preset is `preset_id`.
func _day_with(preset_id: String) -> String:
	var base: int = Daily.day_index("2026-10-15")
	for i in 30:
		var key: String = Daily.key_of_day(base + i)
		if str(Daily.preset_for(key)["id"]) == preset_id:
			return key
	return ""


func _run() -> void:
	for preset_id in PRESETS:
		var day: String = _day_with(preset_id)
		check(day != "", "found a day with the preset %s: %s" % [preset_id, day])
		await _one_day(day, preset_id)
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _one_day(day: String, preset_id: String) -> void:
	var preset: Dictionary = Daily.preset_for(day)
	var main: Node = await _load_level(day)
	var sim: Sim = main.get_node("Sim")
	var commands: GameCommands = main.get_node("GameCommands")
	var builds: BuildManager = main.get_node("BuildManager")
	var waves: WaveManager = main.get_node("WaveManager")
	check(sim.seed_value == Daily.seed_for(day), "%s: the day's seed is used" % preset_id)
	check(main.level["id"] == Daily.level_for(day), "%s: the day's level is loaded" % preset_id)
	check(waves.plan.endless, "%s: a daily run is an endless siege" % preset_id)
	check(
		is_equal_approx(waves.plan.hp_scale, float(preset["hp_mult"])),
		"%s: health scaled" % preset_id
	)
	check(
		is_equal_approx(waves.reward_scale, float(preset["reward_mult"])),
		"%s: rewards scaled" % preset_id
	)
	check(
		(
			is_equal_approx(waves.plan.wave_duration, 30.0 * float(preset["wave_duration_mult"]))
			or main.level["waves"].has("wave_duration")
		),
		"%s: wave clock scaled" % preset_id
	)
	check(
		str(commands.journal.header.get("daily", "")) == day,
		"%s: the journal names the day" % preset_id
	)
	# Forbidden towers cannot be built, allowed ones can.
	var allowed: Array = preset["towers"]
	var refused := 0
	var accepted := 0
	for kind in builds.tower_types.size():
		var name: String = builds.tower_types[kind].resource_path.get_file().get_basename()
		var legal: bool = allowed.is_empty() or allowed.has(name)
		if not legal:
			# Gold for the test only; the tower is refused whatever the price.
			(main.get_node("GameState") as GameState).add_gold(500)
			(main.get_node("GameState") as GameState).add_wood(500)
			if commands.submit(GameCommand.build(1, kind)):
				accepted += 1
			else:
				refused += 1
	check(accepted == 0, "%s: forbidden towers are refused (%d)" % [preset_id, refused])
	# The recording is played from a fresh level.
	main = await _load_level(day)
	sim = main.get_node("Sim")
	commands = main.get_node("GameCommands")
	builds = main.get_node("BuildManager")
	_collect(sim)
	var last_bot: int = -1
	while sim.tick < TOTAL_TICKS:
		if sim.tick != last_bot and sim.tick % 5 == 0:
			last_bot = sim.tick
			_bot(sim, commands, builds, main.get_node("GameState"), main.get_node("Level/Hero"))
		sim.advance(1.0 / 60.0)
		await process_frame
	var recorded: Array[int] = _trace.duplicate()
	var journal: CommandLog = commands.journal
	var kinds := {}
	for tower in sim.towers:
		kinds[tower.data.resource_path.get_file().get_basename()] = true
	var only_allowed := true
	for name: String in kinds:
		only_allowed = only_allowed and (allowed.is_empty() or allowed.has(name))
	check(
		sim.towers.size() > 0 and only_allowed,
		"%s: the bot built only allowed towers %s" % [preset_id, kinds.keys()]
	)
	check(
		journal.commands.size() >= 8,
		"%s: %d commands recorded" % [preset_id, journal.commands.size()]
	)
	check(recorded.size() == TOTAL_TICKS / HASH_EVERY, "%s: hashes recorded" % preset_id)
	var loaded := CommandLog.from_json(journal.to_json())
	check(str(loaded.header.get("daily", "")) == day, "%s: the day survives JSON" % preset_id)
	for variant in ["jitter", "10fps"]:
		var other: Node = await _load_level(day)
		var sim2: Sim = other.get_node("Sim")
		_collect(sim2)
		sim2.begin_replay(loaded)
		var jitter := RandomNumberGenerator.new()
		jitter.seed = 99
		while sim2.tick < TOTAL_TICKS:
			sim2.advance(0.1 if variant == "10fps" else jitter.randf_range(0.003, 0.19))
			await process_frame
		var same := 0
		for i in mini(recorded.size(), _trace.size()):
			if recorded[i] == _trace[i]:
				same += 1
		check(
			same == recorded.size() and _trace.size() >= recorded.size(),
			"%s: %s replay: %d/%d hashes equal" % [preset_id, variant, same, recorded.size()]
		)
	# A journal of another day diverges (the modifiers are part of the battle).
	var wrong := CommandLog.from_json(journal.to_json())
	wrong.header["daily"] = _day_with("tough_rich" if preset_id != "tough_rich" else "fast_waves")
	var third: Node = await _load_level(day)
	var sim3: Sim = third.get_node("Sim")
	_collect(sim3)
	sim3.begin_replay(wrong)
	while sim3.tick < TOTAL_TICKS:
		sim3.advance(0.1)
		await process_frame
	var diverged := false
	for i in mini(recorded.size(), _trace.size()):
		diverged = diverged or recorded[i] != _trace[i]
	check(diverged, "%s: a journal that names another day's modifiers diverges" % preset_id)


## Plays the allowed towers only: build on free slots, upgrade now and then.
func _bot(
	sim: Sim, commands: GameCommands, builds: BuildManager, state: GameState, hero: Hero
) -> void:
	var t: int = sim.tick
	if state.wood < 80:
		for tree in sim.trees:
			if tree.is_choppable():
				var origin: Vector3 = tree.global_position + Vector3(1.0, 0.0, 0.0)
				commands.submit(GameCommand.hero_attack(origin, -PI / 2.0))
				break
	if not sim.enemies.is_empty() and hero.spin_cooldown_left() <= 0.0:
		commands.submit(GameCommand.hero_spin(sim.enemies[0].sim_position()))
	if t % 10 != 0:
		return
	if t % 90 == 0 and state.wood >= 40:
		commands.submit(GameCommand.trade(1))
	for slot in commands.slots:
		var kind: int = slot.slot_id % builds.tower_types.size()
		for step in builds.tower_types.size():
			var index: int = (kind + step) % builds.tower_types.size()
			if slot.is_free() and builds.can_build(slot, builds.tower_types[index]):
				commands.submit(GameCommand.build(slot.slot_id, index))
				return
		if not slot.is_free() and t % 60 == 0 and builds.can_upgrade(slot):
			commands.submit(GameCommand.upgrade(slot.slot_id))
			return
