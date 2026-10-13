class_name WoodTree
extends StaticBody3D
## A tree the hero can chop for wood. Each hit gives wood_per_hit and throws
## leaves and chips; when the tree runs out it falls, leaves a stump and grows
## back later. `variant` picks the model before the node enters the tree.

const GROUP := &"wood_trees"
const MODELS := {
	&"round": preload("res://assets/models/tree_round.glb"),
	&"pine": preload("res://assets/models/tree_pine.glb"),
}
const CHOP_FX: PackedScene = preload("res://scenes/fx/chop_fx.tscn")

@export var variant: StringName = &"round"
## Scale of the model only (physics bodies must stay unscaled).
@export var model_scale: float = 1.0
@export var wood_per_hit: int = 3
@export var hits: int = 4
@export var regrow_time: float = 60.0

var _hits_left: int = 0
var _tree: Node3D = null
var _yaw := Quaternion.IDENTITY

@onready var _stump: Node3D = $Stump


func _ready() -> void:
	add_to_group(GROUP)
	_tree = (MODELS.get(variant, MODELS[&"round"]) as PackedScene).instantiate()
	_yaw = Quaternion(Vector3.UP, randf() * TAU)
	_tree.quaternion = _yaw
	_tree.scale = Vector3.ONE * model_scale
	add_child(_tree)
	_hits_left = hits
	_stump.visible = false


func is_choppable() -> bool:
	return _hits_left > 0


## Hits left before the tree falls (0..hits).
func hits_left() -> int:
	return _hits_left


## One axe/sword hit from `from`. Returns the wood gained (0 if the tree is down).
func chop(from: Vector3) -> int:
	if _hits_left <= 0:
		return 0
	_hits_left -= 1
	var fx := CHOP_FX.instantiate() as Node3D
	add_child(fx)
	var away: Vector3 = global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	var axis: Vector3 = Vector3.UP.cross(away).normalized()
	var tween := create_tween()
	if _hits_left > 0:
		# Shake.
		tween.tween_property(_tree, "quaternion", Quaternion(axis, 0.12) * _yaw, 0.06)
		tween.tween_property(_tree, "quaternion", Quaternion(axis, -0.05) * _yaw, 0.1)
		tween.tween_property(_tree, "quaternion", _yaw, 0.12)
	else:
		_stump.visible = true
		tween.tween_property(_tree, "quaternion", Quaternion(axis, PI * 0.5) * _yaw, 0.7) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(_tree, "scale", Vector3.ONE * 0.01 * model_scale, 0.35)
		tween.tween_callback(_tree.hide)
		get_tree().create_timer(regrow_time, false).timeout.connect(_regrow)
	return wood_per_hit


func _regrow() -> void:
	_hits_left = hits
	_yaw = Quaternion(Vector3.UP, randf() * TAU)
	_tree.quaternion = _yaw
	_tree.scale = Vector3.ONE * 0.05 * model_scale
	_tree.show()
	var tween := create_tween()
	tween.tween_property(_tree, "scale", Vector3.ONE * model_scale, 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_stump.hide)
