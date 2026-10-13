class_name WoodTree
extends StaticBody3D
## A tree the hero can chop for wood. Each hit gives wood_per_hit until the
## tree runs out, then it falls, leaves a stump and grows back later.

const GROUP := &"wood_trees"

@export var wood_per_hit: int = 3
@export var hits: int = 4
@export var regrow_time: float = 40.0

var _hits_left: int = 0

@onready var _tree: Node3D = $Tree
@onready var _stump: Node3D = $Stump


func _ready() -> void:
	add_to_group(GROUP)
	_tree.rotation.y = randf() * TAU
	_hits_left = hits
	_stump.visible = false


func is_choppable() -> bool:
	return _hits_left > 0


## One axe/sword hit from `from`. Returns the wood gained (0 if the tree is down).
func chop(from: Vector3) -> int:
	if _hits_left <= 0:
		return 0
	_hits_left -= 1
	var away: Vector3 = global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	var axis: Vector3 = Vector3.UP.cross(away).normalized()
	var tween := create_tween()
	if _hits_left > 0:
		# Shake.
		tween.tween_property(_tree, "quaternion", Quaternion(axis, 0.12), 0.06)
		tween.tween_property(_tree, "quaternion", Quaternion(axis, -0.05), 0.1)
		tween.tween_property(_tree, "quaternion", Quaternion.IDENTITY, 0.12)
	else:
		_stump.visible = true
		tween.tween_property(_tree, "quaternion", Quaternion(axis, PI * 0.5), 0.7) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(_tree, "scale", Vector3.ONE * 0.01, 0.35)
		tween.tween_callback(_tree.hide)
		get_tree().create_timer(regrow_time, false).timeout.connect(_regrow)
	return wood_per_hit


func _regrow() -> void:
	_hits_left = hits
	_tree.quaternion = Quaternion.IDENTITY
	_tree.scale = Vector3.ONE * 0.05
	_tree.show()
	var tween := create_tween()
	tween.tween_property(_tree, "scale", Vector3.ONE, 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_stump.hide)
