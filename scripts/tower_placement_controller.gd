class_name TowerPlacementController
extends RefCounted
## Manages free Warcraft-style tower placement:
## - Interactive placement mode with 3D ghost preview, footprint and range circles
## - Real-time validation against creep paths, obstacles, trees, camps and castle
## - Dynamic TowerSlot creation, grid snapping (0.5m), and unbuilt slot cleanup
## - Empty ground tap handling and placement confirmation

signal placement_started(tower_index: int)
signal placement_updated(position: Vector3, valid: bool, message: String)
signal placement_confirmed(slot: TowerSlot, tower_index: int)
signal placement_cancelled

var placement_mode: bool = false
var placement_tower_index: int = -1
var placement_position: Vector3 = Vector3.ZERO
var placement_valid: bool = false
var validation_message: String = ""

var castle_position: Vector3 = Vector3(INF, INF, INF)
var active_dynamic_slot: TowerSlot = null
var ghost: Node3D = null
var placement_ring: MeshInstance3D = null

var _hero: Hero = null
var _build_manager: BuildManager = null
var _commands: GameCommands = null
var _game_state: GameState = null
var _sim: Sim = null
var _range_ring: MeshInstance3D = null
var _invalid_preview_tween: Tween = null


func setup(
	hero: Hero,
	build_manager: BuildManager,
	commands: GameCommands,
	game_state: GameState,
	sim: Sim,
	range_ring: MeshInstance3D
) -> void:
	_hero = hero
	_build_manager = build_manager
	_commands = commands
	_game_state = game_state
	_sim = sim
	_range_ring = range_ring
	if placement_ring == null and _range_ring != null:
		placement_ring = _create_placement_ring()


func start_placement_mode(tower_index: int) -> void:
	if _build_manager == null or tower_index < 0 or tower_index >= _build_manager.tower_types.size():
		return
	if _build_manager != null:
		_build_manager.clear_selection()
	cleanup_unbuilt_dynamic_slot()

	placement_mode = true
	placement_tower_index = tower_index
	if _build_manager != null:
		_build_manager.placement_mode_active = true

	var start_pos := Vector3.ZERO
	if _hero != null:
		start_pos = _hero.global_position
	var snapped_x := roundf(start_pos.x * 2.0) / 2.0
	var snapped_z := roundf(start_pos.z * 2.0) / 2.0
	placement_position = Vector3(snapped_x, 0.05, snapped_z)

	_destroy_ghost()

	var data: TowerData = _build_manager.tower_types[placement_tower_index]
	ghost = _create_placement_ghost(data)
	update_placement_position(placement_position)
	placement_started.emit(tower_index)


func update_placement_position(pos: Vector3) -> void:
	if not placement_mode or _build_manager == null or placement_tower_index < 0:
		return
	var snapped_x := roundf(pos.x * 2.0) / 2.0
	var snapped_z := roundf(pos.z * 2.0) / 2.0
	var test_pos := Vector3(snapped_x, 0.05, snapped_z)

	# If near an existing free slot, snap directly to it for easy placement on prepared slots
	if _commands != null:
		for s in _commands.slots:
			if s != null and is_instance_valid(s) and s.is_free():
				var d: float = Vector2(s.global_position.x - pos.x, s.global_position.z - pos.z).length()
				if d <= 0.85:
					test_pos = Vector3(s.global_position.x, 0.05, s.global_position.z)
					break

	placement_position = test_pos

	if ghost != null and is_instance_valid(ghost):
		ghost.global_position = placement_position

	var paths: Array = _get_paths()
	var trees: Array = _get_trees()
	var camps: Array = _get_camps()

	var val_result: Dictionary = _build_manager.validate_placement_detailed(
		placement_position, paths, trees, castle_position, camps, active_dynamic_slot
	)
	placement_valid = val_result.get("valid", false)
	validation_message = val_result.get("message", "")

	_update_ghost_appearance(placement_valid)
	placement_updated.emit(placement_position, placement_valid, validation_message)


