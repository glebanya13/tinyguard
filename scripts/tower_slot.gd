class_name TowerSlot
extends Area3D
## Build pad. Picked by a camera ray (collision layer 1) and holds at most
## one tower as its child. A Tower already placed under it in the editor
## makes it occupied from the start.

enum State { FREE, SELECTED, OCCUPIED }

@export var free_material: Material
@export var selected_material: Material
@export var occupied_material: Material
## Height of the pad top, where a built tower stands.
@export var tower_offset: float = 0.05

var state: State = State.FREE
var tower: Tower = null

@onready var _pad: MeshInstance3D = $Pad
@onready var _selection_ring: MeshInstance3D = $SelectionRing


func _ready() -> void:
	for child: Node in get_children():
		if child is Tower:
			tower = child as Tower
	_set_state(State.FREE if tower == null else State.OCCUPIED)


func is_free() -> bool:
	return tower == null


func set_selected(selected: bool) -> void:
	if not is_free():
		return
	_set_state(State.SELECTED if selected else State.FREE)


## Returns the new tower, or null if the slot is taken or the scene is invalid.
func place_tower(scene: PackedScene) -> Tower:
	if not is_free() or scene == null:
		return null
	var new_tower := scene.instantiate() as Tower
	if new_tower == null:
		push_error("TowerSlot: scene root must use tower.gd")
		return null
	new_tower.position = Vector3.UP * tower_offset
	add_child(new_tower)
	tower = new_tower
	_set_state(State.OCCUPIED)
	return new_tower


func _set_state(new_state: State) -> void:
	state = new_state
	match state:
		State.FREE:
			_pad.material_override = free_material
		State.SELECTED:
			_pad.material_override = selected_material
		State.OCCUPIED:
			_pad.material_override = occupied_material
	_selection_ring.visible = state == State.SELECTED
