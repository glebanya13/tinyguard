extends SceneTree
## Global wave direction hints: a wave switches on edge arrows (with the side written) and
## the compass for the roads it uses; they go out when the wave is cleared or the battle ends;
## the button pins the compass. LEVEL=<id> godot --headless --fixed-fps 60 --path . \
## --script res://tests/test_lane_hint.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_lane_hint.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	LevelCatalog.selected_id = (
		int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 4
	)
	LevelCatalog.endless = false
	LevelCatalog.tutorial = false
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func _run() -> void:
	for i in 10:
		await process_frame
	var main: Node = current_scene
	var hint: LaneHint = main._lane_hint
	var wm: WaveManager = main.get_node("WaveManager")
	check(hint != null and not hint.level.is_empty(), "hint knows the level")
	check(not hint.arrows_active() and not hint.compass_visible(), "nothing before a wave")
	wm.start_next_wave()
	await process_frame
	check(hint.arrows_active(), "wave 1 switches the edge arrows on")
	check(hint.compass_visible(), "wave 1 opens the compass")
	check(hint.is_active(), "rings on the portals")
	# Arrows persist long after the 6 s of rings.
	for i in 660:
		await process_frame
	check(not hint.is_active(), "rings are gone after a few seconds")
	check(hint.arrows_active(), "edge arrows stay for the whole wave")
	check(not hint.compass_visible(), "the compass closes by itself")
	hint.toggle_compass()
	check(hint.compass_visible(), "the button pins the compass")
	hint.toggle_compass()
	check(not hint.compass_visible(), "pressed again, it closes")
	hint.finish()
	check(not hint.arrows_active(), "finish() puts the arrows out")
	# Drawing must not fail (also with a camera looking elsewhere).
	hint.announce(main.builder.portals, [0])
	await process_frame
	hint.queue_redraw()
	await process_frame
	var lines: String = LevelCatalog.direction_text(main.level, [0])
	check(lines != "", "side text for lane 0: %s" % lines)
	hint.stop()
	check(not hint.arrows_active() and not hint.compass_visible(), "stop() clears everything")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
