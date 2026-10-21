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

	print("=== 6. Workbench / Build Button & Menu ===")
	await _test_workbench_button_and_menu()

	print("=== 7. Interactive Placement Mode (Warcraft 3 style) ===")
	await _test_interactive_placement_mode()

	print("=== 8. Placement Mode Cancel & Cleanup ===")
	await _test_placement_mode_cancel()

	print("=== 9. Checkpoint Dynamic Tower Restoration ===")
	await _test_checkpoint_dynamic_tower_restoration()

	print("\nRESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _test_validation_logic() -> void:
	# Test paths clearance (>= 0.85m: allows building near the curb)
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 0, 0))
	curve.add_point(Vector3(10, 0, 0))
	var path3d := Path3D.new()
	path3d.curve = curve

	check(
		not bm.is_valid_tower_placement(Vector3(5, 0, 0.5), [path3d], [], Vector3.INF, [], null, false),
		"point 0.5m from path is rejected (< 0.85m)"
	)
	check(
		bm.is_valid_tower_placement(Vector3(5, 0, 1.0), [path3d], [], Vector3.INF, [], null, false),
		"point 1.0m from path is accepted near curb (>= 0.85m)"
	)
	check(
		bm.is_valid_tower_placement(Vector3(5, 0, 2.0), [path3d], [], Vector3.INF, [], null, false),
		"point 2.0m from path is accepted (>= 0.85m)"
	)

	# Test castle clearance (>= 2.0m)
	var castle_pos := Vector3(0, 0, 0)
	check(
		not bm.is_valid_tower_placement(Vector3(1.5, 0, 0), [], [], castle_pos, [], null, false),
		"point 1.5m from castle is rejected (< 2.0m)"
	)
	check(
		bm.is_valid_tower_placement(Vector3(2.5, 0, 0), [], [], castle_pos, [], null, false),
		"point 2.5m from castle is accepted (>= 2.0m)"
	)
	check(
		bm.is_valid_tower_placement(Vector3(3.5, 0, 0), [], [], castle_pos, [], null, false),
		"point 3.5m from castle is accepted (>= 2.0m)"
	)

	# Test trees clearance (>= 0.85m)
	var tree_pos := Vector3(5, 0, 5)
	check(
		not bm.is_valid_tower_placement(Vector3(5, 0, 5.5), [], [tree_pos], Vector3.INF, [], null, false),
		"point 0.5m from tree is rejected (< 0.85m)"
	)
	check(
		bm.is_valid_tower_placement(Vector3(5, 0, 6.2), [], [tree_pos], Vector3.INF, [], null, false),
		"point 1.2m from tree is accepted (>= 0.85m)"
	)

	# Test camps clearance (>= 2.0m)
	var camp_pos := Vector3(-5, 0, -5)
	check(
		not bm.is_valid_tower_placement(Vector3(-5, 0, -3.5), [], [], Vector3.INF, [camp_pos], null, false),
		"point 1.5m from camp is rejected (< 2.0m)"
	)
	check(
		bm.is_valid_tower_placement(Vector3(-5, 0, -2.5), [], [], Vector3.INF, [camp_pos], null, false),
		"point 2.5m from camp is accepted (>= 2.0m)"
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

	# Test built tower clearance (>= 1.2m between tower centers)
	# Free slots do NOT block placement
	var first_slot: TowerSlot = commands.slots[0]
	var first_slot_pos: Vector3 = first_slot.global_position
	check(
		bm.is_valid_tower_placement(first_slot_pos, [], [], Vector3.INF, []),
		"point on free slot is accepted"
	)
	# Build a tower on slot 0 to test collision with built towers
	first_slot.place_tower(bm.tower_types[0].scene)
	check(
		not bm.is_valid_tower_placement(first_slot_pos + Vector3(0.5, 0, 0), [], [], Vector3.INF, []),
		"point 0.5m from built tower is rejected (< 1.2m)"
	)
	check(
		bm.is_valid_tower_placement(first_slot_pos + Vector3(1.5, 0, 0), [], [], Vector3.INF, []),
		"point 1.5m from built tower is accepted (>= 1.2m)"
	)
	# Remove tower to leave scene clean
	first_slot.remove_tower()


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


func _test_workbench_button_and_menu() -> void:
	var hud: Hud = main.get_node("HUD")
	check(hud._workbench_button != null, "workbench button exists in HUD")
	check(hud._workbench_button.visible, "workbench button is visible")

	# Tap workbench button
	hud._workbench_button.pressed.emit()
	await frames(2)

	check(cards.workbench_open, "workbench menu opened on button press")
	check(hud._card.visible, "command card is visible")
	check(hud._button_ids.size() == 5, "build menu has 5 buttons (4 towers + cancel)")
	check(
		hud._button_ids.has(&"build_0")
		and hud._button_ids.has(&"build_1")
		and hud._button_ids.has(&"build_2")
		and hud._button_ids.has(&"build_3")
		and hud._button_ids.has(&"cancel"),
		"build menu has all 4 tower types and cancel"
	)

	# Cancel closes workbench
	cards.on_command_pressed(&"cancel")
	await frames(2)
	check(not cards.workbench_open, "workbench closed on cancel")


func _test_interactive_placement_mode() -> void:
	# Give resources
	gs.gold = 500
	gs.wood = 500

	# Open workbench and select Archer Tower
	cards.toggle_workbench()
	await frames(2)
	cards.on_command_pressed(&"build_0")
	await frames(2)

	check(cards.placement_mode, "entered placement mode")
	check(not cards.workbench_open, "workbench closed on tower select")
	check(cards.placement_tower_index == 0, "archer tower selected (index 0)")
	check(cards._placement_ghost != null and is_instance_valid(cards._placement_ghost), "3D preview ghost created")

	var fp: MeshInstance3D = cards._placement_ghost.get_node_or_null("FootprintRing") as MeshInstance3D
	var range_c: MeshInstance3D = cards._placement_ghost.get_node_or_null("RangeCircle") as MeshInstance3D
	check(fp != null, "ghost has FootprintRing")
	check(range_c != null, "ghost has RangeCircle")

	# Test invalid placement on enemy path
	var path_curve: Curve3D = sim.wave_manager.get_paths()[0].curve
	var path_pt: Vector3 = path_curve.get_point_position(path_curve.point_count / 2)
	cards.on_placement_moved(path_pt)
	await frames(2)

	check(not cards.placement_valid, "placement on enemy path is rejected")
	var fp_mat: StandardMaterial3D = fp.material_override as StandardMaterial3D
	check(fp_mat != null and fp_mat.albedo_color.r > 0.8, "footprint ring is RED on path")
	check(not range_c.visible, "range circle hidden on invalid spot")
	check(
		cards._placement_validation_message.contains("дорожк")
		or cards._placement_validation_message.contains("path")
		or cards._placement_validation_message == TranslationServer.translate("CARD_CANNOT_BUILD_PATH"),
		"hint shows cannot build on path warning"
	)

	# Test invalid placement on tree obstacle
	var tree_pos: Vector3 = sim.trees[0].global_position
	cards.on_placement_moved(tree_pos)
	await frames(2)
	check(not cards.placement_valid, "placement on tree is rejected")
	check(fp_mat.albedo_color.r > 0.8, "footprint ring is RED on obstacle")

	# Test valid placement on free ground
	var valid_pos := Vector3(-6.0, 0.0, -3.0)
	for x in range(-6, 7):
		for z in range(-6, 7):
			var p := Vector3(float(x), 0.0, float(z))
			if bm.is_valid_tower_placement(p, sim.wave_manager.get_paths(), sim.trees, cards.castle_position, main.get_tree().get_nodes_in_group(&"camps")):
				valid_pos = p
				break
	cards.on_placement_moved(valid_pos)
	await frames(2)

	check(cards.placement_valid, "placement on free ground is accepted")
	check(fp_mat.albedo_color.g > 0.8, "footprint ring is GREEN on free ground")
	check(range_c.visible, "range circle visible on valid spot")

	# Confirm build via dedicated on-screen Build button
	var count_before: int = commands.slots.size()
	hero.position = valid_pos
	cards.on_command_pressed(&"confirm_build")
	await frames(5)

	check(not cards.placement_mode, "exited placement mode on confirm build")
	check(cards._placement_ghost == null, "preview ghost cleaned up")
	check(commands.slots.size() == count_before + 1, "dynamic slot created on confirm build")
	var slot: TowerSlot = bm.selected_slot
	check(slot != null and not slot.is_free(), "tower constructed on dynamic slot")
	check(slot.tower != null and slot.tower.data.display_name == "TOWER_ARCHER_NAME", "archer tower built")


func _test_placement_mode_cancel() -> void:
	var initial_slots: int = commands.slots.size()
	cards.start_placement_mode(1) # Cannon
	await frames(2)

	check(cards.placement_mode, "in placement mode for cannon")
	check(cards._placement_ghost != null, "preview ghost exists")

	# Cancel placement mode
	cards.on_command_pressed(&"cancel")
	await frames(2)

	check(not cards.placement_mode, "placement mode exited cleanly on cancel")
	check(cards._placement_ghost == null, "preview ghost destroyed on cancel")
	check(commands.slots.size() == initial_slots, "no slot created on cancel")


func test_checkpoint_dynamic_tower_restoration() -> void:
	await _test_checkpoint_dynamic_tower_restoration()


func _test_checkpoint_dynamic_tower_restoration() -> void:
	# Provide ample resources
	gs.gold = 1000
	gs.wood = 1000

	# Clean up any leftover dynamic slots so we start with a clean level state
	var pre_existing: Array[TowerSlot] = []
	for s in commands.slots:
		if s != null and is_instance_valid(s) and s.is_dynamic:
			pre_existing.append(s)
	for s in pre_existing:
		if s.tower != null:
			s.remove_tower()
		bm.remove_dynamic_slot(s)
	await frames(2)

	var base_slot_count: int = commands.slots.size()

	# 1. Sets up a dynamic slot via bm.create_dynamic_slot(Vector3(4.0, 0.05, 4.0))
	var target_pos := Vector3(4.0, 0.05, 4.0)
	var dyn_slot: TowerSlot = bm.create_dynamic_slot(target_pos)
	check(dyn_slot != null, "dynamic slot created at (4.0, 0.05, 4.0)")
	check(dyn_slot.is_dynamic, "slot is marked is_dynamic")
	check(is_equal_approx(dyn_slot.global_position.x, 4.0), "dynamic slot X is 4.0")
	check(is_equal_approx(dyn_slot.global_position.z, 4.0), "dynamic slot Z is 4.0")

	# 2. Builds a tower on it (e.g. cannon or archer)
	var cannon_data: TowerData = bm.tower_types[1]
	var build_ok: bool = bm.build_on(dyn_slot, cannon_data)
	check(build_ok, "built cannon tower on dynamic slot")
	check(dyn_slot.tower != null, "dynamic slot contains built tower")
	check(dyn_slot.tower.level == 0, "tower initial level is 0")

	# 3. Upgrades it to level 1
	var upgrade_ok: bool = bm.upgrade(dyn_slot)
	check(upgrade_ok, "upgraded cannon tower on dynamic slot")
	check(dyn_slot.tower.level == 1, "tower level is 1 after upgrade")

	# 4. Calls _save_checkpoint() (or builds the checkpoint dictionary)
	main._save_checkpoint()
	var saved_data: Dictionary = BattleCheckpoint.load_checkpoint()
	check(not saved_data.is_empty(), "checkpoint dictionary saved and loaded successfully")

	var dynamic_found_in_save := false
	for t in saved_data.get("towers", []):
		if t.get("is_dynamic", false):
			dynamic_found_in_save = true
			check(t.get("level", 0) == 1, "saved dynamic tower level is 1")
			check(t.get("type", "") == "cannon", "saved dynamic tower type is cannon")
			var p: Array = t.get("pos", [])
			check(p.size() >= 3, "saved dynamic tower has 3D position")
			if p.size() >= 3:
				check(is_equal_approx(float(p[0]), 4.0), "saved pos X is approx 4.0")
				check(is_equal_approx(float(p[2]), 4.0), "saved pos Z is approx 4.0")
			break
	check(dynamic_found_in_save, "saved checkpoint contains dynamic tower data")

	# 5. Clears dynamic slots to simulate level reload
	var to_clear: Array[TowerSlot] = []
	for s in commands.slots:
		if s != null and is_instance_valid(s) and s.is_dynamic:
			to_clear.append(s)
	for s in to_clear:
		if s.tower != null:
			s.remove_tower()
		bm.remove_dynamic_slot(s)
	await frames(2)

	check(commands.slots.size() == base_slot_count, "all dynamic slots cleared to simulate level reload")

	# 6. Calls restore_from_checkpoint(saved_data)
	main.restore_from_checkpoint(saved_data)
	await frames(2)

	# 7. Asserts that the dynamic slot and tower exist at the restored position with level 1!
	var restored_dyn_slot: TowerSlot = null
	for s in commands.slots:
		if s != null and is_instance_valid(s) and s.is_dynamic:
			restored_dyn_slot = s
			break

	check(restored_dyn_slot != null, "restored dynamic slot exists in commands.slots")
	if restored_dyn_slot != null:
		check(restored_dyn_slot.is_dynamic, "restored slot is_dynamic is true")
		check(is_equal_approx(restored_dyn_slot.global_position.x, 4.0), "restored dynamic slot X is 4.0")
		check(is_equal_approx(restored_dyn_slot.global_position.z, 4.0), "restored dynamic slot Z is 4.0")
		check(restored_dyn_slot.tower != null, "restored dynamic slot has tower instance")
		if restored_dyn_slot.tower != null:
			check(restored_dyn_slot.tower.level == 1, "restored dynamic tower level is 1")
			check(
				restored_dyn_slot.tower.data != null and restored_dyn_slot.tower.data.resource_path.get_file().get_basename() == "cannon",
				"restored dynamic tower data is cannon"
			)
			check(restored_dyn_slot.tower.sim == sim, "restored dynamic tower is attached to sim")

		# Clean up restored dynamic slot
		if restored_dyn_slot.tower != null:
			restored_dyn_slot.remove_tower()
		bm.remove_dynamic_slot(restored_dyn_slot)

	BattleCheckpoint.clear_checkpoint()
