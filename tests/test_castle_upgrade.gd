extends SceneTree
## Castle upgrade (GameCommand.UPGRADE_CASTLE): the price table, the level limit, refusal
## without resources (nothing is spent, nothing is journaled), the effect on lives (and the
## repair ceiling) and armor, leaks of heavy and light enemies, the look (one body mesh at
## any level), the forge card, the wire format, and the same command in the record run and
## the daily challenge. Replays, hashes and co-op are in test_replay / test_old_journal /
## test_coop_integration.
## LEVEL=<id> godot --headless --fixed-fps 60 --path . --script res://tests/test_castle_upgrade.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_castle_upgrade.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	_run.call_deferred()


func _run() -> void:
	_test_table()
	_test_state()
	_test_wire()
	await _test_scene(false, "")
	# The command is the same in every mode: the record run and the daily challenge.
	await _test_scene(true, "")
	await _test_scene(false, _daily_day())
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _test_table() -> void:
	print("-- table")
	var top: int = CastleUpgrades.max_level()
	check(top == 4, "four upgrades (%d)" % top)
	var rising := true
	var lives_sum: int = 0
	var previous_armor: int = 0
	for level in top:
		var cost: Vector2i = CastleUpgrades.cost(level)
		if level > 0:
			var before: Vector2i = CastleUpgrades.cost(level - 1)
			rising = rising and cost.x > before.x and cost.y > before.y
		lives_sum += CastleUpgrades.lives_bonus(level)
		rising = rising and CastleUpgrades.armor_at(level + 1) >= previous_armor
		previous_armor = CastleUpgrades.armor_at(level + 1)
	check(rising, "prices (gold and wood) rise and armor never drops")
	check(
		lives_sum >= 8 and previous_armor >= 2,
		"total +%d lives, armor %d" % [lives_sum, previous_armor]
	)
	check(CastleUpgrades.cost(top) == Vector2i(-1, -1), "no price past the last upgrade")
	check(
		CastleUpgrades.armor_at(0) == 0 and CastleUpgrades.armor_at(-3) == 0,
		"plain castle: armor 0"
	)
	check(
		CastleUpgrades.armor_at(99) == CastleUpgrades.armor_at(top),
		"armor is capped at the top level"
	)
	# Leaks: a king (5), a golem or tank (2) and a light slime (1) at every level.
	for level in range(top + 1):
		var armor: int = CastleUpgrades.armor_at(level)
		check(
			CastleUpgrades.leak_damage(1, level) == 1,
			"level %d: a light leak always costs 1" % level
		)
		check(
			(
				CastleUpgrades.leak_damage(2, level) == maxi(1, 2 - armor)
				and CastleUpgrades.leak_damage(5, level) == maxi(1, 5 - armor)
			),
			(
				"level %d: tank 2 -> %d, king 5 -> %d"
				% [
					level,
					CastleUpgrades.leak_damage(2, level),
					CastleUpgrades.leak_damage(5, level)
				]
			)
		)
	check(
		(
			CastleUpgrades.leak_damage(5, top) < CastleUpgrades.leak_damage(5, 0)
			and CastleUpgrades.leak_damage(2, top) < CastleUpgrades.leak_damage(2, 0)
		),
		"armor helps against the heavy ones"
	)


