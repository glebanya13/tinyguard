extends SceneTree
## Draw-call benchmark (needs a window, NOT --headless): every slot gets a maxed tower
## (4 kinds in turn), waves overlap at 3x speed, the HUD is on.
## LEVEL=<id> godot --path . --resolution 1280x720 --script res://tools/measure_draw_calls.gd
## Prints the mean / peak of TOTAL_DRAW_CALLS_IN_FRAME in battle, then what each
## child of Level (and the HUD) costs when hidden.

const BATTLE_SECONDS := 40.0
const SAMPLE_FRAMES := 20


func _initialize() -> void:
	LevelCatalog.save_path = "user://measure.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	LevelCatalog.selected_id = (
		int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	)
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func _calls() -> int:
	return int(
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	)


func _mean(frames: int) -> float:
	var sum := 0.0
	for i in frames:
		await process_frame
		sum += _calls()
	return sum / frames


func _run() -> void:
	for i in 10:
		await process_frame
	var main: Node = current_scene
	var gs: GameState = main.get_node("GameState")
	var wm: WaveManager = main.get_node("WaveManager")
	var bm: BuildManager = main.get_node("BuildManager")
	var empty: float = await _mean(SAMPLE_FRAMES)
	gs.add_gold(100000)
	gs.add_wood(100000)
	var kind := 0
	for node: Node in get_nodes_in_group(TowerSlot.GROUP):
		var slot := node as TowerSlot
		if bm.build_on(slot, bm.tower_types[kind % bm.tower_types.size()]):
			while bm.upgrade(slot):
				pass
		kind += 1
	gs.lives = 100000
	# The command card of a selected tower is open in real play most of the time.
	bm.select_slot(get_nodes_in_group(TowerSlot.GROUP)[0] as TowerSlot)
	await process_frame
	var built: float = await _mean(SAMPLE_FRAMES)
	Engine.time_scale = 3.0
	var sum := 0.0
	var n := 0
	var peak := 0
	var peak_enemies := 0
	var prims := 0.0
	var proc_ms := 0.0
	var elapsed := 0.0
	var next_wave := 0.0
	var last := Time.get_ticks_msec()
	while elapsed < BATTLE_SECONDS:
		if bm.selected_slot == null:
			bm.select_slot(get_nodes_in_group(TowerSlot.GROUP)[0] as TowerSlot)
		if elapsed >= next_wave:
			wm.start_next_wave()
			next_wave += 2.0
		await process_frame
		elapsed += (Time.get_ticks_msec() - last) / 1000.0
		last = Time.get_ticks_msec()
		var c := _calls()
		sum += c
		prims += RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
		)
		proc_ms += (
			(
				Performance.get_monitor(Performance.TIME_PROCESS)
				+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
			)
			* 1000.0
		)
		n += 1
		peak = maxi(peak, c)
		peak_enemies = maxi(peak_enemies, get_nodes_in_group(Enemy.GROUP).size())
	print(
		(
			"LEVEL %s empty=%.0f built=%.0f battle_mean=%.0f battle_peak=%d peak_enemies=%d tris_k=%.0f script_ms=%.2f"
			% [
				LevelCatalog.selected_id,
				empty,
				built,
				sum / n,
				peak,
				peak_enemies,
				prims / n / 1000.0,
				proc_ms / n
			]
		)
	)
	# Cost of each part: hide it, count, show it again.
	Engine.time_scale = 0.0001
	var base: float = await _mean(SAMPLE_FRAMES)
	var sun: DirectionalLight3D = main.get_node("Sun")
	sun.shadow_enabled = false
	var m0: float = await _mean(4)
	sun.shadow_enabled = true
	print("  part Sun shadows: %.0f of %.0f" % [base - m0, base])
	var kids: Array[Node] = main.get_node("Level").get_children()
	kids.append_array(main.get_children())
	kids.append_array(main.get_node("HUD/Root").get_children())
	if OS.get_environment("DETAIL") != "":
		for node: Node in main.get_node("HUD/Root").find_children("*", "CanvasItem", true, false):
			if node is Control and node.get_parent().get_parent() != main.get_node("HUD/Root"):
				kids.append(node)
	for child: Node in kids:
		if not "visible" in child or child.name == "Level":
			continue
		var was: bool = child.visible
		child.visible = false
		var m: float = await _mean(4)
		child.visible = was
		if base - m >= 1.0:
			print(
				(
					"  part %s: %.0f of %.0f"
					% [child.get_path() if child is Control else child.name, base - m, base]
				)
			)
	quit()
