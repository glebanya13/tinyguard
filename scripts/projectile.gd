class_name Projectile
extends Node3D
## Homing projectile: flies towards its target and deals damage on arrival.
## Disappears if the target dies or leaves the tree before the hit.

@export var speed: float = 10.0
@export var hit_distance: float = 0.15
## Droplets and sound spawned at the impact point.
@export var hit_fx: PackedScene

var _target: Enemy = null
var _damage: float = 0.0


func launch(target: Enemy, damage: float) -> void:
	_target = target
	_damage = damage


func _process(delta: float) -> void:
	if not is_instance_valid(_target) or not _target.is_alive():
		queue_free()
		return
	var to_target: Vector3 = _target.get_aim_point() - global_position
	var step: float = speed * delta
	if to_target.length() <= maxf(step, hit_distance):
		_spawn_hit_fx(_target.get_aim_point())
		_target.take_damage(_damage)
		queue_free()
		return
	var direction: Vector3 = to_target.normalized()
	global_position += direction * step
	# The arrow model points along -Z; avoid look_at() when flying straight up/down.
	if absf(direction.dot(Vector3.UP)) < 0.99:
		look_at(global_position + direction, Vector3.UP)


func _spawn_hit_fx(point: Vector3) -> void:
	if hit_fx == null:
		return
	var fx := hit_fx.instantiate() as Node3D
	fx.top_level = true
	add_sibling(fx)
	fx.global_position = point
