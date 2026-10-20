extends SceneTree
## Determinism of the battle simulation: a scripted bot plays a level (builds,
## upgrades, sells, swings the sword, whirlwind, forge, castle upgrades, trade, speed, pause)
## while the journal is recorded; the same journal is then replayed twice on a
## fresh level with other frame times (jittery, and a steady 10 fps) and the
## state hash must match the recording at every 30th step, bit for bit.
## LEVEL=<id> godot --headless --fixed-fps 60 --path . --script res://tests/test_replay.gd

const TOTAL_TICKS := 3600
const HASH_EVERY := 30
const LOG_PATH := "user://test_replay_journal.json"

var fails := 0
var _trace: Array[int] = []
var _final: Array[int] = []
var _start_gold: int = 0
var _level: int = 1
var _last_bot_tick: int = -1
var _sold: bool = false
var _sworded: bool = false


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_replay.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	# The recording plays with the "swift feet" perk at full level: it rides in the journal header
	# and both replays must still end in the same hashes.
	LevelCatalog.data().set_value("perks", "swift", 3)
	# The bot plays: the knight must not swing by himself (even in the first frame).
	node_added.connect(
		func(node: Node) -> void:
			if node is Hero:
				(node as Hero).auto_action = false
	)
	_level = int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	LevelCatalog.selected_id = _level
	_run.call_deferred()


## Loads a fresh level and waits until its battle clock is ready.
func _load_level() -> Node:
	paused = false
	var old_scene: Node = current_scene
	change_scene_to_file("res://scenes/main.tscn")
	var sim: Sim = null
	while sim == null:
		await process_frame
		if current_scene != null and current_scene != old_scene and current_scene.has_node("Sim"):
			sim = current_scene.get_node("Sim")
	sim.manual = true  # before the clock starts: the test drives it
	for i in 200:
		if sim.running:
			break
		await process_frame
	return current_scene


func _collect(sim: Sim, main: Node) -> void:
	_trace.clear()
	_final.clear()
	var wm: WaveManager = main.get_node("WaveManager")
	var gs: GameState = main.get_node("GameState")
	sim.ticked.connect(
		func(t: int) -> void:
			if t % HASH_EVERY == 0:
				_trace.append(sim.state_hash())
			if t == TOTAL_TICKS:
				_final.assign(
					[
						gs.gold,
						gs.wood,
						gs.lives,
						wm.killed,
						wm.leaked,
						sim.enemies.size(),
						gs.castle_level
					]
				)
	)


