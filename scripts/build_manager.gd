class_name BuildManager
extends Node
## Picks tower slots with a camera ray, builds and upgrades towers for gold
## and wood.
## Input arrives as a left mouse click: on Android touches are converted
## to mouse events (input_devices/pointing/emulate_mouse_from_touch), so
## HUD buttons consume their taps before they reach _unhandled_input.
## A tap on open ground is reported as ground_tapped (the hero walks there).

signal slot_selected(slot: TowerSlot)
signal camp_selected(camp: Node3D)
signal selection_cleared
signal tower_built(slot: TowerSlot, tower: Tower)
signal tower_upgraded(slot: TowerSlot, tower: Tower)
signal tower_sold(slot: TowerSlot, refund: Vector2i)
signal ground_tapped(point: Vector3)

## Buildable tower types, in command card order.
@export var tower_types: Array[TowerData] = []
@export var game_state: GameState
@export var camera: CameraFollow
@export_flags_3d_physics var slot_collision_mask: int = 1
@export var ray_length: float = 100.0
## A press that moves further than this before release is a drag, not a tap.
@export var tap_slop: float = 24.0

## Towers built here join this simulation (set by the level).
var sim: Sim = null
## Daily challenge: resource names of the towers that may be built (empty = all).
var allowed_towers: Array[String] = []
var selected_slot: TowerSlot = null
var selected_camp: Node3D = null
var lumberjack_camp: CampStructures.LumberjackCamp = null
var mercenary_camp: CampStructures.MercenaryCamp = null
var villagers: Villagers = null
var commands: GameCommands = null
var bounds: Rect2 = Rect2()
## Permanent tower damage bonus (perk), applied after every level change.
var damage_multiplier: float = 1.0

const SLOT_SCENE: PackedScene = preload("res://scenes/tower_slot.tscn")

var _press_position: Vector2 = Vector2.ZERO
var _pressed: bool = false


func _unhandled_input(event: InputEvent) -> void:
	# Act on release, so a pinch (second finger) or a drag does not count as a tap.
	var press := event as InputEventMouseButton
	if press == null or press.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	if press.pressed:
		_pressed = true
		_press_position = press.position
		return
	if not _pressed:
		return
	_pressed = false
	if press.position.distance_to(_press_position) > tap_slop or camera.is_pinch_gesture():
		return
	handle_tap(press.position)


## Selects the slot under screen_pos; elsewhere clears the selection and
## reports the ground point.
func handle_tap(screen_pos: Vector2) -> void:
	var ground: Variant = _pick_ground(screen_pos)
	if ground != null and villagers != null:
		var villager: Villager = villagers.nearest(ground, 1.0)
		if villager != null:
			clear_selection()
			ground_tapped.emit(ground)
			return

	# Camp tap detection (Area3D collider or proximity on ground)
	var camp: Node3D = _pick_camp(screen_pos)
	if camp == null and ground != null:
		camp = _camp_near_ground(ground)
	if camp != null:
		select_camp(camp)
		return

	var slot: TowerSlot = _pick_slot(screen_pos)
	if slot == null and ground != null:
		var best_dist: float = 1.35
		for s in get_tree().get_nodes_in_group(TowerSlot.GROUP):
			if s is TowerSlot:
				var ts: TowerSlot = s as TowerSlot
				var d: float = Vector2(ground.x - ts.global_position.x, ground.z - ts.global_position.z).length()
				if d < best_dist:
					best_dist = d
					slot = ts
	if slot != null:
		select_slot(slot)
		return
	clear_selection()
	if ground != null:
		ground_tapped.emit(ground)


func select_camp(camp: Node3D) -> void:
	if selected_slot != null:
		selected_slot.set_selected(false)
		selected_slot = null
	if selected_camp != null and selected_camp != camp:
		if selected_camp.has_method("set_selected"):
			selected_camp.set_selected(false)
	selected_camp = camp
	if selected_camp != null and selected_camp.has_method("set_selected"):
		selected_camp.set_selected(true)
	camp_selected.emit(camp)


