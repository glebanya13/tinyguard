extends SceneTree
## Screenshots of the thumb controls in battle: joystick size / height / side and the road
## compass, with a faked display cutout, and the controls tab of the settings. Needs a window.
## SHOT_DIR=<dir> SHOT_PREFIX=a godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##   --resolution 1920x1080 --script res://tools/shot_controls.gd

var _dir: String = ""
var _prefix: String = "a"


func _initialize() -> void:
	LevelCatalog.save_path = "user://shot_controls.cfg"
	LevelCatalog.erase_all()
	GameSettings.config_path = "user://shot_controls_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.config_path))
	_dir = OS.get_environment("SHOT_DIR")
	if OS.get_environment("SHOT_PREFIX") != "":
		_prefix = OS.get_environment("SHOT_PREFIX")
	LevelCatalog.selected_id = 2
	GameSettings.set_language("ru")
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(_dir.path_join("%s_%s.png" % [_prefix, shot_name]))
	print("saved ", shot_name)


func _run() -> void:
	await _frames(40)
	var main: Node = current_scene
	var hud: Hud = main.get_node("HUD")
	var hint: LaneHint = hud.get_node("Root").find_children("*", "LaneHint", false, false)[0]
	GameSettings.set_layout_value("minimap_mode", HudLayout.MAP_SHOW)
	hint.apply_settings()
	var cases := [
		["joy_small_std", 0, 1, 0],
		["joy_medium_std", 1, 1, 0],
		["joy_large_std", 2, 1, 0],
		["joy_medium_low", 1, 0, 0],
		["joy_medium_high", 1, 2, 0],
		["joy_medium_right", 1, 1, 1],
	]
	for c: Array in cases:
		GameSettings.set_layout_value("joystick_size", c[1])
		GameSettings.set_layout_value("joystick_pos", c[2])
		GameSettings.set_layout_value("joystick_side", c[3])
		hud.apply_layout()
		hint.apply_settings()
		hud.get_node("Root/Joystick").show()
		await _frames(3)
		await _shot(c[0])
	# a phone with a notch and a gesture bar
	ScreenUtil.fake_margins = Vector4(72, 0, 72, 32)
	GameSettings.set_layout_value("joystick_size", 2)
	GameSettings.set_layout_value("joystick_pos", 2)
	GameSettings.set_layout_value("joystick_side", 0)
	GameSettings.set_layout_value("minimap_size", 2)
	var safe: SafeArea = hud.get_node("Root/SafeArea")
	safe.apply()
	hud.apply_layout()
	hint.apply_settings()
	await _frames(3)
	await _shot("notch_large")
	ScreenUtil.fake_margins = Vector4.ZERO
	safe.apply()
	GameSettings.set_layout_value("joystick_size", 1)
	GameSettings.set_layout_value("joystick_pos", 1)
	GameSettings.set_layout_value("minimap_size", 1)
	hud.apply_layout()
	hint.apply_settings()
	var panel := SettingsPanel.new()
	hud.get_node("Root").add_child(panel)
	panel._on_tab(1)
	panel.open()
	paused = false
	await _frames(4)
	await _shot("settings_controls")
	quit()
