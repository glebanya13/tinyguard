extends SceneTree
## Tests Area/Zone Tower Placement Tap Reach and Co-op Movement Smoothing & Prediction.
## Run with: godot --headless --fixed-fps 60 --path . --script res://tests/test_coop_smoothing_and_area.gd

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
	print("-- 1. Area/Zone Tower Placement Tap Reach")
	LevelCatalog.selected_id = 1
	change_scene_to_file("res://scenes/main.tscn")

	for i in 6:
		await process_frame
	for i in 6:
		await physics_frame

	var main_node = current_scene
	var bm: BuildManager = main_node.get_node("BuildManager")
	var commands: GameCommands = main_node.get_node("GameCommands")
	var slot0: TowerSlot = commands.slots[0]
	var camera: CameraFollow = main_node.get_node("Camera")

	# Tap 0.9m offset from slot 0 on the ground plane (outside 0.5m cylinder collider)
	var near_point: Vector3 = slot0.global_position + Vector3(0.9, 0.0, 0.0)
	var near_screen: Vector2 = camera.unproject_position(near_point)
	bm.clear_selection()
	bm.handle_tap(near_screen)
	_ok(bm.selected_slot == slot0, "Tap in zone (0.9m from slot center) successfully selects slot 0")

	# Tap 3.0m away (outside 1.35m zone radius)
	var far_point: Vector3 = slot0.global_position + Vector3(3.0, 0.0, 0.0)
	var far_screen: Vector2 = camera.unproject_position(far_point)
	bm.clear_selection()
	bm.handle_tap(far_screen)
	_ok(bm.selected_slot == null, "Tap outside zone (3.0m away) does not select slot")

	print("-- 2. Co-op Movement Sync & Protocol")
	_ok(GameCommand.WIRE_NAMES.get(GameCommand.Type.MOVE_TO) == "move_to", "WIRE_NAMES has move_to")
	_ok(int(GameCommand.ARG_COUNTS.get(GameCommand.Type.MOVE_TO)) == 2, "ARG_COUNTS for move_to is 2")
	var move_cmd := GameCommand.hero_move(Vector3(12.5, 0.0, -8.2))
	_ok(move_cmd.type == GameCommand.Type.MOVE_TO, "hero_move creates MOVE_TO command")
	_ok(move_cmd.args == [12500, -8200], "hero_move correctly serializes mm coordinates")

	var decoded: GameCommand = GameCommand.from_wire("move_to", [12500, -8200], 1, 45)
	_ok(decoded != null and decoded.type == GameCommand.Type.MOVE_TO, "from_wire decodes move_to command")

	print("-- 3. Ghost Hero Adaptive Catch-Up")
	var hero: Hero = main_node.get_node("Level/Hero")
	var ghost: Hero = preload("res://scenes/hero.tscn").instantiate()
	ghost.is_ghost = true
	ghost.sim = main_node.get_node("Sim")
	main_node.add_child(ghost)
	ghost.global_position = Vector3(0.0, 0.0, 0.0)
	ghost.ghost_goto(Vector3(5.0, 0.0, 0.0))

	# Advance 0.1s delta: adaptive speed should cover significant ground
	ghost._glide(0.1)
	_ok(ghost.position.x > 0.3, "Ghost catches up smoothly with adaptive speed (x: %.2f)" % ghost.position.x)
	ghost.queue_free()

	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
