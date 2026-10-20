extends SceneTree
## Thumb-control layout: the joystick, the road compass (and its pin button), the sword and
## whirl buttons never overlap each other or the top bars, and stay inside the (safe) screen
## at 1280x720 and 2340x1080 (canvas 1560x720) with every size / height / side / compass
## setting. Also: the HUD really places the joystick where HudLayout says, the radius scales
## and the settings are saved.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_hud_layout.gd

const SAVE := "user://test_progress.cfg"
const SETTINGS := "user://test_hud_layout_settings.cfg"
## Canvas sizes after the stretch (expand) for the two reference screens, and a notch.
const CANVASES: Array[Vector2] = [Vector2(1280, 720), Vector2(1560, 720)]
const NOTCH := Vector4(48.0, 0.0, 48.0, 24.0)

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	GameSettings.config_path = SETTINGS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	LevelCatalog.selected_id = 1
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func _run() -> void:
	_math()
	await _live()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _math() -> void:
	var bad: PackedStringArray = []
	var combos := 0
	for canvas in CANVASES:
		for inset in [Vector4.ZERO, NOTCH]:
			# The HUD root is already inset by the safe area: its own size shrinks.
			var size: Vector2 = canvas - Vector2(inset.x + inset.z, inset.y + inset.w)
			var bounds := Rect2(Vector2.ZERO, size)
			for js in 3:
				for jp in 3:
					for side in 2:
						for ms in 3:
							for mode in 3:
								combos += 1
								var tag := (
									"%dx%d inset=%s js%d jp%d s%d ms%d m%d"
									% [
										canvas.x,
										canvas.y,
										inset != Vector4.ZERO,
										js,
										jp,
										side,
										ms,
										mode
									]
								)
								var r: Dictionary = HudLayout.rects(size, js, jp, side, ms, mode)
								var joy: Rect2 = r["joystick"]
								var items: Array = ["joystick", "attack", "spin"]
								if r.has("map"):
									items += ["map", "pin", "strat"]
								for key: String in items:
									if not bounds.encloses(r[key]):
										bad.append("%s: %s outside" % [tag, key])
								for key: String in ["attack", "spin", "top_left", "top_right"]:
									if joy.intersects(r[key]):
										bad.append("%s: joystick over %s" % [tag, key])
								if r.has("map"):
									for key: String in ["attack", "spin", "top_left", "top_right"]:
										if (r["map"] as Rect2).intersects(r[key]):
											bad.append("%s: map over %s" % [tag, key])
									if joy.intersects(r["map"]) or joy.intersects(r["pin"]) or joy.intersects(r["strat"]):
										bad.append("%s: joystick over the compass" % tag)
									if (r["strat"] as Rect2).intersects(r["map"]):
										bad.append("%s: strat over map" % tag)
									if (r["pin"] as Rect2).intersects(r["strat"]):
										bad.append("%s: pin over strat" % tag)
									if (r["strat"] as Rect2).position.y <= (r["pin"] as Rect2).position.y:
										bad.append("%s: strat not below pin" % tag)
	check(
		bad.is_empty(),
		"%d layouts: no overlaps, all inside the screen %s" % [combos, ", ".join(bad.slice(0, 4))]
	)
	var sides: Array[float] = []
	for js in 3:
		sides.append(
			(HudLayout.rects(Vector2(1280, 720), js, 1, 0, 1, 2)["joystick"] as Rect2).size.x
		)
	check(sides[0] < sides[1] and sides[1] < sides[2], "joystick sizes grow")
	var low: float = (
		(HudLayout.rects(Vector2(1280, 720), 1, 0, 0, 1, 1)["joystick"] as Rect2).position.y
	)
	var high: float = (
		(HudLayout.rects(Vector2(1280, 720), 1, 2, 0, 1, 1)["joystick"] as Rect2).position.y
	)
	check(high < low, "a higher joystick sits higher")
	var right: Rect2 = HudLayout.rects(Vector2(1280, 720), 1, 1, 1, 1, 2)["joystick"]
	check(right.position.x > 640.0, "the right side puts it on the right")


