extends Node3D
## Visuals of a tower model: turns the turret towards the current target,
## plays the recoil animation and shot sound, shows level decorations.
## The model has one body mesh per upgrade level (Base, Base2 = Base + level 2
## decorations, Base3 = with level 3 decorations): only one of them is drawn, by
## swapping the mesh of "Base". Only the body casts a shadow: every shadow caster is
## one more draw call per tower, the turret and its parts add nothing visible to it.
## Gameplay stays in tower.gd.

## Radians per second the crossbow turns at.
@export var turn_speed: float = 10.0
@export var shot_sound: AudioStreamPlayer

var _target_yaw: float = 0.0
var _body_meshes: Array[Mesh] = []

@onready var _turret: Node3D = find_child("Turret") as Node3D
@onready var _anim: AnimationPlayer = find_child("AnimationPlayer", false) as AnimationPlayer
@onready var _body: MeshInstance3D = find_child("Base") as MeshInstance3D


func _ready() -> void:
	_target_yaw = _turret.rotation.y
	for node_name: String in ["Base", "Base2", "Base3"]:
		var body := find_child(node_name) as MeshInstance3D
		_body_meshes.append(body.mesh)
		if body != _body:
			body.queue_free()
	_drop_shadow(_turret)
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
	_body.mesh = _body_meshes[clampi(level, 0, _body_meshes.size() - 1)]


func _drop_shadow(part: Node) -> void:
	if part is GeometryInstance3D:
		(part as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mesh: Node in part.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
