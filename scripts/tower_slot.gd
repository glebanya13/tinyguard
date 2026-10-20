class_name TowerSlot
extends Area3D
## Build pad. Picked by a camera ray (collision layer 1) and holds at most
## one tower as its child. A Tower already placed under it in the editor
## makes it occupied from the start. Free and occupied slots can be selected
## (to build or to upgrade).

enum State { FREE, SELECTED, OCCUPIED }

const GROUP := &"tower_slots"

@export var free_material: Material
@export var selected_material: Material
@export var occupied_material: Material
## Height of the pad top, where a built tower stands.
@export var tower_offset: float = 0.05

## Index in the level's "slots" (the id commands refer to).
var slot_id: int = 0
var state: State = State.FREE
var tower: Tower = null
var is_selected: bool = false
var is_dynamic: bool = false

@onready var _pad: MeshInstance3D = $Pad
@onready var _selection_ring: MeshInstance3D = $SelectionRing


func _ready() -> void:
	add_to_group(GROUP)
	for child: Node in get_children():
		if child is Tower:
			tower = child as Tower
	_update_visuals()


func is_free() -> bool:
	return tower == null


func set_selected(selected: bool) -> void:
	is_selected = selected
	_update_visuals()


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
	_update_visuals()
	return new_tower


## Frees the tower (if any) and makes the slot free again.
func remove_tower() -> void:
	if tower == null:
		return
	# Leave the simulation now: queue_free() lands at the end of the frame, and extra
	# steps of that frame must not let a sold tower shoot (replays differ in steps per frame).
	if tower.sim != null:
		tower.sim.remove_tower(tower)
	tower.queue_free()
	tower = null
	_update_visuals()


func _update_visuals() -> void:
	if tower != null:
		state = State.OCCUPIED
	else:
		state = State.SELECTED if is_selected else State.FREE
	match state:
		State.FREE:
			_pad.material_override = free_material
		State.SELECTED:
			_pad.material_override = selected_material
		State.OCCUPIED:
			_pad.material_override = occupied_material
	# The tower stands on the pad: no need to draw it.
	_pad.visible = state != State.OCCUPIED
	_selection_ring.visible = is_selected
