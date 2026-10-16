extends SceneTree
## Memory between battles (needs a window, NOT --headless): the map and a battle are
## entered and left again and again, the way a player goes map -> level -> map, and the
## counters that would show a level that is not freed are printed after every round.
## Also prints how long the load of each level part and of the whole scene takes.
## LEVEL=<id|0 = all in turn> RUNS=10 godot --path . --resolution 1280x720 \
##   --script res://tools/soak_reload.gd

const MAP := "res://scenes/level_select.tscn"
const GAME := "res://scenes/main.tscn"
const HEADER := "run,level,load_ms,objects,nodes,orphans,static_mb,vram_mb,rss_mb"


func _initialize() -> void:
	LevelCatalog.save_path = "user://soak_reload.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	_run.call_deferred()


func _rss_mb() -> float:
	var out: Array = []
	OS.execute("ps", ["-o", "rss=", "-p", str(OS.get_process_id())], out)
	return float(str(out[0]).strip_edges()) / 1024.0 if not out.is_empty() else 0.0


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _row(run: int, level: int, load_ms: float) -> void:
	print(
		(
			"%d,%d,%.0f,%d,%d,%d,%.1f,%.1f,%.1f"
			% [
				run,
				level,
				load_ms,
				int(Performance.get_monitor(Performance.OBJECT_COUNT)),
				int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
				Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
				_rss_mb(),
			]
		)
	)


func _run() -> void:
	var runs: int = int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 10
	var only: int = int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 0
	# Cold load of the parts of level 1 (this is what a phone does when a level starts).
	for part in ["terrain", "decor", "forest"]:
		var t0: int = Time.get_ticks_usec()
		var scene: PackedScene = load("res://assets/models/level_1_%s.glb" % part)
		var t1: int = Time.get_ticks_usec()
		var node: Node = scene.instantiate()
		var t2: int = Time.get_ticks_usec()
		print(
			(
				"LOAD level_1_%s load=%.0f ms instantiate=%.0f ms"
				% [part, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0]
			)
		)
		node.free()
	change_scene_to_file(MAP)
	await _frames(30)
	print(HEADER)
	_row(0, 0, 0.0)
	for run in range(1, runs + 1):
		var level: int = only if only > 0 else 1 + (run - 1) % 6
		LevelCatalog.selected_id = level
		LevelCatalog.endless = false
		var t0: int = Time.get_ticks_msec()
		change_scene_to_file(GAME)
		var sim: Sim = null
		while sim == null:
			await process_frame
			if current_scene != null and current_scene.has_node("Sim"):
				sim = current_scene.get_node("Sim")
		while not sim.running:
			await process_frame
		var load_ms: float = Time.get_ticks_msec() - t0
		# A short battle: waves, towers and effects get created.
		var main: Node = current_scene
		var wm: WaveManager = main.get_node("WaveManager")
		var gs: GameState = main.get_node("GameState")
		var bm: BuildManager = main.get_node("BuildManager")
		gs.add_gold(5000)
		gs.add_wood(500)
		for node: Node in get_nodes_in_group(TowerSlot.GROUP):
			bm.build_on(node as TowerSlot, bm.tower_types[0])
		wm.start_next_wave()
		wm.start_next_wave()
		Engine.time_scale = 3.0
		await _frames(400)
		Engine.time_scale = 1.0
		_row(run, level, load_ms)
		change_scene_to_file(MAP)
		await _frames(40)
		_row(run, 0, 0.0)
	quit()