## Confirms the placement: cleans up ghost, creates or finds the slot, and returns order parameters.
func confirm_placement() -> Dictionary:
	if not placement_mode or not placement_valid:
		return {"success": false, "slot": null, "tower_index": -1, "cmd_id": &""}
	var tower_idx: int = placement_tower_index
	var build_pos: Vector3 = placement_position
	var data: TowerData = _build_manager.tower_types[tower_idx]
	if _game_state != null and not _game_state.can_afford(Vector2i(data.cost_gold, data.cost_wood)):
		return {"success": false, "slot": null, "tower_index": -1, "cmd_id": &""}

	# End placement mode and clean up ghost
	cancel_placement()

	# Check if placement corresponds to an existing free slot
	var slot: TowerSlot = null
	if _commands != null:
		for s in _commands.slots:
			if s != null and is_instance_valid(s) and s.is_free():
				var d: float = Vector2(s.global_position.x - build_pos.x, s.global_position.z - build_pos.z).length()
				if d <= 0.85:
					slot = s
					break

	if slot == null:
		slot = _build_manager.create_dynamic_slot(build_pos)
		active_dynamic_slot = slot

	var cmd_id := StringName("build_%d" % tower_idx)
	placement_confirmed.emit(slot, tower_idx)
	return {"success": true, "slot": slot, "tower_index": tower_idx, "cmd_id": cmd_id}


func cancel_placement() -> void:
	placement_mode = false
	placement_tower_index = -1
	if _build_manager != null:
		_build_manager.placement_mode_active = false
	_destroy_ghost()
	placement_cancelled.emit()


## Handles ground tap when outside placement mode: creates dynamic slot if valid.
## Returns true if a dynamic slot was created/selected, false otherwise.
func handle_ground_tap(point: Vector3) -> bool:
	var snapped_pos := Vector3(roundf(point.x * 2.0) / 2.0, 0.05, roundf(point.z * 2.0) / 2.0)
	var paths: Array = _get_paths()
	var trees: Array = _get_trees()
	var camps: Array = _get_camps()

	var is_valid: bool = _build_manager.is_valid_tower_placement(
		snapped_pos, paths, trees, castle_position, camps, active_dynamic_slot
	)

	if is_valid:
		cleanup_unbuilt_dynamic_slot()
		var slot: TowerSlot = _build_manager.create_dynamic_slot(snapped_pos)
		active_dynamic_slot = slot
		_build_manager.select_slot(slot)
		show_placement_preview(snapped_pos, true)
		return true
	else:
		cleanup_unbuilt_dynamic_slot()
		show_placement_preview(snapped_pos, false)
		return false


## Handles cursor/touch movement when outside placement mode: updates preview ring.
func handle_placement_moved(ground_pos: Vector3) -> void:
	if _build_manager == null:
		return
	var snapped_pos := Vector3(roundf(ground_pos.x * 2.0) / 2.0, 0.05, roundf(ground_pos.z * 2.0) / 2.0)
	var paths: Array = _get_paths()
	var trees: Array = _get_trees()
	var camps: Array = _get_camps()
	var is_valid: bool = _build_manager.is_valid_tower_placement(
		snapped_pos, paths, trees, castle_position, camps, active_dynamic_slot
	)
	show_placement_preview(snapped_pos, is_valid)


func cleanup_unbuilt_dynamic_slot() -> void:
	if active_dynamic_slot != null:
		if is_instance_valid(active_dynamic_slot) and active_dynamic_slot.is_dynamic and active_dynamic_slot.is_free():
			_build_manager.remove_dynamic_slot(active_dynamic_slot)
		active_dynamic_slot = null
	hide_placement_ring()


func show_placement_preview(pos: Vector3, valid: bool) -> void:
	if placement_ring == null:
		placement_ring = _create_placement_ring()
	if placement_ring == null:
		return
	if _invalid_preview_tween != null and _invalid_preview_tween.is_valid():
		_invalid_preview_tween.kill()
		_invalid_preview_tween = null
	placement_ring.global_position = Vector3(pos.x, 0.08, pos.z)
	var mat := placement_ring.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(0.2, 0.9, 0.3, 0.85) if valid else Color(0.95, 0.2, 0.2, 0.85)
	placement_ring.visible = true
	if not valid:
		if _hero != null and _hero.is_inside_tree():
			_invalid_preview_tween = _hero.create_tween()
			if _invalid_preview_tween != null:
				_invalid_preview_tween.tween_interval(0.6)
				_invalid_preview_tween.tween_callback(func() -> void:
					if placement_ring != null and not (active_dynamic_slot != null and _build_manager != null and _build_manager.selected_slot == active_dynamic_slot):
						placement_ring.visible = false
				)


func hide_placement_ring() -> void:
	if placement_ring != null:
		placement_ring.visible = false


func _destroy_ghost() -> void:
	if ghost != null:
		if is_instance_valid(ghost):
			if ghost.get_parent() != null:
				ghost.get_parent().remove_child(ghost)
			ghost.queue_free()
		ghost = null


