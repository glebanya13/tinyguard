extends SceneTree
## Tests Warcraft-style free tower placement:
## - is_valid_tower_placement validation against paths, trees, castle, camps, slots, bounds
## - create_dynamic_slot snapping to 0.5m grid
## - CardController ground tap interaction: valid builds, invalid rejects
## - Unbuilt dynamic slot cleanup on cancel / dismissal
## - WalkGrid blocking when dynamic tower placed and unblocking when sold
## Run with:
## /Applications/Godot.app/Contents/MacOS/Godot --headless --fixed-fps 60 --path . --script res://tests/test_warcraft_placement.gd

const SAVE := "user://test_warcraft_placement.cfg"

var fails := 0
var main: Node = null
var gs: GameState = null
var bm: BuildManager = null
var hero: Hero = null
var sim: Sim = null
var cards: CardController = null
var commands: GameCommands = null
var walk_grid: WalkGrid = null


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


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await frames(10)
	main = current_scene
	gs = main.get_node("GameState")
	bm = main.get_node("BuildManager")
	hero = main.get_node("Level/Hero")
	sim = main.get_node("Sim")
	cards = main.cards
	commands = main.get_node("GameCommands")
	walk_grid = main.walk_grid

	# Prevent waves from disrupting test
	(main.get_node("WaveManager") as WaveManager).stop()

	print("=== 1. Validation Logic (is_valid_tower_placement) ===")
	_test_validation_logic()

	print("=== 2. Dynamic Slot Creation & Grid Snapping ===")
	_test_slot_creation()

	print("=== 3. CardController Empty Ground Tap & Warcraft Placement ===")
	await _test_ground_tap_interaction()

	print("=== 4. Cancel & Cleanup of Unbuilt Dynamic Slot ===")
	await _test_cancel_cleanup()

	print("=== 5. WalkGrid Blocking on Dynamic Slot ===")
	await _test_walkgrid_blocking()

	print("\nRESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _test_validation_logic() -> void:
	# Test paths clearance (>= 1.35m)
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 0, 0))
	curve.add_point(Vector3(10, 0, 0))
	var path3d := Path3D.new()
	path3d.curve = curve

	check(
		not bm.is_valid_tower_placement(Vector3(5, 0, 0.5), [path3d], [], Vector3.INF, [], null, false),
		"point 0.5m from path is rejected (< 1.35m)"
	)
	check(
		not bm.is_valid_tower_placement(Vector3(5, 0, 1.2), [path3d], [], Vector3.INF, [], null, false),
		"point 1.2m from path is rejected (< 1.35m)"
	)
	check(
		bm.is_valid_tower_placement(Vector3(5, 0, 2.0), [path3d], [], Vector3.INF, [], null, false),
		"point 2.0m from path is accepted (>= 1.35m)"
	)

	# Test castle clearance (>= 3.0m)
	var castle_pos := Vector3(0, 0, 0)
	check(
		not bm.is_valid_tower_placement(Vector3(1.5, 0, 0), [], [], castle_pos, [], null, false),
		"point 1.5m from castle is rejected (< 3.0m)"
	)
	check(
		not bm.is_valid_tower_placement(Vector3(2.8, 0, 0), [], [], castle_pos, [], null, false),
		"point 2.8m from castle is rejected (< 3.0m)"
	)
	check(
		bm.is_valid_tower_placement(Vector3(3.5, 0, 0), [], [], castle_pos, [], null, false),
		"point 3.5m from castle is accepted (>= 3.0m)"
	)

	# Test trees clearance (>= 1.5m)
	var tree_pos := Vector3(5, 0, 5)
	check(
		not bm.is_valid_tower_placement(Vector3(5, 0, 5.8), [], [tree_pos], Vector3.INF, [], null, false),
		"point 0.8m from tree is rejected (< 1.5m)"
	)
	check(
		bm.is_valid_tower_placement(Vector3(5, 0, 6.8), [], [tree_pos], Vector3.INF, [], null, false),
		"point 1.8m from tree is accepted (>= 1.5m)"
	)

	# Test camps clearance (>= 3.0m)
	var camp_pos := Vector3(-5, 0, -5)
	check(
		not bm.is_valid_tower_placement(Vector3(-5, 0, -3.0), [], [], Vector3.INF, [camp_pos], null, false),
		"point 2.0m from camp is rejected (< 3.0m)"
	)
	check(
		bm.is_valid_tower_placement(Vector3(-5, 0, -1.5), [], [], Vector3.INF, [camp_pos], null, false),
		"point 3.5m from camp is accepted (>= 3.0m)"
	)

	# Test level bounds
	bm.bounds = Rect2(-10, -10, 20, 20)
	check(
		not bm.is_valid_tower_placement(Vector3(15, 0, 0), [], [], Vector3.INF, [], null, false),
		"point outside bounds is rejected"
	)
	check(
		bm.is_valid_tower_placement(Vector3(4, 0, 4), [], [], Vector3.INF, [], null, false),
		"point inside bounds is accepted"
	)
	# Restore bounds
	bm.bounds = LevelBuilder.map_rect(main.level)

	# Test slot clearance with real level slots (>= 2.0m)
	var first_slot_pos: Vector3 = commands.slots[0].global_position
	check(
		not bm.is_valid_tower_placement(first_slot_pos + Vector3(0.5, 0, 0), [], [], Vector3.INF, []),
		"point 0.5m from existing slot is rejected (< 2.0m)"
	)
	check(
		not bm.is_valid_tower_placement(first_slot_pos + Vector3(1.8, 0, 0), [], [], Vector3.INF, []),
		"point 1.8m from existing slot is rejected (< 2.0m)"
	)