func _run() -> void:
	# --- SimRng: fixed sequence (same on every platform).
	var rng := SimRng.new(42)
	var first: Array[int] = []
	for i in 5:
		first.append(rng.next_u32())
	check(
		first == [3270867926, 1795671209, 1924641435, 1143034755, 4121910957],
		"SimRng: golden sequence %s" % [first]
	)

	# The castle upgrades cost little here so that the short battle goes through ALL of them
	# (the real prices are in resources/castle_upgrades.json; the recording and both replays
	# run in this process and see the same table).
	CastleUpgrades.rows()
	CastleUpgrades._rows = [
		{"gold": 10, "wood": 10, "lives": 2, "armor": 0},
		{"gold": 10, "wood": 15, "lives": 2, "armor": 1},
		{"gold": 15, "wood": 20, "lives": 3, "armor": 1},
		{"gold": 15, "wood": 25, "lives": 3, "armor": 2},
	]

	# --- 1. Recording: the bot plays.
	var main: Node = await _load_level()
	var sim: Sim = main.get_node("Sim")
	var commands: GameCommands = main.get_node("GameCommands")
	check(sim.running and sim.tick == 0, "level %d: clock ready at tick 0" % _level)
	_collect(sim, main)
	_start_gold = (main.get_node("GameState") as GameState).gold
	while sim.tick < TOTAL_TICKS:
		if sim.tick != _last_bot_tick and sim.tick % 5 == 0:
			_last_bot_tick = sim.tick
			_bot(main, sim, commands)
		sim.advance(1.0 / 60.0)
		await process_frame
	var recorded: Array[int] = _trace.duplicate()
	var wm: WaveManager = main.get_node("WaveManager")
	var gs: GameState = main.get_node("GameState")
	var journal: CommandLog = commands.journal
	var final_state: Array[int] = _final.duplicate()
	print(
		(
			(
				"  recorded: %d commands, %d hashes, towers %d, killed %d, leaked %d, wave %d, "
				+ "gold %d wood %d lives %d, enemies %d"
			)
			% [
				journal.commands.size(),
				recorded.size(),
				sim.towers.size(),
				wm.killed,
				wm.leaked,
				wm.current_wave,
				gs.gold,
				gs.wood,
				gs.lives,
				sim.enemies.size()
			]
		)
	)
	check(
		is_equal_approx(float(journal.header["perks"]["swift"]), 0.18),
		"the journal header carries the swift perk"
	)
	check(recorded.size() == TOTAL_TICKS / HASH_EVERY, "hash recorded every %d ticks" % HASH_EVERY)
	check(journal.commands.size() >= 15, "bot gave enough commands (%d)" % journal.commands.size())
	check(wm.killed > 0 and sim.towers.size() > 0, "battle happened: kills and towers")
	check(recorded[-1] != recorded[0], "state changes over time")
	var kinds := {}
	var castle_upgrades: int = 0
	for cmd in journal.commands:
		kinds[cmd.type] = true
		if cmd.type == GameCommand.Type.UPGRADE_CASTLE:
			castle_upgrades += 1
	check(
		castle_upgrades == CastleUpgrades.max_level() and gs.castle_level == castle_upgrades,
		(
			"the bot upgraded the castle through all %d levels (%d commands)"
			% [CastleUpgrades.max_level(), castle_upgrades]
		)
	)
	check(kinds.size() >= 7, "many command kinds in the journal (%d)" % kinds.size())
	check(
		kinds.has(GameCommand.Type.HIRE) and kinds.has(GameCommand.Type.TRADE_BUY),
		"the journal has hire and buy commands"
	)
	check(
		(
			(main.villagers as Villagers).hired_count() >= 1
			and ((main.villagers as Villagers).lots_bought >= 1 or kinds.has(GameCommand.Type.TRADE_BUY))
		),
		(
			"lumberjacks working and wood bought (%d hired, %d lots)"
			% [
				(main.villagers as Villagers).hired_count(),
				(main.villagers as Villagers).lots_bought
			]
		)
	)

	# Journal through JSON and a file, as a saved replay would travel.
	check(journal.save(LOG_PATH) == OK, "journal saved")
	var loaded: CommandLog = CommandLog.load_file(LOG_PATH)
	check(
		loaded != null and loaded.commands.size() == journal.commands.size(), "journal loaded back"
	)
	check(loaded.to_json() == journal.to_json(), "journal survives JSON exactly")
	check(int(loaded.header["level"]) == _level and loaded.header.has("seed"), "header filled")

	# --- 2 and 3. Replays with other frame times.
	for variant in ["jitter", "10fps"]:
		# Cosmetics are colours only: the jitter replay wears a skin in every slot and must
		# still match the recording (worn here, not in the recording) hash for hash.
		Cosmetics.preview = {}
		if variant == "jitter":
			Cosmetics.preview = {
				"hero": "hero_ember", "tower": "tower_fire", "flag": "flag_violet", "fx": "fx_pink"
			}
		var other: Node = await _load_level()
		if variant == "jitter":
			var knight: Hero = get_nodes_in_group(Hero.GROUP)[0] as Hero
			var skinned: bool = false
			for mesh in knight.find_children("*", "MeshInstance3D", true, false):
				skinned = skinned or (mesh as MeshInstance3D).material_override != null
			check(skinned, "jitter replay: the knight wears a skin")
		var sim2: Sim = other.get_node("Sim")
		_collect(sim2, other)
		check(sim2.tick == 0, "%s: fresh level at tick 0" % variant)
		sim2.begin_replay(loaded)
		var jitter := RandomNumberGenerator.new()
		jitter.seed = 777
		while sim2.tick < TOTAL_TICKS:
			var dt: float = 0.1 if variant == "10fps" else jitter.randf_range(0.003, 0.19)
			sim2.advance(dt)
			await process_frame
		var state2: Array[int] = _final.duplicate()
		var same: int = 0
		var first_diff: int = -1
		for i in mini(recorded.size(), _trace.size()):
			if recorded[i] == _trace[i]:
				same += 1
			elif first_diff < 0:
				first_diff = (i + 1) * HASH_EVERY
		check(
			same == recorded.size() and _trace.size() >= recorded.size(),
			(
				"%s replay: %d/%d hashes equal (first mismatch at tick %d)"
				% [variant, same, recorded.size(), first_diff]
			)
		)
		check(
			state2 == final_state,
			"%s replay: final gold/wood/lives/kills %s == %s" % [variant, state2, final_state]
		)
		check(
			(other.get_node("GameCommands") as GameCommands).journal.commands.is_empty(),
			"%s replay: nothing was written to the journal" % variant
		)
		check(
			not (other.get_node("GameCommands") as GameCommands).submit(GameCommand.sword()),
			"%s replay: live commands are refused" % variant
		)

	Cosmetics.preview = {}
	await _negative_controls(loaded, recorded)
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


