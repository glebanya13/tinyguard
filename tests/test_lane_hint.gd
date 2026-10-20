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
	GameSettings.set_layout_value("minimap_mode", HudLayout.MAP_WAVE)
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
	_check_map(main.level)
	var live: LaneMap = hint.compass_map()
	check(
		not live.routes.is_empty() and not live.dim.is_empty(), "the compass of the battle is built"
	)
	hint.stop()
	check(not hint.arrows_active() and not hint.compass_visible(), "stop() clears everything")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


## The compass map of the level: simplified roads, the screen's orientation, portals and side
## names inside the frame and clear of each other, for both languages and every panel size.
func _check_map(level: Dictionary) -> void:
	var font: Font = ThemeDB.fallback_font
	var paths: Array = level["paths"]
	var castle_world := Vector2(float(level["castle"][0]), float(level["castle"][1]))
	var starts: Array[Vector2] = []
	var most: int = 0
	for path: Array in paths:
		var raw := PackedVector2Array()
		for point: Array in path:
			raw.append(Vector2(float(point[0]), float(point[1])))
		most = maxi(most, LaneMap.simplify(raw, LaneMap.SIMPLIFY_METRES).size())
		starts.append(raw[0])
	check(most <= 12, "simplified roads have at most 12 points (most: %d)" % most)
	var texts := {}
	for locale: String in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		for box: Vector2 in HudLayout.MAP_SIZES:
			var map := LaneMap.new()
			map.build(level, box, font)
			var where: String = "%s %s level %s" % [locale, box, level["id"]]
			check(map.routes.size() == paths.size(), "a route per road " + where)
			var rim := Rect2(Vector2.ZERO, map.frame.size)
			check(
				absf(map.frame.position.y) < 0.01 and absf(map.frame.end.x - box.x) < 0.01,
				"the frame sits in the corner of the panel " + where
			)
			check(
				map.frame.size.x <= box.x + 0.01 and map.frame.size.y <= box.y + 0.01,
				"the frame is not bigger than the panel " + where
			)
			var inside: bool = rim.has_point(map.castle)
			for portal: Vector2 in map.portals:
				inside = inside and rim.has_point(portal)
			for route: PackedVector2Array in map.routes:
				check(
					route.size() >= 2 and route.size() <= 40, "a route is short: %d" % route.size()
				)
				for p: Vector2 in route:
					inside = inside and rim.grow(1.0).has_point(p)
			check(inside, "castle, portals and roads are inside the frame " + where)
			# Orientation: the top of the map is the top of the screen (the banner's north),
			# one scale on both axes: no turned or squeezed layout.
			var up: Vector2 = map.to_map(castle_world + LevelCatalog.SCREEN_UP * 10.0) - map.castle
			var right: Vector2 = (
				map.to_map(castle_world + LevelCatalog.SCREEN_RIGHT * 10.0) - map.castle
			)
			check(
				absf(up.x) < 0.01 and up.y < 0.0 and absf(right.y) < 0.01 and right.x > 0.0,
				"screen up is up and screen right is right on the map " + where
			)
			check(
				(
					absf(up.length() - 10.0 * map.scale) < 0.01
					and absf(right.length() - 10.0 * map.scale) < 0.01
				),
				"one scale on both axes " + where
			)
			# The side names: inside, apart, and each one in the direction the banner says.
			var seen: Array[Rect2] = []
			var clear: bool = true
			var named: bool = not map.labels.is_empty()
			for label: Dictionary in map.labels:
				var rect: Rect2 = label["rect"]
				clear = clear and rim.encloses(rect) and str(label["text"]) != ""
				for other: Rect2 in seen:
					clear = clear and not rect.intersects(other)
				seen.append(rect)
				var lane: int = label["lane"]
				var dx: float = map.portals[lane].x - map.castle.x
				var dy: float = map.portals[lane].y - map.castle.y
				var angle: float = atan2(dx, -dy)
				var shown: int = posmod(roundi(angle / (PI / 4.0)), 8)
				var said: int = LevelCatalog.screen_direction(starts[lane] - castle_world)
				named = named and shown == said
				texts[locale + str(lane) + str(said)] = label["text"]
			check(clear, "side names are inside the frame and do not overlap " + where)
			check(named, "every side name sits where the banner says " + where)
			var lit: Array[int] = [0, 1]
			map.set_lit(lit)
			check(not map.lit_core.is_empty() and not map.lit_air.is_empty(), "lit roads " + where)
			var none: Array[int] = []
			map.set_lit(none)
			check(map.lit_core.is_empty(), "no lit roads when none is lit " + where)
	var differ: bool = false
	for key: String in texts:
		if key.begins_with("ru") and texts.has("en" + key.substr(2)):
			differ = differ or texts[key] != texts["en" + key.substr(2)]
	check(differ, "side names are translated")
	TranslationServer.set_locale("ru")
