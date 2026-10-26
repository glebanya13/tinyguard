class_name WoodTree
extends StaticBody3D
## A tree the hero can chop for wood. Each hit gives wood_per_hit and throws
## leaves and chips; when the tree runs out it falls, leaves a stump and grows
## back later. `variant` picks the model before the node enters the tree.
## With a `grove` the standing tree is drawn by the grove's MultiMesh and the
## node's own model is made the first time it animates (not before: two nodes less per
## tree, and a level has 250 of them) and shown only while it does.
## What chopping does (hits left, regrowing after regrow_time) is simulation state
## counted in Sim steps; the tweens only show it.

signal felled(tree: WoodTree)
signal regrown(tree: WoodTree)

const GROUP := &"wood_trees"
## Model per variant: res://assets/models/tree_<variant>.glb, e.g. "pine" or
## "pine_winter" (biome colours). Loaded once per variant.
const MODEL_PATH := "res://assets/models/tree_%s.glb"
const FALLBACK := &"round"
const CHOP_FX: PackedScene = preload("res://scenes/fx/chop_fx.tscn")
const HIGHLIGHT: Material = preload("res://assets/materials/highlight.tres")

@export var variant: StringName = &"round"
## Scale of the model only (physics bodies must stay unscaled).
@export var model_scale: float = 1.0
@export var wood_per_hit: int = 3
@export var hits: int = 4
@export var regrow_time: float = 60.0
@export var is_thicket: bool = false
@export var outpost_id: int = -1

## Set if this tree belongs to an outpost's thicket shield.
var outpost: Outpost = null
## Set before adding the tree; null = always draw the own model.
var grove: Grove = null
## Stable id (set by Sim.add_tree: the order the level plants the trees in).
var id: int = 0
## Set before adding the tree.
var sim: Sim = null

var _hits_left: int = 0
var _tree: Node3D = null
var _yaw := Quaternion.IDENTITY
var _tween: Tween = null
var _highlighted: bool = false
## Step at which the felled tree grows back, or -1.
var _regrow_at: int = -1

@onready var _stump: Node3D = $Stump


func _ready() -> void:
	if not is_thicket:
		add_to_group(GROUP)
	else:
		add_to_group(&"thicket_trees")
	if sim != null:
		sim.add_tree(self)
	_yaw = Quaternion(Vector3.UP, randf() * TAU)
	if grove == null:
		_model()
	_hits_left = hits
	if _stump != null:
		_stump.visible = false


static func model_scene(kind: StringName) -> PackedScene:
	var path: String = MODEL_PATH % kind
	if not ResourceLoader.exists(path):
		path = MODEL_PATH % FALLBACK
	return load(path)  # ResourceLoader caches: every tree of a kind shares one scene


## Glow on the tree the hero is about to chop.
func set_highlighted(on: bool) -> void:
	if on == _highlighted:
		return
	_highlighted = on
	var model: Node3D = _model()
	for node: Node in model.find_children("*", "GeometryInstance3D", true, false) + [model]:
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).material_overlay = HIGHLIGHT if on else null
	if _tween == null or not _tween.is_running():
		_set_animated(on)


## World transform of the standing model (for the grove's MultiMesh).
func model_transform() -> Transform3D:
	return (
		global_transform * Transform3D(Basis(_yaw).scaled(Vector3.ONE * model_scale), Vector3.ZERO)
	)


func is_choppable() -> bool:
	return _hits_left > 0


## Hits left before the tree falls (0..hits).
func hits_left() -> int:
	return _hits_left


## Step at which the tree will regrow, or -1 if standing.
func regrow_at() -> int:
	return _regrow_at


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
	_model()
	_set_animated(true)
	if _tween:
		_tween.kill()
	var tween := create_tween()
	_tween = tween
	if _hits_left > 0:
		# Shake.
		tween.tween_property(_tree, "quaternion", Quaternion(axis, 0.12) * _yaw, 0.06)
		tween.tween_property(_tree, "quaternion", Quaternion(axis, -0.05) * _yaw, 0.1)
		tween.tween_property(_tree, "quaternion", _yaw, 0.12)
		tween.tween_callback(_set_animated.bind(false))
	else:
		if has_node("Shape"):
			$Shape.set_deferred("disabled", true)
		if _stump != null:
			_stump.visible = true
		(
			tween
			. tween_property(_tree, "quaternion", Quaternion(axis, PI * 0.5) * _yaw, 0.7)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN)
		)
		tween.tween_property(_tree, "scale", Vector3.ONE * 0.01 * model_scale, 0.35)
		tween.tween_callback(_tree.hide)
		_regrow_at = sim.tick + Sim.ticks(regrow_time)
		sim.schedule_in(Sim.ticks(regrow_time), _regrow)
		felled.emit(self)
		if outpost != null:
			outpost.on_tree_felled(self)
	# Everything that can be chopped gives wood (thicket trees too, at their own rate).
	return wood_per_hit


## A battle checkpoint puts the tree back as it was: `hits_left` hits left, or (0) felled and
## growing back in `regrow_in` steps. No animation: the level is just being loaded.
func restore_state(hits_left: int, regrow_in: int) -> void:
	if hits_left > 0:
		_hits_left = mini(hits_left, hits)
		return
	_hits_left = 0
	if has_node("Shape"):
		$Shape.set_deferred("disabled", true)
	if _stump != null:
		_stump.visible = true
	if _tree != null:
		_tree.hide()
	if grove != null:
		grove.set_tree_visible(self, false)
	var delay: int = maxi(regrow_in, 1)
	_regrow_at = sim.tick + delay
	sim.schedule_in(delay, _regrow)
	felled.emit(self)
	if outpost != null:
		outpost.on_tree_felled(self)


## Integers describing the simulated state (for Sim.state_hash).
func state_ints() -> Array[int]:
	return [id, _hits_left, _regrow_at]


func _regrow() -> void:
	if has_node("Shape"):
		$Shape.set_deferred("disabled", false)
	_hits_left = hits
	_regrow_at = -1
	_yaw = Quaternion(Vector3.UP, randf() * TAU)
	_model()
	_tree.quaternion = _yaw
	_tree.scale = Vector3.ONE * 0.05 * model_scale
	_tree.show()
	if _tween:
		_tween.kill()
	_tween = create_tween()
	(
		_tween
		. tween_property(_tree, "scale", Vector3.ONE * model_scale, 1.2)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	if _stump != null:
		_tween.tween_callback(_stump.hide)
	_tween.tween_callback(_set_animated.bind(false))
	regrown.emit(self)
	if outpost != null:
		outpost.on_tree_regrown(self)


## Own model while animating, grove instance while standing still.
func _set_animated(animated: bool) -> void:
	if grove == null:
		return
	animated = animated or (_highlighted and _hits_left > 0)
	if animated:
		_model()
	if _tree != null:
		_tree.visible = animated
	grove.set_tree_visible(self, not animated)


## The node's own model (made on first use; hidden at first when the grove draws the tree).
func _model() -> Node3D:
	if _tree == null:
		_tree = model_scene(variant).instantiate()
		_tree.quaternion = _yaw
		_tree.scale = Vector3.ONE * model_scale
		_tree.visible = grove == null
		add_child(_tree)
	return _tree
