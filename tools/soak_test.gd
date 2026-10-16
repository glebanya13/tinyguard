extends SceneTree
## Soak test (needs a window, NOT --headless): a scripted bot plays one long battle and
## the metrics that grow with a leak are printed as CSV rows. The clock is driven by hand
## (TICKS_PER_FRAME steps per frame, 6 = a x3 game at 60 fps), so 20 game minutes take
## about two real ones. The bot is the one of tests/test_replay.gd, plus a gold top-up so
## its towers keep up with the late waves (STRESS=0 turns the top-up off).
##
## LEVEL=<id> [DAILY=YYYY-MM-DD] [MINUTES=20] [TICKS_PER_FRAME=6] [SAMPLE_SECONDS=60]
##   [STRESS=1] [RAMP=0] godot --path . --resolution 1280x720 --script res://tools/soak_test.gd
## RAMP=1 also starts a new wave every few seconds (hundreds of enemies at once).
## CSV columns: see HEADER. One line "SOAK_SUMMARY ..." at the end.

const HEADER := (
	"level,game_min,wave,enemies,proj,towers,objects,nodes,orphans,static_mb,vram_mb,"
	+ "draws,script_ms,frame_ms,frame_max_ms,step_ms,step_max_ms,rss_mb,journal"
)

var _level: int = 1
var _ticks_per_frame: int = 6
var _total_ticks: int = 36000
var _sample_ticks: int = 1800
var _stress: bool = true
var _ramp: bool = false
var _last_bot_tick: int = -1
var _sworded: bool = false
var _rows: Array[PackedFloat64Array] = []


func _initialize() -> void:
	LevelCatalog.save_path = "user://soak.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	node_added.connect(
		func(node: Node) -> void:
			if node is Hero:
				(node as Hero).auto_action = false
	)
	_level = _env_int("LEVEL", 1)
	_ticks_per_frame = _env_int("TICKS_PER_FRAME", 6)
	_total_ticks = _env_int("MINUTES", 20) * 60 * Sim.TICK_RATE
	_sample_ticks = _env_int("SAMPLE_SECONDS", 60) * Sim.TICK_RATE
	_stress = _env_int("STRESS", 1) != 0
	_ramp = _env_int("RAMP", 0) != 0
	LevelCatalog.selected_id = _level
	LevelCatalog.endless = true
	var daily: String = OS.get_environment("DAILY")
	if daily != "":
		DailyRun.select(daily)
		_level = LevelCatalog.selected_id
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func _env_int(name: String, fallback: int) -> int:
	var text: String = OS.get_environment(name)
	return int(text) if text != "" else fallback


func _rss_mb() -> float:
	var out: Array = []
	OS.execute("ps", ["-o", "rss=", "-p", str(OS.get_process_id())], out)
	return float(str(out[0]).strip_edges()) / 1024.0 if not out.is_empty() else 0.0


func _run() -> void:
	var sim: Sim = null
	while sim == null:
		await process_frame
		if current_scene != null and current_scene.has_node("Sim"):
			sim = current_scene.get_node("Sim")
	sim.manual = true
	for i in 300:
		if sim.running:
			break
		await process_frame
	var main: Node = current_scene
	var commands: GameCommands = main.get_node("GameCommands")
	var gs: GameState = main.get_node("GameState")
	var wm: WaveManager = main.get_node("WaveManager")
	print(HEADER)
	var frame_sum: float = 0.0
	var frame_max: float = 0.0
	var frames: int = 0
	var step_sum: float = 0.0
	var step_max: float = 0.0
	var next_sample: int = 0
	var peak_enemies: int = 0
	var worst_frame: float = 0.0
	var last_us: int = Time.get_ticks_usec()
	var hard_stop_us: int = last_us + _env_int("WALL_SECONDS", 1500) * 1000000
	var next_ramp: int = 0
	while sim.tick < _total_ticks and Time.get_ticks_usec() < hard_stop_us:
		if sim.tick != _last_bot_tick and sim.tick % 5 == 0:
			_last_bot_tick = sim.tick
			_bot(main, sim, commands, gs)
		if _ramp and sim.tick >= next_ramp:
			wm.start_next_wave()
			next_ramp = sim.tick + 6 * Sim.TICK_RATE
		var t0: int = Time.get_ticks_usec()
		for k in _ticks_per_frame:
			sim.step()
		var step_ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		step_sum += step_ms
		step_max = maxf(step_max, step_ms)
		await process_frame
		var now: int = Time.get_ticks_usec()
		var frame_ms: float = (now - last_us) / 1000.0
		last_us = now
		frame_sum += frame_ms
		frame_max = maxf(frame_max, frame_ms)
		worst_frame = maxf(worst_frame, frame_ms)
		frames += 1
		peak_enemies = maxi(peak_enemies, sim.enemies.size())
		if sim.tick >= next_sample:
			next_sample = sim.tick + _sample_ticks
			_sample(sim, wm, commands, frame_sum, frame_max, step_sum, step_max, frames)
			frame_sum = 0.0
			frame_max = 0.0
			step_sum = 0.0
			step_max = 0.0
			frames = 0
	_sample(sim, wm, commands, frame_sum, frame_max, step_sum, step_max, maxi(frames, 1))
	var first: PackedFloat64Array = _rows[1] if _rows.size() > 1 else _rows[0]
	var last: PackedFloat64Array = _rows[-1]
	print(
		(
			(
				"SOAK_SUMMARY level=%d minutes=%.1f wave=%d peak_enemies=%d worst_frame_ms=%.1f "
				+ "d_objects=%+d d_nodes=%+d d_orphans=%+d d_static_mb=%+.1f d_vram_mb=%+.1f "
				+ "d_rss_mb=%+.1f (from sample 2 to last)"
			)
			% [
				_level,
				last[0],
				int(last[1]),
				peak_enemies,
				worst_frame,
				int(last[5] - first[5]),
				int(last[6] - first[6]),
				int(last[7] - first[7]),
				last[8] - first[8],
				last[9] - first[9],
				last[16] - first[16],
			]
		)
	)
	quit()


