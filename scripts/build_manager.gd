class_name BuildManager
extends Node
## Picks tower slots with a camera ray, builds and upgrades towers for gold
## and wood.
## Input arrives as a left mouse click: on Android touches are converted
## to mouse events (input_devices/pointing/emulate_mouse_from_touch), so
## HUD buttons consume their taps before they reach _unhandled_input.
## A tap on open ground is reported as ground_tapped (the hero walks there).

signal slot_selected(slot: TowerSlot)
signal selection_cleared
signal tower_built(slot: TowerSlot, tower: Tower)
signal tower_upgraded(slot: TowerSlot, tower: Tower)
signal ground_tapped(point: Vector3)

## Buildable tower types, in command card order.
@export var tower_types: Array[TowerData] = []
@export var game_state: GameState
@export var camera: CameraFollow
@export_flags_3d_physics var slot_collision_mask: int = 1
@export var ray_length: float = 100.0
## A press that moves further than this before release is a drag, not a tap.
@export var tap_slop: float = 24.0

var selected_slot: TowerSlot = null

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


func can_build(slot: TowerSlot, data: TowerData) -> bool:
	return (
		slot != null and slot.is_free() and data != null
		and game_state.can_afford(Vector2i(data.cost_gold, data.cost_wood))
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
	tower.apply_level(data, 0)
	if slot == selected_slot:
		# Refresh listeners: the selected slot changed from free to occupied.
		slot_selected.emit(slot)
	tower_built.emit(slot, tower)
	return true


func upgrade(slot: TowerSlot) -> bool:
	if not game_state.spend(upgrade_cost(slot)):
		return false
	slot.tower.apply_level(slot.tower.data, slot.tower.level + 1)
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
