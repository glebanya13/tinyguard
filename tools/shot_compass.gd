extends SceneTree
## Screenshot of the road compass (mini map) of every level and its draw-call cost; needs a
## window (NOT --headless):
## OUT=/tmp/compass LANG_SHOT=ru godot --path . --resolution 1600x720 \
##   --script res://tools/shot_compass.gd
## LEVELS=1,2,3 limits the levels, LANG_SHOT=en|ru sets the language, WAVE_LANES=0,2 lights those
## roads (default: the first two). Saves <OUT>_<level>.png (the whole screen) and prints how
## many draw calls the compass adds.


func _initialize() -> void:
	_run.call_deferred()


func _calls() -> float:
	var sum: float = 0.0
	for i in 12:
		await process_frame
		sum += float(
			RenderingServer.get_rendering_info(
				RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
			)
		)
	return sum / 12.0


func _run() -> void:
	LevelCatalog.save_path = "user://shot_compass.cfg"
	var lang: String = (
		OS.get_environment("LANG_SHOT") if OS.get_environment("LANG_SHOT") != "" else "ru"
	)
	TranslationServer.set_locale(lang)
	LaneMap.screen_oriented = OS.get_environment("WORLD_AXES") == ""
	var ids: PackedStringArray = (
		OS.get_environment("LEVELS").split(",")
		if OS.get_environment("LEVELS") != ""
		else PackedStringArray(["1", "2", "3", "4", "5", "6"])
	)
	var out: String = (
		OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/compass"
	)
	for id: String in ids:
		LevelCatalog.selected_id = int(id)
		change_scene_to_file("res://scenes/main.tscn")
		for i in 20:
			await process_frame
		var main: Node = current_scene
		var hint: LaneHint = main._lane_hint
		var lanes: Array = [0, 1]
		if OS.get_environment("WAVE_LANES") != "":
			lanes = []
			for part: String in OS.get_environment("WAVE_LANES").split(","):
				lanes.append(int(part))
		hint.announce(main.builder.portals, lanes)
		if not hint.compass_visible():
			hint.toggle_compass()
		for i in 40:
			await process_frame
		var with_map: float = await _calls()
		var image: Image = root.get_texture().get_image()
		image.save_png("%s_%s.png" % [out, id])
		hint._pinned = false
		hint._compass_left = 0.0
		var without: float = await _calls()
		print(
			(
				"level %s: draw calls with compass %.1f, without %.1f, compass costs %.1f"
				% [id, with_map, without, with_map - without]
			)
		)
	quit()
