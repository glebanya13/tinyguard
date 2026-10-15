extends SceneTree
## Visual effects never touch the battle: the same journal gives the same state
## hashes with effects off, minimum and full (it is recorded with one level and
## replayed with the others). Also the settings, the particle layer limits and
## that "off" really builds nothing.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_fx.gd

const TOTAL_TICKS := 1500
const HASH_EVERY := 30

var fails := 0
var _trace: Array[int] = []


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_fx_progress.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	GameSettings.config_path = "user://test_fx_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.config_path))
	GameSettings._forced = -1  # ignore BIMBLEGUARD_FX: the test sets the level itself
	node_added.connect(
		func(node: Node) -> void:
			if node is Hero:
				(node as Hero).auto_action = false
	)
	LevelCatalog.selected_id = 1
	_run.call_deferred()


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


## Plays TOTAL_TICKS; records (journal == null) or replays the journal. Returns
## the hash trace and the Fx node.
func _battle(level: int, journal: CommandLog) -> Dictionary:
	GameSettings.set_effects(level)
	var main: Node = await _load_level()
	var sim: Sim = main.get_node("Sim")
	var commands: GameCommands = main.get_node("GameCommands")
	var gs: GameState = main.get_node("GameState")
	_trace.clear()
	sim.ticked.connect(
		func(t: int) -> void:
			if t % HASH_EVERY == 0:
				_trace.append(sim.state_hash())
	)
	if journal != null:
		sim.begin_replay(journal)  # applies the journal's start (resources reset)
	gs.add_gold(2000)
	gs.add_wood(2000)
	var built := false
	while sim.tick < TOTAL_TICKS:
		if journal == null and not built and sim.tick >= 5:
			built = true
			for slot in commands.slots:
				commands.submit(GameCommand.build(slot.slot_id, slot.slot_id % 4))
		sim.advance(1.0 / 60.0)
		await process_frame
	return {"trace": _trace.duplicate(), "main": main, "journal": commands.journal}


func _run() -> void:
	# --- Settings.
	GameSettings.set_effects(GameSettings.FX_MIN)
	check(GameSettings.effects() == GameSettings.FX_MIN, "effects level is stored")
	GameSettings._effects = -1  # forget the cache: read the file again
	check(GameSettings.effects() == GameSettings.FX_MIN, "effects level survives a reload")
	GameSettings.set_effects(99)
	check(GameSettings.effects() == GameSettings.FX_FULL, "effects level is clamped")

	# --- Particle layer: capacity is a hard limit and it empties itself.
	var layer := FxParticles.new()
	root.add_child(layer)
	await process_frame
	var accepted: int = 0
	for i in FxParticles.CAPACITY + 20:
		if layer.emit(Vector3.ZERO, Vector3.UP, 0.1, 1.0, 0.1, Color.WHITE, Color.WHITE):
			accepted += 1
	check(accepted == FxParticles.CAPACITY, "particle layer drops what does not fit")
	for i in 20:
		await process_frame
	await create_timer(0.3).timeout
	check(layer.alive_count() == 0, "particles die after their lifetime")
	layer.queue_free()

	# --- Same journal, different effects: identical hashes.
	var rec: Dictionary = await _battle(GameSettings.FX_OFF, null)
	var off_trace: Array[int] = rec["trace"]
	var journal: CommandLog = rec["journal"]
	check(off_trace.size() == TOTAL_TICKS / HASH_EVERY, "recorded %d hashes" % off_trace.size())
	check(journal.commands.size() >= 4, "the bot built towers (%d commands)" % journal.commands.size())
	var fx_off: Fx = rec["main"].get_node("Fx")
	check(fx_off._dots == null and fx_off._layer == null, "effects off: nothing was built")
	for level in [GameSettings.FX_MIN, GameSettings.FX_FULL]:
		var played: Dictionary = await _battle(level, journal)
		var trace: Array[int] = played["trace"]
		check(trace == off_trace, "effects level %d: same hashes as with effects off" % level)
		var fx: Fx = played["main"].get_node("Fx")
		check(fx._dots != null, "effects level %d: the layers were built" % level)

	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
