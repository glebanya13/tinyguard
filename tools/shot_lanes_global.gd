extends SceneTree
## Screenshot of the global lane indicators (edge arrows + compass), needs a window:
## LEVEL=4 OUT=/tmp/x.png godot --path . --resolution 1600x720 \
##   --script res://tools/shot_lanes_global.gd
## FRAMES=n waits n frames after the wave starts (default 90).
## HERO=x,z teleports the knight (and the camera) to show a portal that is off screen.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LevelCatalog.save_path = "user://shot_lanes.cfg"
	var level: int = int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 4
	LevelCatalog.selected_id = level
	change_scene_to_file("res://scenes/main.tscn")
	for i in 20:
		await process_frame
	var main: Node = current_scene
	var wm: WaveManager = main.get_node("WaveManager")
	if OS.get_environment("HERO") != "":
		var parts: PackedStringArray = OS.get_environment("HERO").split(",")
		main.get_node("Level/Hero").global_position = Vector3(float(parts[0]), 0.0, float(parts[1]))
		main.get_node("Camera").snap()
	wm.start_next_wave()
	var frames: int = (
		int(OS.get_environment("FRAMES")) if OS.get_environment("FRAMES") != "" else 90
	)
	for i in frames:
		await process_frame
	var image: Image = root.get_texture().get_image()
	var out: String = (
		OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/lanes.png"
	)
	image.save_png(out)
	print("saved ", out)
	quit()