func _live() -> void:
	for i in 10:
		await process_frame
	root.size = Vector2i(1280, 720)
	for i in 3:
		await process_frame
	var main: Node = current_scene
	var hud: Hud = main.get_node("HUD")
	var joy: Control = hud.get_node("Root/Joystick")
	var hint: LaneHint = hud.get_node("Root").find_children("*", "LaneHint", false, false)[0]
	check(
		GameSettings.minimap_mode() == GameSettings.MAP_MODE_ALWAYS,
		"MAP_MODE_ALWAYS is default minimap mode"
	)
	for js in 3:
		GameSettings.set_layout_value("joystick_size", js)
		hud.apply_layout()
		await process_frame
		var want: Rect2 = HudLayout.current(hud.get_node("Root").size)["joystick"]
		var got := Rect2(joy.position, joy.size)
		check(
			got.is_equal_approx(want), "joystick %d placed by HudLayout %s vs %s" % [js, got, want]
		)
		check(
			is_equal_approx(joy.get("radius") as float, want.size.x * HudLayout.JOY_RADIUS_RATIO),
			"radius scales with the size"
		)
	GameSettings.set_layout_value("minimap_mode", HudLayout.MAP_HIDE)
	hint.apply_settings()
	hint.toggle_compass()
	check(not hint.compass_visible(), "mode hide: no compass")
	GameSettings.set_layout_value("minimap_mode", HudLayout.MAP_SHOW)
	hint.apply_settings()
	check(hint.compass_visible(), "mode always: the compass is open")
	check(
		GameSettings.LAYOUT_DEFAULTS["minimap_mode"] == GameSettings.MAP_MODE_ALWAYS,
		"MAP_MODE_ALWAYS является режимом по умолчанию"
	)
	var pin: Control = hint.get_node("CompassButton")
	var rect: Rect2 = HudLayout.current(hint.size)["pin"]
	check(pin.position.is_equal_approx(rect.position), "pin button placed by HudLayout")
	check(pin.position.x > 600.0 and pin.position.y < 300.0, "pin button is in the top-right quarter")
	var strat_btn: Control = hint.get_node("StrategicViewButton")
	var strat_rect: Rect2 = HudLayout.current(hint.size)["strat"]
	check(strat_btn.position.is_equal_approx(strat_rect.position), "strat button placed by HudLayout")
	check(strat_btn.position.y > pin.position.y, "strat button sits vertically below compass button")
	check(is_equal_approx(strat_btn.position.x, pin.position.x), "strat button aligns horizontally with compass button")
	check(strat_btn.position.x > 600.0 and strat_btn.position.y < 300.0, "strat button is in the top-right quarter")
	var map_rect: Rect2 = HudLayout.current(hint.size)["map"]
	var pin_box := Rect2(pin.position, pin.size)
	var strat_box := Rect2(strat_btn.position, strat_btn.size)
	check(not pin_box.intersects(strat_box), "pin and strat buttons do not overlap")
	check(not pin_box.intersects(map_rect), "pin button does not overlap minimap")
	check(not strat_box.intersects(map_rect), "strat button does not overlap minimap")
	# Floating joystick: touching in the left zone centers base at touch position,
	# releasing returns base to home position.
	GameSettings.set_layout_value("joystick_side", 0)
	hud.apply_layout()
	await process_frame
	var want_home: Rect2 = HudLayout.current(hud.get_node("Root").size)["joystick"]
	var touch_pos := Vector2(160.0, 360.0)
	var touch_down := InputEventScreenTouch.new()
	touch_down.pressed = true
	touch_down.position = touch_pos
	joy._input(touch_down)
	check(
		joy.get_base_center().is_equal_approx(touch_pos),
		"Касание в левой зоне джойстика центрирует базу плавающего джойстика в точке касания"
	)
	var touch_up := InputEventScreenTouch.new()
	touch_up.pressed = false
	touch_up.position = touch_pos
	joy._input(touch_up)
	check(
		joy.position.is_equal_approx(want_home.position),
		"отпускание возвращает джойстик в исходное базовое положение"
	)
	GameSettings.set_layout_value("joystick_side", 1)
	hud.apply_layout()
	await process_frame
	check(joy.position.x > 640.0, "joystick moved to the right side live")
	var panel := SettingsPanel.new()
	hud.get_node("Root").add_child(panel)
	var fired := [0]
	panel.layout_changed.connect(func() -> void: fired[0] += 1)
	panel._on_tab(1)
	panel.open()
	var button: Button = panel.find_child("Opt_joystick_size_2", true, false)
	check(
		button != null and button.custom_minimum_size.y >= 84.0, "option buttons are at least 84 px"
	)
	button.pressed.emit()
	check(
		fired[0] == 1 and GameSettings.joystick_size() == 2, "an option saves and announces itself"
	)
	var tap_btn: Button = panel.find_child("TapToMoveToggle", true, false)
	check(tap_btn != null, "TapToMoveToggle button exists")
	var auto_btn: Button = panel.find_child("AutoAttackToggle", true, false)
	check(auto_btn != null, "AutoAttackToggle button exists")
	var initial_tap: bool = GameSettings.is_tap_to_move()
	tap_btn.pressed.emit()
	check(GameSettings.is_tap_to_move() != initial_tap, "tap_to_move toggled")
	tap_btn.pressed.emit()
	check(GameSettings.is_tap_to_move() == initial_tap, "tap_to_move restored")
	var initial_auto: bool = GameSettings.is_auto_attack()
	auto_btn.pressed.emit()
	check(GameSettings.is_auto_attack() != initial_auto, "auto_attack toggled")
	auto_btn.pressed.emit()
	check(GameSettings.is_auto_attack() == initial_auto, "auto_attack restored")
	# Graphics quality: four big switches on the general tab, saved on the device.
	panel._on_tab(0)
	panel.open()
	var gfx: Button = panel.find_child("Gfx_1", true, false)
	check(gfx != null and gfx.custom_minimum_size.y >= 84.0, "graphics buttons are at least 84 px")
	check(
		panel.find_children("Gfx_*", "Button", true, false).size() == 4, "auto, low, medium, high"
	)
	gfx.pressed.emit()
	check(GameSettings.graphics() == GameSettings.GFX_LOW, "the graphics choice is saved")