func _create_placement_ghost(data: TowerData) -> Node3D:
	var new_ghost := Node3D.new()
	new_ghost.name = "TowerPlacementGhost"

	# Tower visual model
	if data.scene != null:
		var model_root: Node = data.scene.instantiate()
		model_root.process_mode = Node.PROCESS_MODE_DISABLED
		for child in model_root.get_children():
			if child is AudioStreamPlayer or child is AudioStreamPlayer3D or child is CollisionShape3D:
				child.queue_free()
		_make_meshes_translucent(model_root, Color(0.7, 0.9, 1.0, 0.6))
		new_ghost.add_child(model_root)

	# Footprint ring (0.65m outer radius, 0.52m inner radius)
	var footprint := MeshInstance3D.new()
	footprint.name = "FootprintRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.52
	torus.outer_radius = 0.65
	torus.rings = 24
	torus.ring_segments = 4
	footprint.mesh = torus
	var fp_mat := StandardMaterial3D.new()
	fp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fp_mat.albedo_color = Color(0.2, 0.9, 0.3, 0.85)
	footprint.material_override = fp_mat
	footprint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	footprint.position.y = 0.06
	new_ghost.add_child(footprint)

	# Range circle
	var range_mesh := MeshInstance3D.new()
	range_mesh.name = "RangeCircle"
	var range_radius: float = data.range_levels[0] if not data.range_levels.is_empty() else 4.0
	var range_torus := TorusMesh.new()
	range_torus.inner_radius = range_radius - 0.05
	range_torus.outer_radius = range_radius + 0.05
	range_torus.rings = 48
	range_torus.ring_segments = 4
	range_mesh.mesh = range_torus
	var r_mat := StandardMaterial3D.new()
	r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	r_mat.albedo_color = Color(0.3, 0.6, 1.0, 0.45)
	range_mesh.material_override = r_mat
	range_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	range_mesh.position.y = 0.04
	new_ghost.add_child(range_mesh)

	var parent: Node = null
	if _hero != null and _hero.get_parent() != null:
		parent = _hero.get_parent()
	elif _build_manager != null and _build_manager.is_inside_tree():
		parent = _build_manager.get_tree().current_scene
	if parent != null:
		parent.add_child(new_ghost)
	return new_ghost


func _make_meshes_translucent(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = tint
		mi.material_override = mat
	for child in node.get_children():
		_make_meshes_translucent(child, tint)


func _update_ghost_appearance(valid: bool) -> void:
	if ghost == null or not is_instance_valid(ghost):
		return
	var fp: MeshInstance3D = ghost.get_node_or_null("FootprintRing") as MeshInstance3D
	if fp != null and fp.material_override is StandardMaterial3D:
		var fp_mat: StandardMaterial3D = fp.material_override as StandardMaterial3D
		fp_mat.albedo_color = Color(0.2, 0.9, 0.3, 0.85) if valid else Color(0.95, 0.2, 0.2, 0.85)
	var range_c: MeshInstance3D = ghost.get_node_or_null("RangeCircle") as MeshInstance3D
	if range_c != null:
		range_c.visible = valid
	var tint := Color(0.4, 1.0, 0.5, 0.6) if valid else Color(1.0, 0.3, 0.3, 0.6)
	_tint_ghost_meshes(ghost, tint)


func _tint_ghost_meshes(node: Node, tint: Color) -> void:
	if node is MeshInstance3D and node.name != "FootprintRing" and node.name != "RangeCircle":
		var mi := node as MeshInstance3D
		if mi.material_override is StandardMaterial3D:
			(mi.material_override as StandardMaterial3D).albedo_color = tint
	for child in node.get_children():
		_tint_ghost_meshes(child, tint)


func _create_placement_ring() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	ring.name = "PlacementPreviewRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.52
	torus.outer_radius = 0.65
	torus.rings = 24
	torus.ring_segments = 4
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 0.9, 0.3, 0.85)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	var parent: Node = null
	if _range_ring != null and _range_ring.get_parent() != null:
		parent = _range_ring.get_parent()
	elif _hero != null and _hero.get_parent() != null:
		parent = _hero.get_parent()
	if parent != null:
		parent.add_child(ring)
	return ring


func _get_paths() -> Array:
	if _sim != null and _sim.wave_manager != null:
		return _sim.wave_manager.get_paths()
	return []


func _get_trees() -> Array:
	return _sim.trees if _sim != null else []


func _get_camps() -> Array:
	if _hero != null and _hero.is_inside_tree():
		return _hero.get_tree().get_nodes_in_group(&"camps")
	return []
