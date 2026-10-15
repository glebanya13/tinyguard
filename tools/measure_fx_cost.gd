extends SceneTree
## Draw calls of each effect layer (needs a window, NOT --headless): time is nearly
## frozen, the effects are started by hand and stay on screen while the frame is counted.
## LEVEL=<id> godot --path . --resolution 1280x720 --script res://tools/measure_fx_cost.gd


func _initialize() -> void:
	LevelCatalog.save_path = "user://measure_fx.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	var level: String = OS.get_environment("LEVEL")
	LevelCatalog.selected_id = int(level) if level != "" else 1
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func _calls() -> float:
	var sum := 0.0
	for i in 6:
		await process_frame
		sum += RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
		)
	return sum / 6.0


func _run() -> void:
	for i in 15:
		await process_frame
	var main: Node = current_scene
	var fx: Fx = main.get_node("Fx")
	var camera: Camera3D = main.get_node("Camera")
	var centre: Vector3 = main.get_node("Level/Hero").global_position
	Engine.time_scale = 0.0001
	fx._ensure_built()
	for i in 20:
		await process_frame  # the digit atlas is rendered once, in the first frames
	var base: float = await _calls()
	print("FXCOST baseline %.0f" % base)
	for i in 10:
		fx._text("%d" % (i * 7), centre + Vector3(i * 0.3 - 1.5, 1.0, 0.0), Color.WHITE, 22 if i % 2 == 0 else 28)
	var with_numbers: float = await _calls()
	print("FXCOST 10 numbers: +%.0f" % (with_numbers - base))
	fx._numbers.clear()
	for i in 150:
		fx._emit_dot(
			centre + Vector3(i * 0.02, 0.5, 0.0), Vector3.ZERO, 5.0, 0.2, 0.2, Color.WHITE, Color.WHITE
		)
	var with_dots: float = await _calls()
	print("FXCOST 150 dots: +%.0f" % (with_dots - base))
	fx._dots.clear()
	for i in 20:
		fx._ring(centre + Vector3(i * 0.1, 0.0, 0.0), 0.5, 1.5, Color.WHITE, 5.0)
	var with_rings: float = await _calls()
	print("FXCOST 20 rings: +%.0f" % (with_rings - base))
	fx._rings.clear()
	fx._vignette.visible = true
	fx._vignette.modulate.a = 0.5
	var with_vignette: float = await _calls()
	print("FXCOST vignette: +%.0f" % (with_vignette - base))
	fx._vignette.visible = false
	quit()
