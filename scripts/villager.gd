class_name Villager
extends Node3D
## Friendly villager: strolls around its home spot on free ground and stops to
## greet the knight while he trades. Enemies ignore villagers and nothing
## collides with them. The model faces +Z at rest.

const GROUP := &"villagers"

## Metres per second (a slow stroll).
@export var speed: float = 0.6
## Radians per second the model turns towards where it goes or looks.
@export var turn_speed: float = 6.0
## Strolls end within this distance of the home spot.
@export var wander_radius: float = 1.8
## Seconds of rest between strolls.
@export var rest_min: float = 1.5
@export var rest_max: float = 4.5
## Attempts to find a free stroll target before resting again.
@export var target_tries: int = 6
## Distance between ground checks along a stroll.
@export var check_step: float = 0.3
## A knight this close (metres) gets a wave and the villager turns to him.
@export var greet_range: float = 4.0
## Seconds before the same villager greets again.
@export var greet_pause: float = 12.0

## Centre of the strolls (on the ground).
var home: Vector3 = Vector3.ZERO
## ground_check.call(point: Vector3) -> bool: may the villager stand there?
var ground_check: Callable = Callable()
## Own random stream for the strolls: decoration only, never the simulation's
## (Villagers seeds it from the battle seed so clients start alike).
var rng := RandomNumberGenerator.new()

var _target: Vector3 = Vector3.ZERO
var _walking: bool = false
var _rest_left: float = 0.0
var _partner: Node3D = null
var _greet_wait: float = 0.0
var _look_at: Node3D = null
var _sense_left: float = 0.0

@onready var _model: Node3D = $Model
@onready var _puppet: Puppet = $Puppet


func _ready() -> void:
	add_to_group(GROUP)
	_model.rotation.y = rng.randf() * TAU
	_rest_left = rng.randf_range(0.0, rest_max)


func _process(delta: float) -> void:
	if _partner != null:
		_turn_to(_partner.global_position, delta)
		return
	_greet_wait = maxf(_greet_wait - delta, 0.0)
	if not _walking:
		_notice_hero(delta)
		_rest_left -= delta
		if _rest_left <= 0.0:
			_start_stroll()
		return
	var offset: Vector3 = _target - global_position
	offset.y = 0.0
	var step: float = speed * delta
	if offset.length() <= step:
		global_position = _target
		_rest()
		return
	global_position += offset.normalized() * step
	_turn_to(_target, delta)


## Stops and turns to `partner` (the knight) while trading; null walks on.
func talk_to(partner: Node3D) -> void:
	if partner == _partner:
		return
	_partner = partner
	if partner != null:
		_walking = false
		greet()
	else:
		_rest()


## Waves a hand (greeting, a sale).
func cheer() -> void:
	_puppet.play_action(&"cheer")


## Greets with a wave.
func greet() -> void:
	_puppet.play_action(&"wave")


func is_walking() -> bool:
	return _walking


## Resting: waves at a knight who comes near, then keeps an eye on him.
func _notice_hero(delta: float) -> void:
	_sense_left -= delta
	if _sense_left <= 0.0:
		_sense_left = 0.3
		_look_at = null
		var best: float = greet_range
		for hero: Node3D in get_tree().get_nodes_in_group(Hero.GROUP):
			var d: float = (
				Vector2(
					hero.global_position.x - global_position.x,
					hero.global_position.z - global_position.z
				)
				. length()
			)
			if d <= best:
				best = d
				_look_at = hero
		if _look_at != null and _greet_wait <= 0.0:
			_greet_wait = greet_pause
			greet()
	if _look_at != null and is_instance_valid(_look_at):
		_turn_to(_look_at.global_position, delta)


func _rest() -> void:
	_walking = false
	_rest_left = rng.randf_range(rest_min, rest_max)


func _start_stroll() -> void:
	for i in target_tries:
		var angle: float = rng.randf() * TAU
		var target: Vector3 = (
			home + Vector3(cos(angle), 0.0, sin(angle)) * wander_radius * sqrt(rng.randf())
		)
		if _way_free(global_position, target):
			_target = target
			_walking = true
			return
	_rest()


func _way_free(from: Vector3, to: Vector3) -> bool:
	if not ground_check.is_valid():
		return false
	var steps: int = maxi(1, ceili(from.distance_to(to) / check_step))
	for k in range(1, steps + 1):
		if not ground_check.call(from.lerp(to, float(k) / steps)):
			return false
	return true


func _turn_to(point: Vector3, delta: float) -> void:
	var offset: Vector3 = point - global_position
	if absf(offset.x) + absf(offset.z) < 0.01:
		return
	var yaw: float = atan2(offset.x, offset.z)
	_model.rotation.y = rotate_toward(_model.rotation.y, yaw, turn_speed * delta)