func select_slot(slot: TowerSlot) -> void:
	if selected_camp != null:
		if selected_camp.has_method("set_selected"):
			selected_camp.set_selected(false)
		selected_camp = null
	if slot == selected_slot:
		return
	if selected_slot != null:
		selected_slot.set_selected(false)
	selected_slot = slot
	slot.set_selected(true)
	slot_selected.emit(slot)


func clear_selection() -> void:
	var had_selection: bool = false
	if selected_camp != null:
		had_selection = true
		if selected_camp.has_method("set_selected"):
			selected_camp.set_selected(false)
		selected_camp = null
	if selected_slot != null:
		had_selection = true
		selected_slot.set_selected(false)
		selected_slot = null
	if had_selection:
		selection_cleared.emit()


func can_build(slot: TowerSlot, data: TowerData) -> bool:
	return (
		slot != null
		and slot.is_free()
		and data != null
		and is_allowed(data)
		and game_state.can_afford(Vector2i(data.cost_gold, data.cost_wood))
	)


## False for a tower the day's modifiers forbid.
func is_allowed(data: TowerData) -> bool:
	return (
		allowed_towers.is_empty()
		or allowed_towers.has(data.resource_path.get_file().get_basename())
	)


## Price of the next upgrade of the tower on `slot` as (gold, wood), or (-1, -1).
func upgrade_cost(slot: TowerSlot) -> Vector2i:
	if slot == null or slot.tower == null or slot.tower.data == null:
		return Vector2i(-1, -1)
	return slot.tower.data.upgrade_cost(slot.tower.level)


func can_upgrade(slot: TowerSlot) -> bool:
	return game_state.can_afford(upgrade_cost(slot))


## Builds a `data` tower on `slot`. Does nothing and returns false if the
## slot is taken or gold/wood is short.
func build_on(slot: TowerSlot, data: TowerData) -> bool:
	if not can_build(slot, data):
		return false
	var cost := Vector2i(data.cost_gold, data.cost_wood)
	game_state.spend(cost)
	var tower: Tower = slot.place_tower(data.scene)
	if tower == null:
		game_state.add_gold(cost.x)
		game_state.add_wood(cost.y)
		return false
	if sim != null:
		tower.attach(sim)
	tower.apply_level(data, 0)
	tower.damage *= damage_multiplier
	if slot == selected_slot:
		# Refresh listeners: the selected slot changed from free to occupied.
		slot_selected.emit(slot)
	tower_built.emit(slot, tower)
	return true


func upgrade(slot: TowerSlot) -> bool:
	if not game_state.spend(upgrade_cost(slot)):
		return false
	slot.tower.apply_level(slot.tower.data, slot.tower.level + 1)
	slot.tower.damage *= damage_multiplier
	tower_upgraded.emit(slot, slot.tower)
	return true


## Removes the tower on `slot` and refunds part of its price.
func sell(slot: TowerSlot) -> bool:
	if slot == null or slot.tower == null:
		return false
	var refund: Vector2i = slot.tower.data.sell_value(slot.tower.level)
	slot.remove_tower()
	game_state.add_gold(refund.x)
	game_state.add_wood(refund.y)
	if slot == selected_slot:
		slot_selected.emit(slot)
	tower_sold.emit(slot, refund)
	return true


