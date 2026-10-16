extends SceneTree
## Screenshots of the map with the Record Run button and the difficulty row, and of the
## Record Run HUD. Needs a display.
## SHOT_DIR=/tmp/shots godot --path . --resolution 1280x720 --rendering-driver opengl3 \
##   --script res://tools/shot_difficulty.gd

const SAVE := "user://shot_difficulty_progress.cfg"

var _dir: String = ""


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	LevelCatalog.erase_all()
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("user://")
	_run.call_deferred()


func _run() -> void:
	GameSettings.set_language("ru")
	Onboarding.set_local_nickname("Ёжик", "x", false)
	LevelCatalog.complete(1, 3)
	LevelCatalog.complete(2, 2, 1)
	LevelCatalog.save_endless(2, 23)
	change_scene_to_file("res://scenes/level_select.tscn")
	await _frames(30)
	await _shot("map_normal")
	current_scene.call("_on_difficulty_pressed", 1)
	await _frames(5)
	await _shot("map_hard")
	current_scene.call("_select", 2)
	await _frames(5)
	await _shot("map_level2")
	LevelCatalog.selected_id = 2
	LevelCatalog.endless = true
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(240)
	await _shot("record_hud")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("%s/difficulty_%s.png" % [_dir, name])
	print("saved ", name)
