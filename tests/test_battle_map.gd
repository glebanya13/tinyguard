extends SceneTree
## Playtest 2026-10-24: the minimap button opens the battle map (the whole field from above with
## every unit), the mercenaries' tent shows its guard area, single trees grow in groves and a
## swing chops one tree.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_battle_map.gd

var _failures: int = 0


func _ok(condition: bool, text: String) -> void:
	if condition:
		print("  ok   %s" % text)
	else:
		_failures += 1
		print("  FAIL %s" % text)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	LevelCatalog.selected_id = 1
	LevelCatalog.endless = false
	LevelCatalog.tutorial = false
	LevelCatalog.inspect_map = false
	change_scene_to_file("res://scenes/main.tscn")
	for i in 6:
		await process_frame
	for i in 6:
		await physics_frame
	var main: Node = current_scene
	var sim: Sim = main.get_node("Sim")
	sim.manual = true
	var hint: LaneHint = main._lane_hint
	var map: BattleMap = main._battle_map

	print("-- 1. The battle map")
	_ok(map != null and not map.visible, "the battle map is there, closed")
	(hint.get_node("CompassButton") as Button).pressed.emit()
	_ok(map.visible, "the minimap button opens it")
	(main.get_node("WaveManager") as WaveManager).start_next_wave()
	for i in 90:
		sim.step()
	await process_frame
	map.queue_redraw()
	await process_frame
	_ok(not sim.enemies.is_empty(), "enemies are on the field while it is open")
	var castle: Vector2 = map.screen_of(Vector2(0.0, 0.0))
	var screen := Rect2(Vector2.ZERO, map.size)
	_ok(screen.has_point(castle), "the castle is drawn on the screen (%s)" % castle)
	for enemy: Enemy in sim.enemies:
		var at: Vector2 = map.screen_of(Vector2(enemy.sim_position().x, enemy.sim_position().z))
		if not screen.has_point(at):
			_ok(false, "enemy %d is drawn off the screen (%s)" % [enemy.id, at])
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	map._gui_input(tap)
	_ok(not map.visible, "a tap closes it")
	map.open()
	main.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_ok(not map.visible and not paused, "'Back' closes it first")

	print("-- 2. The mercenaries' guard area")
	var camp: CampStructures.MercenaryCamp = main.builder.mercenary_camp
	_ok(not camp.guard_area_visible(), "the guard area is hidden while the tent is not selected")
	camp.set_selected(true)
	_ok(camp.guard_area_visible(), "selecting the tent shows its guard area")
	_ok(
		Mercenary.guard_reach() > Mercenary.DETECTION_RADIUS,
		"the area is the reach from the gate (%.1f m)" % Mercenary.guard_reach()
	)
	camp.set_selected(false)

	print("-- 3. Groves and one tree a swing")
	var field: Array[WoodTree] = []
	for tree: WoodTree in sim.trees:
		if not tree.is_thicket:
			field.append(tree)
	var with_neighbour: int = 0
	for tree: WoodTree in field:
		for other: WoodTree in field:
			if other != tree and other.global_position.distance_to(tree.global_position) < 1.7:
				with_neighbour += 1
				break
	_ok(
		with_neighbour * 10 >= field.size() * 8,
		"most field trees stand in groves (%d of %d)" % [with_neighbour, field.size()]
	)
	var level: Dictionary = main.level
	var spots: Array[Vector2] = [Vector2(6.0, 7.5)]
	var empty: Array[Vector2] = []
	var once: Array = TreeClusters.neighbours(level, spots, empty, empty)
	var again: Array = TreeClusters.neighbours(level, spots, empty, empty)
	_ok(once == again, "the groves are the same every time (replays, co-op)")
	for road: PackedVector2Array in LevelCatalog.routes(level):
		for tree: WoodTree in field:
			var at := Vector2(tree.global_position.x, tree.global_position.z)
			for k in road.size() - 1:
				var near: Vector2 = Geometry2D.get_closest_point_to_segment(
					at, road[k], road[k + 1]
				)
				if at.distance_to(near) < 1.0:
					_ok(false, "a tree stands on a road at %s" % at)
	var hero: Hero = main.get_node("Level/Hero")
	var pair: Array[WoodTree] = []
	for tree: WoodTree in field:
		for other: WoodTree in field:
			if other != tree and other.global_position.distance_to(tree.global_position) < 1.4:
				pair = [tree, other]
				break
		if not pair.is_empty():
			break
	_ok(not pair.is_empty(), "two trees stand close together")
	if not pair.is_empty():
		var middle: Vector3 = (pair[0].global_position + pair[1].global_position) * 0.5
		var side: Vector3 = (pair[1].global_position - pair[0].global_position).cross(Vector3.UP)
		var origin: Vector3 = middle + side.normalized() * 0.9
		var forward: Vector3 = (middle - origin).normalized()
		var before: Array[int] = [pair[0].hits_left(), pair[1].hits_left()]
		var gained: Array[int] = [0]
		hero.wood_gathered.connect(func(amount: int, _at: Vector3) -> void: gained[0] += amount)
		hero._strike(origin, atan2(forward.x, forward.z))
		var hit: int = (before[0] - pair[0].hits_left()) + (before[1] - pair[1].hits_left())
		_ok(hit == 1, "one swing chops one tree, not both (%d)" % hit)
		_ok(gained[0] > 0, "and gives its wood (%d)" % gained[0])

	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
