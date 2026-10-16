extends SceneTree
## Slow-phone emulation (needs a window): the real clock runs a battle at x2 speed while
## every simulation step is made artificially expensive (STEP_MS busy-wait). Shows how the
## clock behaves when steps cost more than a frame: frame time, steps done per second.
## STEP_MS=12 SECONDS=20 godot --path . --resolution 960x540 --script res://tools/exp_spiral.gd


func _initialize() -> void:
	LevelCatalog.save_path = "user://exp_spiral.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	LevelCatalog.selected_id = 1
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func _run() -> void:
	var sim: Sim = null
	while sim == null:
		await process_frame
		if current_scene != null and current_scene.has_node("Sim"):
			sim = current_scene.get_node("Sim")
	for i in 100:
		if sim.running:
			break
		await process_frame
	var step_ms: float = (
		float(OS.get_environment("STEP_MS")) if OS.get_environment("STEP_MS") != "" else 12.0
	)
	var seconds: float = (
		float(OS.get_environment("SECONDS")) if OS.get_environment("SECONDS") != "" else 20.0
	)
	sim.ticked.connect(func(_t: int) -> void: OS.delay_usec(int(step_ms * 1000.0)))
	Engine.time_scale = 2.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var start_tick: int = sim.tick
	var t0: int = Time.get_ticks_usec()
	var last: int = t0
	var frames: int = 0
	var worst: float = 0.0
	while (Time.get_ticks_usec() - t0) / 1000000.0 < seconds:
		await process_frame
		var now: int = Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
	var real: float = (Time.get_ticks_usec() - t0) / 1000000.0
	var ticks: int = sim.tick - start_tick
	print(
		(
			(
				"SPIRAL step_ms=%.0f real=%.1fs frames=%d avg_frame=%.1f ms worst=%.0f ms "
				+ "ticks=%d (%.1f/s, wanted %.0f/s) over_budget=%d"
			)
			% [
				step_ms,
				real,
				frames,
				real * 1000.0 / frames,
				worst,
				ticks,
				ticks / real,
				60.0,
				sim.over_budget_frames if "over_budget_frames" in sim else -1
			]
		)
	)
	quit()