func _pick_slot(screen_pos: Vector2) -> TowerSlot:
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + camera.project_ray_normal(screen_pos) * ray_length
	var query := PhysicsRayQueryParameters3D.create(from, to, slot_collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit["collider"] as TowerSlot


func _pick_camp(screen_pos: Vector2) -> Node3D:
	if camera == null:
		return null
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + camera.project_ray_normal(screen_pos) * ray_length
	var query := PhysicsRayQueryParameters3D.create(from, to, slot_collision_mask)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var col: Object = hit.get("collider")
		var target: Node = col as Node
		while target != null:
			if target is CampStructures.LumberjackCamp or target is CampStructures.MercenaryCamp:
				return target as Node3D
			target = target.get_parent()
	return null


func _camp_near_ground(ground_pt: Vector3) -> Node3D:
	var lj := lumberjack_camp
	if lj == null and is_inside_tree():
		lj = get_tree().current_scene.find_child("LumberjackCamp", true, false) as CampStructures.LumberjackCamp
	if lj != null:
		var d_lj: float = Vector2(ground_pt.x - lj.global_position.x, ground_pt.z - lj.global_position.z).length()
		if d_lj <= 2.2:
			return lj

	var mc := mercenary_camp
	if mc == null and is_inside_tree():
		mc = get_tree().current_scene.find_child("MercenaryCamp", true, false) as CampStructures.MercenaryCamp
	if mc != null:
		var d_mc: float = Vector2(ground_pt.x - mc.global_position.x, ground_pt.z - mc.global_position.z).length()
		if d_mc <= 2.5:
			return mc

	return null


## Intersection of the tap ray with the ground plane (y = 0), or null.
func _pick_ground(screen_pos: Vector2) -> Variant:
	var plane := Plane(Vector3.UP, 0.0)
	return plane.intersects_ray(
		camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos)
	)


## Warcraft-style tower placement validation.
## Checks clearance from enemy paths, castle, trees, camps, existing slots/towers, and level bounds.
func is_valid_tower_placement(
	pos: Vector3,
	paths: Array = [],
	trees: Array = [],
	castle_pos: Vector3 = Vector3.INF,
	camps: Array = [],
	ignore_slot: TowerSlot = null,
	check_slots: bool = true
) -> bool:
	var pos_2d := Vector2(pos.x, pos.z)

	# 1. Level bounds check
	var effective_bounds := bounds
	if effective_bounds.size == Vector2.ZERO and camera != null and camera.bounds.size != Vector2.ZERO:
		effective_bounds = camera.bounds.grow(LevelBuilder.CAMERA_MARGIN)
	if effective_bounds.size != Vector2.ZERO:
		if not effective_bounds.has_point(pos_2d):
			return false

	# 2. Distance to all enemy Path3D curves (curve sample distance >= 1.35m to keep paths clear)
	for p in paths:
		if p is Path3D and p.curve != null:
			if p.curve.point_count < 2:
				continue
			var closest: Vector3
			if p.is_inside_tree():
				var local_pt: Vector3 = p.to_local(pos)
				closest = p.to_global(p.curve.get_closest_point(local_pt))
			else:
				closest = p.curve.get_closest_point(pos)
			if Vector2(closest.x - pos.x, closest.z - pos.z).length() < 1.35:
				return false
		elif p is Curve3D:
			if p.point_count < 2:
				continue
			var closest: Vector3 = p.get_closest_point(pos)
			if Vector2(closest.x - pos.x, closest.z - pos.z).length() < 1.35:
				return false
		elif p is PackedVector2Array:
			for i in range(p.size() - 1):
				var closest_pt: Vector2 = Geometry2D.get_closest_point_to_segment(pos_2d, p[i], p[i + 1])
				if closest_pt.distance_to(pos_2d) < 1.35:
					return false
		elif p is PackedVector3Array:
			for i in range(p.size() - 1):
				var seg_start := Vector2(p[i].x, p[i].z)
				var seg_end := Vector2(p[i + 1].x, p[i + 1].z)
				var closest_pt: Vector2 = Geometry2D.get_closest_point_to_segment(pos_2d, seg_start, seg_end)
				if closest_pt.distance_to(pos_2d) < 1.35:
					return false

	# 3. Distance to castle (>= 3.0m)
	if castle_pos.is_finite():
		if Vector2(castle_pos.x - pos.x, castle_pos.z - pos.z).length() < 3.0:
			return false

	# 4. Distance to all trees (>= 1.5m)
	for tree in trees:
		var t_pos: Vector3
		if tree is Node3D:
			t_pos = tree.global_position if tree.is_inside_tree() else tree.position
		elif tree is Vector3:
			t_pos = tree
		elif tree is Vector2:
			t_pos = Vector3(tree.x, 0.0, tree.y)
		else:
			continue
		if Vector2(t_pos.x - pos.x, t_pos.z - pos.z).length() < 1.5:
			return false

	# 5. Distance to camps (>= 3.0m)
	for camp in camps:
		var cp: Vector3
		if camp is Node3D:
			cp = camp.global_position if camp.is_inside_tree() else camp.position
		elif camp is Vector3:
			cp = camp
		elif camp is Vector2:
			cp = Vector3(camp.x, 0.0, camp.y)
		else:
			continue
		if Vector2(cp.x - pos.x, cp.z - pos.z).length() < 3.0:
			return false

	# 6. Distance to existing towers/slots (>= 2.0m)
	if check_slots:
		var checked_slots: Array = []
		if commands != null:
			for slot in commands.slots:
				if slot != null and is_instance_valid(slot) and slot != ignore_slot:
					checked_slots.append(slot)
					if Vector2(slot.global_position.x - pos.x, slot.global_position.z - pos.z).length() < 2.0:
						return false
		if is_inside_tree():
			for slot_node in get_tree().get_nodes_in_group(TowerSlot.GROUP):
				if slot_node is TowerSlot and is_instance_valid(slot_node) and slot_node != ignore_slot:
					if checked_slots.has(slot_node):
						continue
					if Vector2(slot_node.global_position.x - pos.x, slot_node.global_position.z - pos.z).length() < 2.0:
						return false
		if sim != null:
			for tower in sim.towers:
				if tower != null and is_instance_valid(tower):
					if Vector2(tower.global_position.x - pos.x, tower.global_position.z - pos.z).length() < 2.0:
						return false

	return true


