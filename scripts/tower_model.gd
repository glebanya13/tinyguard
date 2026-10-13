extends Node3D
## Visuals of the archer tower model: turns the crossbow towards the current
## target, plays the recoil animation and shot sound, shows level decorations.
## Gameplay stays in tower.gd.

## Radians per second the crossbow turns at.
@export var turn_speed: float = 10.0
@export var shot_sound: AudioStreamPlayer

var _target_yaw: float = 0.0

@onready var _turret: Node3D = find_child("Turret") as Node3D
@onready var _anim: AnimationPlayer = find_child("AnimationPlayer", false) as AnimationPlayer
@onready var _lv2: Node3D = find_child("Lv2") as Node3D
@onready var _lv3: Node3D = find_child("Lv3") as Node3D


func _ready() -> void:
	_target_yaw = _turret.rotation.y
	_on_tower_level_changed(0)


func _process(delta: float) -> void:
	_turret.rotation.y = rotate_toward(_turret.rotation.y, _target_yaw, turn_speed * delta)


func _on_tower_fired(target: Enemy) -> void:
	# The turret faces +Z at rest; yaw it towards the target on the ground plane.
	var local_target: Vector3 = _turret.get_parent_node_3d().to_local(target.global_position)
	var to_target: Vector3 = local_target - _turret.position
	_target_yaw = atan2(to_target.x, to_target.z)
	_anim.stop()
	_anim.play(&"attack")
	if shot_sound:
		shot_sound.pitch_scale = randf_range(0.92, 1.08)
		shot_sound.play()


func _on_tower_level_changed(level: int) -> void:
	_lv2.visible = level >= 1
	_lv3.visible = level >= 2
