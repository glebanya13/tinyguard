class_name BuildManager
extends Node
## Picks tower slots with a camera ray, builds and upgrades towers for gold.
## Input arrives as a left mouse press: on Android touches are converted
## to mouse events (input_devices/pointing/emulate_mouse_from_touch), so
## HUD buttons consume their taps before they reach _unhandled_input.
## A tap on open ground is reported as ground_tapped (the hero walks there).

signal slot_selected(slot: TowerSlot)
signal selection_cleared
signal tower_built(slot: TowerSlot, tower: Tower)
signal tower_upgraded(slot: TowerSlot, tower: Tower)
signal ground_tapped(point: Vector3)

@export var tower_data: TowerData
@export var game_state: GameState
@export var camera: Camera3D
@export_flags_3d_physics var slot_collision_mask: int = 1
@export var ray_length: float = 100.0

var selected_slot: TowerSlot = null


func _ready() -> void:
	# Towers placed in the editor take their stats from the same data.
	for node: Node in get_tree().get_nodes_in_group(TowerSlot.GROUP):
		var slot := node as TowerSlot
		if slot.tower != null:
			slot.tower.apply_level(tower_data, 0)


func _unhandled_input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT:
		return
	handle_tap(press.position)
	get_viewport().set_input_as_handled()


## Selects the slot under screen_pos; elsewhere clears the selection and
## reports the ground point.
func handle_tap(screen_pos: Vector2) -> void:
	var slot: TowerSlot = _pick_slot(screen_pos)
	if slot != null:
		select_slot(slot)
		return
	clear_selection()
	var ground: Variant = _pick_ground(screen_pos)
	if ground != null:
		ground_tapped.emit(ground)


func select_slot(slot: TowerSlot) -> void:
	if slot == selected_slot:
		return
	if selected_slot != null:
		selected_slot.set_selected(false)
	selected_slot = slot
	slot.set_selected(true)
	slot_selected.emit(slot)


func clear_selection() -> void:
	if selected_slot == null:
		return
	selected_slot.set_selected(false)
	selected_slot = null
	selection_cleared.emit()


func can_afford() -> bool:
	return game_state.gold >= tower_data.cost


func can_build(slot: TowerSlot) -> bool:
	return slot != null and slot.is_free() and game_state.gold >= tower_data.cost


## Price of the next upgrade of the tower on `slot`, or -1 if none.
func upgrade_cost(slot: TowerSlot) -> int:
	if slot == null or slot.tower == null:
		return -1
	return tower_data.upgrade_cost(slot.tower.level)


func can_upgrade(slot: TowerSlot) -> bool:
	var cost: int = upgrade_cost(slot)
	return cost >= 0 and game_state.gold >= cost


## Builds on the selected slot. Does nothing and returns false if no free
## slot is selected or there is not enough gold.
func build_selected() -> bool:
	return build_on(selected_slot)


func build_on(slot: TowerSlot) -> bool:
	if slot == null or not slot.is_free():
		return false
	if not game_state.spend_gold(tower_data.cost):
		return false
	var tower: Tower = slot.place_tower(tower_data.scene)
	if tower == null:
		game_state.add_gold(tower_data.cost)
		return false
	tower.apply_level(tower_data, 0)
	if slot == selected_slot:
		# Refresh listeners: the selected slot changed from free to occupied.
		slot_selected.emit(slot)
	tower_built.emit(slot, tower)
	return true


func upgrade(slot: TowerSlot) -> bool:
	var cost: int = upgrade_cost(slot)
	if cost < 0 or not game_state.spend_gold(cost):
		return false
	slot.tower.apply_level(tower_data, slot.tower.level + 1)
	tower_upgraded.emit(slot, slot.tower)
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


## Intersection of the tap ray with the ground plane (y = 0), or null.
func _pick_ground(screen_pos: Vector2) -> Variant:
	var plane := Plane(Vector3.UP, 0.0)
	return plane.intersects_ray(
		camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos)
	)