func _test_slot_creation() -> void:
	var unsnapped := Vector3(2.13, 0.0, 4.37)
	var slot := bm.create_dynamic_slot(unsnapped)
	check(slot != null, "dynamic slot instantiated")
	check(slot.is_dynamic, "slot marked is_dynamic")
	check(is_equal_approx(slot.position.x, 2.0), "X coordinate snapped to 2.0 (from 2.13)")
	check(is_equal_approx(slot.position.z, 4.5), "Z coordinate snapped to 4.5 (from 4.37)")
	check(slot.slot_id == commands.slots.size() - 1, "slot added to commands.slots with valid slot_id")

	# Clean it up
	bm.remove_dynamic_slot(slot)
	check(commands.slots.find(slot) == -1, "dynamic slot removed cleanly from commands.slots")


func _test_ground_tap_interaction() -> void:
	var initial_slots_count: int = commands.slots.size()
	gs.gold = 500
	gs.wood = 500

	# Find a clear valid spot on level 1: e.g. (3.0, 0.0, -3.0) or check validity
	var test_pos := Vector3(3.0, 0.0, -3.0)
	var valid := bm.is_valid_tower_placement(
		test_pos,
		sim.wave_manager.get_paths(),
		sim.trees,
		cards.castle_position,
		main.get_tree().get_nodes_in_group(&"camps")
	)

	# Try an alternate clear spot if needed
	if not valid:
		for x in range(-6, 7):
			for z in range(-6, 7):
				var p := Vector3(float(x), 0.0, float(z))
				if bm.is_valid_tower_placement(p, sim.wave_manager.get_paths(), sim.trees, cards.castle_position, main.get_tree().get_nodes_in_group(&"camps")):
					test_pos = p
					valid = true
					break
			if valid:
				break

	check(valid, "found valid placement spot on level: %s" % test_pos)

	# Tap ground at valid spot
	cards.on_ground_tapped(test_pos)
	await frames(2)

	check(commands.slots.size() == initial_slots_count + 1, "dynamic slot created on valid ground tap")
	var dyn_slot: TowerSlot = bm.selected_slot
	check(dyn_slot != null and dyn_slot.is_dynamic, "dynamic slot is selected")
	check(dyn_slot.is_free(), "dynamic slot is currently free")

	# Build an Archer Tower (build_0)
	hero.position = dyn_slot.global_position # teleport hero close so build executes immediately
	cards.on_command_pressed(&"build_0")
	await frames(5)

	check(not dyn_slot.is_free(), "tower successfully built on dynamic slot")
	check(dyn_slot.tower != null, "dyn_slot has tower attached")
	check(dyn_slot.tower.sim == sim, "tower attached to sim")


func _test_cancel_cleanup() -> void:
	var initial_slots_count: int = commands.slots.size()

	# Find another valid spot
	var test_pos := Vector3.ZERO
	var valid := false
	for x in range(-7, 8):
		for z in range(-7, 8):
			var p := Vector3(float(x) + 0.5, 0.0, float(z) + 0.5)
			if bm.is_valid_tower_placement(p, sim.wave_manager.get_paths(), sim.trees, cards.castle_position, main.get_tree().get_nodes_in_group(&"camps")):
				test_pos = p
				valid = true
				break
		if valid:
			break

	check(valid, "found second spot for cancel test: %s" % test_pos)
	cards.on_ground_tapped(test_pos)
	await frames(2)

	check(commands.slots.size() == initial_slots_count + 1, "slot created before cancel")
	var slot: TowerSlot = bm.selected_slot
	check(slot != null and slot.is_dynamic, "slot selected")

	# Press Cancel
	cards.on_command_pressed(&"cancel")
	await frames(2)

	check(commands.slots.size() == initial_slots_count, "unbuilt dynamic slot was removed from commands.slots on cancel")
	check(bm.selected_slot == null, "selection cleared on cancel")


func _test_walkgrid_blocking() -> void:
	# Find a valid spot
	var test_pos := Vector3.ZERO
	var valid := false
	for x in range(-7, 8):
		for z in range(-7, 8):
			var p := Vector3(float(x), 0.0, float(z))
			if bm.is_valid_tower_placement(p, sim.wave_manager.get_paths(), sim.trees, cards.castle_position, main.get_tree().get_nodes_in_group(&"camps")):
				test_pos = p
				valid = true
				break
		if valid:
			break

	check(valid, "found spot for walkgrid test: %s" % test_pos)
	var pos_2d := Vector2(test_pos.x, test_pos.z)
	check(walk_grid.is_free(pos_2d), "walk_grid cell is initially free")

	# Tap and build
	cards.on_ground_tapped(test_pos)
	await frames(2)
	var slot: TowerSlot = bm.selected_slot
	hero.position = slot.global_position
	cards.on_command_pressed(&"build_1") # Cannon
	await frames(5)

	check(not walk_grid.is_free(pos_2d), "walk_grid cell is blocked after tower is built on dynamic slot")

	# Sell tower
	bm.select_slot(slot)
	cards.on_command_pressed(&"sell")
	await frames(5)

	check(walk_grid.is_free(pos_2d), "walk_grid cell is unblocked after tower is sold")