## Creates a dynamic TowerSlot snapped to a 0.5m grid and registers it with commands.slots.
func create_dynamic_slot(pos: Vector3) -> TowerSlot:
	var snapped_x := roundf(pos.x * 2.0) / 2.0
	var snapped_z := roundf(pos.z * 2.0) / 2.0
	var snapped_pos := Vector3(snapped_x, 0.05, snapped_z)

	var slot: TowerSlot = SLOT_SCENE.instantiate() as TowerSlot
	slot.is_dynamic = true
	slot.position = snapped_pos

	if commands != null:
		slot.slot_id = commands.slots.size()
		commands.slots.append(slot)

	var parent: Node = null
	if commands != null:
		for s in commands.slots:
			if s != null and s != slot and is_instance_valid(s) and s.get_parent() != null:
				parent = s.get_parent()
				break
	if parent == null and is_inside_tree():
		var lvl: Node = get_tree().current_scene.find_child("Level", true, false)
		if lvl != null:
			parent = lvl
		else:
			parent = get_tree().current_scene
	if parent != null:
		parent.add_child(slot)

	return slot


## Cleans up an unbuilt dynamic slot and removes it from commands.slots and scene tree.
func remove_dynamic_slot(slot: TowerSlot) -> void:
	if slot == null or not is_instance_valid(slot) or not slot.is_dynamic:
		return
	if slot == selected_slot:
		clear_selection()
	if commands != null:
		var idx: int = commands.slots.find(slot)
		if idx != -1:
			if idx == commands.slots.size() - 1:
				commands.slots.pop_back()
			else:
				commands.slots.remove_at(idx)
				for i in range(idx, commands.slots.size()):
					if commands.slots[i] != null:
						commands.slots[i].slot_id = i
	if slot.get_parent() != null:
		slot.get_parent().remove_child(slot)
	slot.queue_free()
