extends SceneTree
## Screenshots of the whole map of every level with all paths (needs a window, NOT --headless):
## godot --path . --resolution 1600x900 --script res://tools/shot_levels.gd
## Writes docs/screenshots/lanes_<id>.png. With HINT=1 (and LEVEL=<id>) it instead starts a
## wave and saves the view with the HUD, banner and lane markers as docs/screenshots/lane_hint.png.

const OUT := "res://docs/screenshots/%s.png"


func _initialize() -> void:
	_run.call_deferred()


func _shoot(level: int, hint: bool) -> void:
	LevelCatalog.save_path = "user://shot_levels.cfg"
	LevelCatalog.selected_id = level
	change_scene_to_file("res://scenes/main.tscn")
	for i in 20:
		await process_frame
	var main: Node = current_scene
	var camera: Camera3D = main.get_node("Camera")
	if hint:
		var wm: WaveManager = main.get_node("WaveManager")
		wm.start_next_wave()
		wm.start_next_wave()
		for i in 40:
			await process_frame
	else:
		main.get_node("HUD").visible = false
		camera.set_process(false)
		camera.size = 52.0
		camera.global_position = Vector3(11.5, 11.5, 11.5) * 1.6
	for i in 12:
		await process_frame
	var image: Image = root.get_texture().get_image()
	var name: String = "lane_hint" if hint else "lanes_%02d" % level
	image.save_png(ProjectSettings.globalize_path(OUT % name))
	print("saved ", name)


func _run() -> void:
	if OS.get_environment("HINT") != "":
		var id: int = int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 4
		await _shoot(id, true)
	else:
		for id in range(1, 7):
			await _shoot(id, false)
	quit()
