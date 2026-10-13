extends SceneTree
## Pause (P, Android back), speed x2, victory stars.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_pause.gd

const SAVE := "user://test_progress.cfg"

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	LevelCatalog.selected_id = 1
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func tap_key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		root.push_input(ev)
		await process_frame


func _run() -> void:
	for i in 10:
		await process_frame
	var main := current_scene
	await tap_key(KEY_F)
	check(is_equal_approx(Engine.time_scale, 2.0), "speed x2")
	await tap_key(KEY_P)
	check(paused, "paused by P")
	check(main.get_node("HUD/Root/EndScreen").visible, "pause menu shown")
	await tap_key(KEY_P)
	check(not paused, "resumed by P")
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(paused, "back button pauses")
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not paused, "back button resumes")
	check(
		(
			LevelCatalog.stars_for(20, 20) == 3
			and LevelCatalog.stars_for(10, 20) == 2
			and LevelCatalog.stars_for(3, 20) == 1
		),
		"stars rule"
	)
	main._on_all_waves_cleared()
	await process_frame
	check(
		(
			paused
			and main.get_node("HUD/Root/EndScreen/EndPanel/Content/Stars").get_child_count() == 3
		),
		"victory with stars"
	)
	check(LevelCatalog.stars(1) == 3, "stars saved")
	check(is_equal_approx(Engine.time_scale, 1.0), "speed reset at end")
	LevelCatalog.set_sound_on(false)
	check(AudioServer.is_bus_mute(0) and not LevelCatalog.sound_on(), "sound off saved and applied")
	LevelCatalog.set_sound_on(true)
	check(not AudioServer.is_bus_mute(0), "sound back on")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