func _test_state() -> void:
	print("-- game state")
	var gs := GameState.new()
	gs.configure({"gold": 0, "wood": 0, "lives": 10})
	gs.reset()
	check(
		gs.castle_level == 0 and gs.lives == 10 and gs.starting_lives == 10,
		"plain castle: 10 lives"
	)
	check(not gs.upgrade_castle(), "refused without gold and wood")
	gs.gold = CastleUpgrades.cost(0).x
	gs.wood = CastleUpgrades.cost(0).y - 1
	check(
		not gs.upgrade_castle() and gs.gold == CastleUpgrades.cost(0).x,
		"refused with 1 wood short, nothing spent"
	)
	gs.wood = CastleUpgrades.cost(0).y
	check(gs.upgrade_castle(), "upgrade 1 bought")
	check(gs.gold == 0 and gs.wood == 0, "exact price paid (gold and wood)")
	var bonus: int = CastleUpgrades.lives_bonus(0)
	check(
		gs.castle_level == 1 and gs.lives == 10 + bonus and gs.starting_lives == 10 + bonus,
		"lives +%d, repair ceiling +%d" % [bonus, bonus]
	)
	gs.lose_lives(3)
	check(gs.lives == 10 + bonus - 3, "the added lives are real lives")
	gs.gold = 100000
	gs.wood = 100000
	for i in range(1, CastleUpgrades.max_level()):
		check(gs.upgrade_castle(), "upgrade %d bought" % (i + 1))
	check(gs.castle_level == CastleUpgrades.max_level(), "maximum level reached")
	var gold_before: int = gs.gold
	check(
		not gs.upgrade_castle() and gs.gold == gold_before,
		"past the maximum: refused, nothing spent"
	)
	check(
		gs.castle_upgrade_cost().x < 0 and not gs.can_upgrade_castle(),
		"no price and no button action at the maximum"
	)
	var before: int = gs.lives
	gs.take_leak(5)
	check(
		before - gs.lives == 5 - gs.castle_armor(),
		"a king leak takes %d (armor %d)" % [before - gs.lives, gs.castle_armor()]
	)
	before = gs.lives
	gs.take_leak(1)
	check(before - gs.lives == 1, "a light leak still takes 1")
	var dead := GameState.new()
	dead.configure({"gold": 0, "wood": 0, "lives": 1})
	dead.reset()
	dead.gold = 1000
	dead.wood = 1000
	dead.lose_lives(5)
	check(dead.is_defeated and not dead.upgrade_castle(), "a fallen castle cannot be upgraded")
	gs.reset()
	check(gs.castle_level == 0 and gs.starting_lives == 10, "reset: plain castle again")
	gs.free()
	dead.free()


func _test_wire() -> void:
	print("-- wire")
	var cmd: GameCommand = GameCommand.from_wire("castle", [], 1, 7)
	check(
		cmd != null and cmd.type == GameCommand.Type.UPGRADE_CASTLE and cmd.player == 1,
		"castle travels"
	)
	check(GameCommand.from_wire("castle", [1], 1, 7) == null, "castle with an argument is refused")
	check(CoopProtocol.is_valid_command(9, "castle", []), "the protocol knows it")
	check(
		int(GameCommand.Type.UPGRADE_CASTLE) == int(GameCommand.Type.HIRE) + 1,
		"appended after the last old command (journals store the number)"
	)
	var back: GameCommand = GameCommand.from_array(GameCommand.upgrade_castle().to_array())
	check(
		back.type == GameCommand.Type.UPGRADE_CASTLE and back.args.is_empty(),
		"journal row round trip"
	)
	check(Sim.VERSION >= 3, "Sim.VERSION raised (%d)" % Sim.VERSION)


func _daily_day() -> String:
	var base: int = Daily.day_index("2026-10-15")
	for i in 30:
		var key: String = Daily.key_of_day(base + i)
		if str(Daily.preset_for(key)["id"]) == "archers_frost":
			return key
	return Daily.key_of_day(base)


func _load_level() -> Node:
	paused = false
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


