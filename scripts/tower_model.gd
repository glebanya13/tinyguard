extends Node3D
## Visuals of the archer tower model: turns the crossbow towards the current
## target and plays the recoil animation. Gameplay stays in tower.gd.

## Radians per second the crossbow turns at.
@export var turn_speed: float = 10.0

var _target_yaw: float = 0.0

@onready var _turret: Node3D = find_child("Turret") as Node3D
@onready var _anim: AnimationPlayer = find_child("AnimationPlayer", false) as AnimationPlayer


func _ready() -> void:
	_target_yaw = _turret.rotation.y


func _process(delta: float) -> void:
	_turret.rotation.y = rotate_toward(_turret.rotation.y, _target_yaw, turn_speed * delta)


func _on_tower_fired(target: Enemy) -> void:
	# The turret faces +Z at rest; yaw it towards the target on the ground plane.
	var local_target: Vector3 = _turret.get_parent_node_3d().to_local(target.global_position)
	var to_target: Vector3 = local_target - _turret.position
	_target_yaw = atan2(to_target.x, to_target.z)
	_anim.stop()
	_anim.play(&"attack")
