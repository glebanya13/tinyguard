extends SceneTree
## Saves a screenshot of a level.
## LEVEL=<id> SHOT=<png path> godot --path . --resolution 1280x720 --script res://tools/shot_level.gd


func _initialize() -> void:
	LevelCatalog.save_path = "user://shot.cfg"
	LevelCatalog.selected_id = int(OS.get_environment("LEVEL"))
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func _run() -> void:
	for i in 40:
		await process_frame
	root.get_texture().get_image().save_png(OS.get_environment("SHOT"))
	quit()