func _test_scene(record: bool, daily: String) -> void:
	var mode: String = "daily" if daily != "" else ("record run" if record else "campaign")
	print("-- scene: %s" % mode)
	LevelCatalog.daily_key = ""
	LevelCatalog.selected_id = (
		int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	)
	LevelCatalog.endless = record
	if daily != "":
		DailyRun.select(daily)
	var main: Node = await _load_level()
	var sim: Sim = main.get_node("Sim")
	var commands: GameCommands = main.get_node("GameCommands")
	var gs: GameState = main.get_node("GameState")
	var castle: Node3D = main.builder.castle
	var body: MeshInstance3D = castle.find_children("*", "MeshInstance3D", true, false)[0]
	var plain: Mesh = body.mesh
	var lives0: int = gs.lives
	# Without resources: refused, not journaled.
	gs.gold = 0
	gs.wood = 0
	var h0: int = sim.state_hash()
	check(not commands.submit(GameCommand.upgrade_castle()), "%s: refused without resources" % mode)
	check(
		commands.journal.commands.is_empty(), "%s: a refused command is not in the journal" % mode
	)
	check(sim.state_hash() == h0, "%s: nothing changed (same hash)" % mode)
	# Every upgrade in turn: price, lives, armor, the journal, the look.
	var meshes: Array[Mesh] = [plain]
	for level in range(1, CastleUpgrades.max_level() + 1):
		var cost: Vector2i = CastleUpgrades.cost(level - 1)
		gs.gold = cost.x + 7
		gs.wood = cost.y + 3
		var lives_before: int = gs.lives
		check(
			commands.submit(GameCommand.upgrade_castle()), "%s: upgrade %d accepted" % [mode, level]
		)
		check(gs.gold == 7 and gs.wood == 3, "%s: upgrade %d paid exactly %s" % [mode, level, cost])
		check(
			(
				gs.castle_level == level
				and gs.lives == lives_before + CastleUpgrades.lives_bonus(level - 1)
			),
			"%s: level %d, lives %d -> %d" % [mode, level, lives_before, gs.lives]
		)
		check(
			gs.castle_armor() == CastleUpgrades.armor_at(level),
			"%s: armor %d" % [mode, gs.castle_armor()]
		)
		check(
			body.mesh != null and not meshes.has(body.mesh),
			"%s: the castle has a new body mesh" % mode
		)
		meshes.append(body.mesh)
		check(
			castle.find_children("*", "MeshInstance3D", true, false).size() == 1,
			"%s: still one mesh instance (no extra draw calls)" % mode
		)
	check(
		commands.journal.commands.size() == CastleUpgrades.max_level(),
		"%s: four commands in the journal" % mode
	)
	gs.gold = 99999
	gs.wood = 99999
	check(
		not commands.submit(GameCommand.upgrade_castle()),
		"%s: the maximum cannot be exceeded" % mode
	)
	check(
		commands.journal.commands.size() == CastleUpgrades.max_level(),
		"%s: refused at max, not journaled" % mode
	)
	check(
		gs.lives > lives0, "%s: more lives than at the start (%d > %d)" % [mode, gs.lives, lives0]
	)
	# Leaks through the real handler: heavy ones lose to the armor, light ones always cost 1.
	var armor: int = gs.castle_armor()
	var before: int = gs.lives
	main.call("_on_enemy_reached_base", 5)
	check(
		before - gs.lives == maxi(1, 5 - armor),
		"%s: a king leak costs %d" % [mode, before - gs.lives]
	)
	before = gs.lives
	main.call("_on_enemy_reached_base", 1)
	check(before - gs.lives == 1, "%s: a light leak costs 1" % mode)
	# The forge card shows the castle: level, next effect, price or "max".
	var info: Dictionary = CommandCards.forge(main.get_node("Level/Hero"), gs)
	var button: Dictionary = {}
	for spec: Dictionary in info["buttons"]:
		if spec["id"] == &"castle":
			button = spec
	check(not button.is_empty(), "%s: the forge card has the castle button" % mode)
	check(
		button.has("label") and not button.has("gold"), "%s: at the top the button says max" % mode
	)
	check(str(info["hint"]).contains("4/4"), "%s: hint shows the level (%s)" % [mode, info["hint"]])
	gs.reset()
	info = CommandCards.forge(main.get_node("Level/Hero"), gs)
	for spec: Dictionary in info["buttons"]:
		if spec["id"] == &"castle":
			button = spec
	check(
		(
			button.get("gold", 0) == CastleUpgrades.cost(0).x
			and button.get("wood", 0) == CastleUpgrades.cost(0).y
		),
		"%s: next price on the button" % mode
	)
	check(not button["enabled"], "%s: disabled while poor" % mode)
	check(
		str(info["hint"]).contains("0/4") and str(info["hint"]).contains("+"),
		"%s: hint: %s" % [mode, info["hint"]]
	)
	CastleModel.show_level(castle, 0)
	check(body.mesh == plain, "%s: level 0 shows the plain castle again" % mode)
	await process_frame  # the effects of the upgrades finish their deferred start
	await process_frame