## The test must be able to fail: replays of a doctored journal have to diverge
## (a divergence here is the expected, passing outcome).
func _negative_controls(original: CommandLog, recorded: Array[int]) -> void:
	var first_build: int = -1
	for i in original.commands.size():
		if original.commands[i].type == GameCommand.Type.BUILD:
			first_build = i
			break
	check(first_build >= 0, "control: the journal has a BUILD command")
	var at: int = original.commands[first_build].tick
	var checkpoint: int = ceili((at + 1) / float(HASH_EVERY)) * HASH_EVERY

	var late := CommandLog.from_json(original.to_json())
	late.commands[first_build].tick += 1
	var result: Dictionary = await _replay_trace(late)
	var diff: int = _first_diff(recorded, result["trace"])
	check(
		diff >= at + 1,
		"control: a build one tick late diverges (tick %d, build at %d)" % [diff, at]
	)

	var other_tower := CommandLog.from_json(original.to_json())
	var cmd: GameCommand = other_tower.commands[first_build]
	cmd.args[1] = (cmd.args[1] + 1) % 4
	result = await _replay_trace(other_tower)
	diff = _first_diff(recorded, result["trace"])
	check(
		diff == checkpoint,
		"control: another tower type diverges at tick %d (got %d)" % [checkpoint, diff]
	)

	var first_prio: int = -1
	for i in original.commands.size():
		if original.commands[i].type == GameCommand.Type.SET_PRIORITY:
			first_prio = i
			break
	check(first_prio >= 0, "control: the journal has a SET_PRIORITY command")
	var no_prio := CommandLog.from_json(original.to_json())
	var prio_tick: int = no_prio.commands[first_prio].tick
	no_prio.commands.remove_at(first_prio)
	result = await _replay_trace(no_prio)
	diff = _first_diff(recorded, result["trace"])
	check(
		diff == ceili((prio_tick + 1) / float(HASH_EVERY)) * HASH_EVERY,
		"control: dropping a priority change diverges at the next hash (got %d)" % diff
	)

	# The wood economy is part of the hash: without a hire or a purchase the battle differs.
	for kind: GameCommand.Type in [GameCommand.Type.HIRE, GameCommand.Type.TRADE_BUY]:
		var index: int = -1
		for i in original.commands.size():
			if original.commands[i].type == kind:
				index = i
				break
		check(index >= 0, "control: the journal has command type %d" % kind)
		var without := CommandLog.from_json(original.to_json())
		var gone_tick: int = without.commands[index].tick
		without.commands.remove_at(index)
		result = await _replay_trace(without)
		diff = _first_diff(recorded, result["trace"])
		check(
			diff >= gone_tick and diff > 0,
			(
				"control: dropping command type %d diverges (tick %d, command at %d)"
				% [kind, diff, gone_tick]
			)
		)

	# The castle level is part of the hash: without an upgrade (the first or the last) it differs.
	for which: String in ["first", "last"]:
		var index: int = -1
		for i in original.commands.size():
			if original.commands[i].type == GameCommand.Type.UPGRADE_CASTLE:
				index = i
				if which == "first":
					break
		check(index >= 0, "control: the journal has castle upgrades")
		var no_castle := CommandLog.from_json(original.to_json())
		var castle_tick: int = no_castle.commands[index].tick
		no_castle.commands.remove_at(index)
		result = await _replay_trace(no_castle)
		diff = _first_diff(recorded, result["trace"])
		check(
			diff >= castle_tick and diff > 0,
			(
				"control: dropping the %s castle upgrade diverges (tick %d, command at %d)"
				% [which, diff, castle_tick]
			)
		)
	var late_castle := CommandLog.from_json(original.to_json())
	for cmd2: GameCommand in late_castle.commands:
		if cmd2.type == GameCommand.Type.UPGRADE_CASTLE:
			cmd2.tick += 45
			break
	result = await _replay_trace(late_castle)
	check(
		_first_diff(recorded, result["trace"]) > 0,
		"control: a castle upgrade 45 ticks late diverges"
	)

	var reseeded := CommandLog.from_json(original.to_json())
	reseeded.header["seed"] = int(reseeded.header["seed"]) + 1
	result = await _replay_trace(reseeded)
	diff = _first_diff(recorded, result["trace"])
	check(diff == HASH_EVERY, "control: another seed diverges at the first hash (got %d)" % diff)

	# Perks of the header are applied by the replay (not the local save).
	var perked := CommandLog.from_json(original.to_json())
	perked.header["perks"]["gold_start"] = 50
	result = await _replay_trace(perked)
	check(
		int(result["gold0"]) == _start_gold + 50,
		"perks: header gold_start applied (%d)" % result["gold0"]
	)
	check(_first_diff(recorded, result["trace"]) == HASH_EVERY, "perks: other perks diverge")


