extends SceneTree
## Validation of hero commands (co-op): a position outside the map or one the
## knight could not have reached since his previous command is refused, the same
## way on every client and in a replay of the journal.
## LEVEL=<id> godot --headless --fixed-fps 60 --path . --script \
##   res://tests/test_command_validation.gd

var fails := 0
var _level: int = 1
var _hash_a: int = 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_validation.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	node_added.connect(
		func(node: Node) -> void:
			if node is Hero:
				(node as Hero).auto_action = false
	)
	_level = int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	LevelCatalog.selected_id = _level
	_run.call_deferred()


func _load_level() -> Node:
	for i in 3:
		await process_frame  # let effects of the previous level finish
	paused = false
	var old_scene: Node = current_scene
	change_scene_to_file("res://scenes/main.tscn")
	var sim: Sim = null
	while sim == null:
		await process_frame
		if current_scene != null and current_scene != old_scene and current_scene.has_node("Sim"):
			sim = current_scene.get_node("Sim")
	sim.manual = true
	sim.set_seed(12345)  # the battle seed is part of the hash
	for i in 200:
		if sim.running:
			break
		await process_frame
	return current_scene


## Runs `steps` simulation steps, then returns.
func _steps(sim: Sim, steps: int) -> void:
	for i in steps:
		sim.step()


func _run() -> void:
	var main: Node = await _load_level()
	var sim: Sim = main.get_node("Sim")
	var commands: GameCommands = main.get_node("GameCommands")
	commands.validate_hero = true
	var start := Vector3(main.level["hero"][0], 0.0, main.level["hero"][1])
	var b: Array = main.level["bounds"]
	var rect := Rect2(b[0], b[1], b[2], b[3])
	var far := Vector3(rect.position.x + 1.0, 0.0, rect.position.y + 1.0)
	if (
		far.distance_to(start)
		< Vector3(rect.get_center().x, 0.0, rect.get_center().y).distance_to(start)
	):
		far = Vector3(rect.end.x - 1.0, 0.0, rect.end.y - 1.0)
	check(far.distance_to(start) > 15.0, "a far corner exists (%.1f m)" % far.distance_to(start))

	var plan: Array = [
		[0, start + Vector3(0.5, 0, 0), true],  # next to the start
		[20, far, false],  # too far for 20 steps (0.7 s)
		[20, Vector3(2000.0, 0.0, 0.0), false],  # outside the map
		[40, start + Vector3(3.0, 0, 0), true],  # a short walk
		[100, far, false],  # still too far for 60 steps
		[1500, far, true],  # enough time (50 s) to get there
	]
	var verdicts: Array[bool] = _play(sim, commands, plan)
	var expected: Array[bool] = []
	for row in plan:
		expected.append(row[2])
	check(verdicts == expected, "verdicts %s == %s" % [verdicts, expected])
	_hash_a = sim.state_hash()
	var total_ticks: int = sim.tick
	var journal: CommandLog = commands.journal
	check(
		journal.commands.size() == 3,
		"only accepted commands are journaled (%d)" % journal.commands.size()
	)

	# The same attempts on a fresh level give the same verdicts and state.
	var main2: Node = await _load_level()
	var sim2: Sim = main2.get_node("Sim")
	var commands2: GameCommands = main2.get_node("GameCommands")
	commands2.validate_hero = true
	var verdicts2: Array[bool] = _play(sim2, commands2, plan)
	check(
		verdicts2 == verdicts and sim2.state_hash() == _hash_a,
		"second client: same verdicts and hash"
	)

	# The journal replays to the same hash with validation on.
	var main3: Node = await _load_level()
	var sim3: Sim = main3.get_node("Sim")
	(main3.get_node("GameCommands") as GameCommands).validate_hero = true
	var copy := CommandLog.from_json(journal.to_json())
	copy.header["seed"] = 12345  # the seed this test gave to the recording
	sim3.begin_replay(copy)
	_steps(sim3, total_ticks)
	check(sim3.state_hash() == _hash_a, "journal replay: same hash")

	# Validation off (single player): everything is accepted.
	var main4: Node = await _load_level()
	var commands4: GameCommands = main4.get_node("GameCommands")
	var verdicts4: Array[bool] = _play(main4.get_node("Sim"), commands4, plan)
	check(
		verdicts4.count(true) == plan.size() - 1,
		"validation off: only the cooldown refuses (%s)" % [verdicts4]
	)

	await _swift_perk(start)

	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


## The perk "swift feet" (+18 % speed): the validator reads the hero's real speed, so a run
## that is possible only with the perk is accepted with it and refused without it, and a
## replay of the journal (its header carries the perk) judges the same way.
func _swift_perk(start: Vector3) -> void:
	var seconds: int = 10
	var base_limit: float = 3.2 * 1.5 * seconds + 1.0
	var swift_limit: float = 3.2 * 1.18 * 1.5 * seconds + 1.0
	var goal: Vector3 = start + Vector3(0.5 * (base_limit + swift_limit), 0.0, 0.0)
	var plan: Array = [[0, start + Vector3(0.5, 0, 0), true], [seconds * Sim.TICK_RATE, goal, true]]
	var wide := Rect2(-500.0, -500.0, 1000.0, 1000.0)
	for level in [0, 3]:
		if LevelCatalog.data().has_section("perks"):
			LevelCatalog.data().erase_section("perks")
		if level > 0:
			LevelCatalog.data().set_value("perks", "swift", level)
		var main: Node = await _load_level()
		var commands: GameCommands = main.get_node("GameCommands")
		var sim: Sim = main.get_node("Sim")
		commands.validate_hero = true
		commands.set_hero_limits(start, wide)
		var verdicts: Array[bool] = _play(sim, commands, plan)
		var accepted: bool = level > 0
		var run: String = "%.0f m in %d s" % [goal.distance_to(start), seconds]
		check(
			verdicts == [true, accepted],
			(
				"swift level %d: a run of %s is %s %s"
				% [level, run, "accepted" if accepted else "refused", verdicts]
			)
		)
		if level == 0:
			continue
		# The journal carries the perk: a replay judges the same way.
		var copy := CommandLog.from_json(commands.journal.to_json())
		copy.header["seed"] = 12345
		var recorded: int = sim.state_hash()
		var total: int = sim.tick
		var again: Node = await _load_level()
		var commands2: GameCommands = again.get_node("GameCommands")
		commands2.validate_hero = true
		commands2.set_hero_limits(start, wide)
		var sim2: Sim = again.get_node("Sim")
		sim2.begin_replay(copy)
		_steps(sim2, total)
		var speed_bonus: float = (again.get("_hero") as Hero).speed_bonus
		check(is_equal_approx(speed_bonus, 0.18), "the replay applies the perk of its header")
		check(sim2.state_hash() == recorded, "the replay with the perk ends in the same hash")
	if LevelCatalog.data().has_section("perks"):
		LevelCatalog.data().erase_section("perks")


## Submits each [tick, position, expected] attempt at its tick; returns the verdicts.
func _play(sim: Sim, commands: GameCommands, plan: Array) -> Array[bool]:
	var out: Array[bool] = []
	for row in plan:
		_steps(sim, int(row[0]) - sim.tick)
		out.append(commands.submit(GameCommand.hero_attack(row[1], 0.0)))
	_steps(sim, 1500 + 10 - sim.tick)
	return out
