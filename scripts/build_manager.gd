class_name BuildManager
extends Node
## Picks tower slots with a camera ray and builds towers for gold.
## Input arrives as a left mouse press: on Android touches are converted
## to mouse events (input_devices/pointing/emulate_mouse_from_touch), so
## HUD buttons consume their taps before they reach _unhandled_input.

signal slot_selected(slot: TowerSlot)
signal selection_cleared
signal tower_built(slot: TowerSlot, tower: Tower)

@export var tower_data: TowerData
@export var game_state: GameState
@export var camera: Camera3D
@export_flags_3d_physics var slot_collision_mask: int = 1
@export var ray_length: float = 100.0

var selected_slot: TowerSlot = null


func _unhandled_input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	if press == null or not press.pressed or press.button_index != MOUSE_BUTTON_LEFT:
		return
	handle_tap(press.position)
	get_viewport().set_input_as_handled()


## Selects a free slot under screen_pos, otherwise clears the selection.
func handle_tap(screen_pos: Vector2) -> void:
	var slot: TowerSlot = _pick_slot(screen_pos)
	if slot != null and slot.is_free():
		select_slot(slot)
	else:
		clear_selection()


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


## Builds on the selected slot. Does nothing and returns false if no free
## slot is selected or there is not enough gold.
func build_selected() -> bool:
	if selected_slot == null or not selected_slot.is_free():
		clear_selection()
		return false
	if not game_state.spend_gold(tower_data.cost):
		return false
	var slot: TowerSlot = selected_slot
	clear_selection()
	var tower: Tower = slot.place_tower(tower_data.scene)
	if tower == null:
		game_state.add_gold(tower_data.cost)
		return false
	tower_built.emit(slot, tower)
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