func _replay_trace(journal: CommandLog) -> Dictionary:
	var other: Node = await _load_level()
	var sim2: Sim = other.get_node("Sim")
	_collect(sim2, other)
	sim2.begin_replay(journal)
	var gold0: int = (other.get_node("GameState") as GameState).gold
	while sim2.tick < TOTAL_TICKS:
		sim2.advance(0.1)
		await process_frame
	return {"trace": _trace.duplicate(), "gold0": gold0}


## Tick of the first differing hash, or -1.
func _first_diff(a: Array[int], b: Array[int]) -> int:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return (i + 1) * HASH_EVERY
	return -1


## The scripted player. Reads only simulation state, issues only commands.
func _bot(main: Node, sim: Sim, commands: GameCommands) -> void:
	var gs: GameState = main.get_node("GameState")
	var bm: BuildManager = main.get_node("BuildManager")
	var hero: Hero = main.get_node("Level/Hero")
	var t: int = sim.tick
	# The villagers' wood economy (campaign): two lumberjacks, wood bought when short of it.
	var folk: Villagers = main.villagers
	if t == 0 or (t % 50 == 0 and folk.hired_count() < 2):
		commands.submit(GameCommand.hire(folk.hired_count()))
	if t == 10 or (t % 50 == 25 and folk.lots_bought < 1):
		commands.submit(GameCommand.trade_buy(1))
	# The castle: an upgrade whenever one is affordable (a refused command is not journaled).
	if t >= 120 and t % 20 == 0:
		commands.submit(GameCommand.upgrade_castle())
	# Speed and pause are commands too (a pause and resume at one tick).
	if t == 300:
		commands.submit(GameCommand.set_speed(2))
	if t == 600:
		commands.submit(GameCommand.set_speed(1))
	if t == 900:
		commands.submit(GameCommand.set_pause(true))
		commands.submit(GameCommand.set_pause(false))
	# Chop the first standing tree.
	if gs.wood < 80:
		for tree in sim.trees:
			if tree.is_choppable():
				var origin: Vector3 = tree.global_position + Vector3(1.0, 0.0, 0.0)
				commands.submit(GameCommand.hero_attack(origin, -PI / 2.0))
				break
	# Whirlwind on the first enemy.
	if not sim.enemies.is_empty() and hero.spin_cooldown_left() <= 0.0:
		commands.submit(GameCommand.hero_spin(sim.enemies[0].sim_position()))
	# Build / upgrade, one action per decision (the bot saves for the castle upgrade it is due).
	var need_villagers: bool = (folk.hired_count() < 1 or folk.lots_bought < 1) and not commands.slots[0].is_free()
	var saving: bool = need_villagers or gs.castle_level < clampi((t - 100) / 450, 0, CastleUpgrades.max_level())
	if t % 10 == 0 and not saving:
		for slot in commands.slots:
			var kind: int = slot.slot_id % bm.tower_types.size()
			if slot.is_free() and bm.can_build(slot, bm.tower_types[kind]):
				commands.submit(GameCommand.build(slot.slot_id, kind))
				break
			if not slot.is_free() and t % 60 == 0 and bm.can_upgrade(slot):
				commands.submit(GameCommand.upgrade(slot.slot_id))
				break
	# The player switches target priorities now and then (a command, hashed with the tower).
	if t >= 600 and t % 150 == 0:
		for slot in commands.slots:
			if not slot.is_free():
				commands.submit(
					GameCommand.set_priority(slot.slot_id, (slot.tower.priority + 1) % 4)
				)
				break
	if t == 1500 and not _sold and not commands.slots[0].is_free():
		_sold = true
		commands.submit(GameCommand.sell(0))
	if not _sworded and gs.can_afford(hero.sword_upgrade_cost()) and t > 1000:
		_sworded = true
		commands.submit(GameCommand.sword())
	if t % 90 == 0 and gs.wood >= 40:
		commands.submit(GameCommand.trade(1))
	if gs.lives < gs.starting_lives and gs.wood >= gs.repair_wood:
		commands.submit(GameCommand.repair())
