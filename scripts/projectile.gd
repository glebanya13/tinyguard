class_name Projectile
extends Node3D
## Homing projectile: flies towards its target and deals damage on arrival.
## Disappears if the target dies or leaves the tree before the hit.

@export var speed: float = 10.0
@export var hit_distance: float = 0.15

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
		_target.take_damage(_damage)
		queue_free()
		return
	global_position += to_target.normalized() * step
