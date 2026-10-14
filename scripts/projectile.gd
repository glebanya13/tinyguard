class_name Projectile
extends Node3D
## Tower shot. Homing (arrow, frost shard) or ballistic (cannonball: flies in an
## arc to where the target was and damages everything within the splash radius).

@export var speed: float = 10.0
@export var hit_distance: float = 0.15
## Droplets and sound spawned at the impact point.
@export var hit_fx: PackedScene
## > 0 makes the shot ballistic with this apex height (metres).
@export var arc_height: float = 0.0

var _target: Enemy = null
var _damage: float = 0.0
var _splash: float = 0.0
var _slow: float = 1.0
var _slow_time: float = 0.0
var _kind: StringName = &""
var _from: Vector3
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
	_to = target.global_position
	_duration = maxf(_from.distance_to(_to) / speed, 0.15)


func _process(delta: float) -> void:
	if arc_height > 0.0:
		_fly_arc(delta)
	else:
		_fly_homing(delta)


func _fly_homing(delta: float) -> void:
	if not is_instance_valid(_target) or not _target.is_alive():
		queue_free()
		return
	var to_target: Vector3 = _target.get_aim_point() - global_position
	var step: float = speed * delta
	if to_target.length() <= maxf(step, hit_distance):
		_spawn_fx(_target.get_aim_point())
		_hit(_target)
		queue_free()
		return
	var direction: Vector3 = to_target.normalized()
	global_position += direction * step
	_face(direction)


func _fly_arc(delta: float) -> void:
	_time += delta
	var k: float = minf(_time / _duration, 1.0)
	var previous: Vector3 = global_position
	global_position = _from.lerp(_to, k) + Vector3.UP * arc_height * 4.0 * k * (1.0 - k)
	_face(global_position - previous)
	if k >= 1.0:
		_spawn_fx(_to)
		for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
			var enemy := node as Enemy
			if enemy.is_flying():
				continue  # shells burst on the ground
			var offset: Vector3 = enemy.global_position - _to
			offset.y = 0.0
			if offset.length() <= _splash:
				_hit(enemy)
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