func _sample(
	sim: Sim,
	wm: WaveManager,
	commands: GameCommands,
	frame_sum: float,
	frame_max: float,
	step_sum: float,
	step_max: float,
	frames: int
) -> void:
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	var nodes: float = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var orphans: float = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var static_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var vram_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var draws: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var script_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var rss: float = _rss_mb()
	var row := PackedFloat64Array(
		[
			sim.tick / float(Sim.TICK_RATE) / 60.0,
			wm.current_wave,
			sim.enemies.size(),
			sim.projectiles.size(),
			sim.towers.size(),
			objects,
			nodes,
			orphans,
			static_mb,
			vram_mb,
			draws,
			script_ms,
			frame_sum / frames,
			frame_max,
			step_sum / frames / _ticks_per_frame,
			step_max / _ticks_per_frame,
			rss,
			commands.journal.commands.size()
		]
	)
	_rows.append(row)
	print(
		(
			"%d,%.1f,%d,%d,%d,%d,%d,%d,%d,%.1f,%.1f,%d,%.2f,%.1f,%.1f,%.3f,%.3f,%.1f,%d"
			% [
				_level,
				row[0],
				int(row[1]),
				int(row[2]),
				int(row[3]),
				int(row[4]),
				int(objects),
				int(nodes),
				int(orphans),
				static_mb,
				vram_mb,
				int(draws),
				script_ms,
				row[12],
				row[13],
				row[14],
				row[15],
				rss,
				int(row[17])
			]
		)
	)


## The scripted player of tests/test_replay.gd (reads the simulation, issues commands).
func _bot(main: Node, sim: Sim, commands: GameCommands, gs: GameState) -> void:
	var bm: BuildManager = main.get_node("BuildManager")
	var hero: Hero = main.get_node("Level/Hero")
	var t: int = sim.tick
	if _stress:
		gs.lives = maxi(gs.lives, 1000)  # the run goes on, the leaks are what we look for
		if t % 150 == 0:
			gs.add_gold(400)
			gs.add_wood(60)
	if gs.wood < 80:
		for tree in sim.trees:
			if tree.is_choppable():
				var origin: Vector3 = tree.global_position + Vector3(1.0, 0.0, 0.0)
				commands.submit(GameCommand.hero_attack(origin, -PI / 2.0))
				break
	if not sim.enemies.is_empty() and hero.spin_cooldown_left() <= 0.0:
		commands.submit(GameCommand.hero_spin(sim.enemies[0].sim_position()))
	if t % 10 == 0:
		for slot in commands.slots:
			var kind: int = slot.slot_id % bm.tower_types.size()
			if slot.is_free() and bm.can_build(slot, bm.tower_types[kind]):
				commands.submit(GameCommand.build(slot.slot_id, kind))
				break
			if not slot.is_free() and t % 60 == 0 and bm.can_upgrade(slot):
				commands.submit(GameCommand.upgrade(slot.slot_id))
				break
	if t >= 600 and t % 150 == 0:
		for slot in commands.slots:
			if not slot.is_free():
				commands.submit(
					GameCommand.set_priority(slot.slot_id, (slot.tower.priority + 1) % 4)
				)
				break
	if t % 90 == 0 and gs.wood >= 40:
		commands.submit(GameCommand.trade(1))
	if not _sworded and gs.can_afford(hero.sword_upgrade_cost()) and t > 1000:
		commands.submit(GameCommand.sword())
