class_name Projectile
extends Node3D
## Tower shot. Homing (arrow, frost shard) or ballistic (cannonball: flies in an
## arc to where the target was and damages everything within the splash radius).
## The model casts no shadow (set in the projectile scenes, not per shot).
## Flies in fixed simulation steps (sim_step); the node only draws the position
## between the last two steps.

@export var speed: float = 10.0
@export var hit_distance: float = 0.15
## Droplets and sound spawned at the impact point.
@export var hit_fx: PackedScene
## > 0 makes the shot ballistic with this apex height (metres).
@export var arc_height: float = 0.0

## Stable id (set by Sim.add_projectile when launched).
var id: int = 0
var sim: Sim = null

var _target: Enemy = null
var _damage: float = 0.0
var _splash: float = 0.0
var _slow: float = 1.0
var _slow_time: float = 0.0
var _kind: StringName = &""
var _from: Vector3
var _pos: Vector3 = Vector3.ZERO
var _prev_pos: Vector3 = Vector3.ZERO
var _to: Vector3
var _time: float = 0.0
var _duration: float = 0.0


## Call after the projectile is in the tree and positioned at the muzzle.
func launch(
	target: Enemy,
	damage: float,
	splash: float = 0.0,
	slow: float = 1.0,
	slow_time: float = 0.0,
	kind: StringName = &""
) -> void:
	_kind = kind
	_target = target
	_damage = damage
	_splash = splash
	_slow = slow
	_slow_time = slow_time
	_from = global_position
	_to = target.sim_position()
	_duration = maxf(_from.distance_to(_to) / speed, 0.15)
	_pos = _from
	_prev_pos = _from
	sim.add_projectile(self)


func _exit_tree() -> void:
	if sim != null:
		sim.remove_projectile(self)


## Drawing only: between the last two simulation steps.
func _process(_delta: float) -> void:
	global_position = _prev_pos.lerp(_pos, sim.alpha())
	_face(_pos - _prev_pos)


## Integers describing the simulated state (for Sim.state_hash).
func state_ints() -> Array[int]:
	return [
		id,
		roundi(_pos.x * 1000.0),
		roundi(_pos.y * 1000.0),
		roundi(_pos.z * 1000.0),
		_target.id if is_instance_valid(_target) else 0,
	]


## One fixed simulation step.
func sim_step() -> void:
	_prev_pos = _pos
	if arc_height > 0.0:
		_fly_arc()
	else:
		_fly_homing()


func _fly_homing() -> void:
	if not is_instance_valid(_target) or not _target.is_alive():
		_finish()
		return
	var to_target: Vector3 = _target.get_aim_point() - _pos
	var step: float = speed * Sim.TICK_DT
	if to_target.length() <= maxf(step, hit_distance):
		_spawn_fx(_target.get_aim_point())
		_hit(_target)
		_finish()
		return
	_pos += to_target.normalized() * step


func _fly_arc() -> void:
	_time += Sim.TICK_DT
	var k: float = minf(_time / _duration, 1.0)
	_pos = _from.lerp(_to, k) + Vector3.UP * arc_height * 4.0 * k * (1.0 - k)
	if k >= 1.0:
		_spawn_fx(_to)
		for enemy in sim.enemies.duplicate():
			if enemy.is_flying():
				continue  # shells burst on the ground
			var offset: Vector3 = enemy.sim_position() - _to
			offset.y = 0.0
			if offset.length() <= _splash:
				_hit(enemy)
		_finish()


func _finish() -> void:
	sim.remove_projectile(self)
	queue_free()


func _hit(enemy: Enemy) -> void:
	if _slow < 1.0:
		enemy.apply_slow(_slow, _slow_time)
	enemy.take_damage(_damage, _kind)


func _face(direction: Vector3) -> void:
	# The models point along -Z; avoid look_at() when flying straight up/down.
	if direction.length() > 0.0001 and absf(direction.normalized().dot(Vector3.UP)) < 0.99:
		look_at(global_position + direction, Vector3.UP)


func _spawn_fx(point: Vector3) -> void:
	if hit_fx == null:
		return
	var fx := hit_fx.instantiate() as Node3D
	fx.top_level = true
	add_sibling(fx)
	fx.global_position = point
