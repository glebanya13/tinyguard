class_name Mercenary
extends CharacterBody3D
## Allied mercenary fighter: patrols castle gate or follows the hero,
## attacks nearby chupacabras/enemies with melee weapon, reacts to damage
## with red flash, armor clang sound, and light recoil.

signal damaged(amount: float)
signal died

enum Mode {
	PATROL_GATE,
	FOLLOW_HERO,
}

const HURT_SOUND: AudioStream = preload("res://assets/audio/hero_hurt.wav")
const SWING_SOUND: AudioStream = preload("res://assets/audio/sword_swing.wav")
const MODEL_SCENE: PackedScene = preload("res://assets/models/hero_knight.glb")
const DEATH_FX: PackedScene = preload("res://scenes/fx/death_fx.tscn")
const GROUP := &"mercenaries"

@export var max_health: float = 80.0
@export var health: float = 80.0
@export var attack_damage: float = 16.0
@export var attack_range: float = 1.4
@export var attack_cooldown: float = 0.55
@export var speed: float = 3.0
@export var turn_speed: float = 12.0
@export var detection_radius: float = 9.0
@export var patrol_radius: float = 2.5

var mode: Mode = Mode.PATROL_GATE
var patrol_center: Vector3 = Vector3.ZERO
var hero: Hero = null
var sim: Sim = null
var target_enemy: Enemy = null

var _damage_flash_timer: float = 0.0
var _recoil_velocity: Vector3 = Vector3.ZERO
var _attack_timer: float = 0.0
var _patrol_angle: float = 0.0
var _patrol_target: Vector3 = Vector3.ZERO
var _patrol_wait: float = 0.0
var _flash_material: StandardMaterial3D = null
var _meshes: Array[GeometryInstance3D] = []
var _hp_bar: MeshInstance3D = null
var _hp_bg: MeshInstance3D = null
var _badge: Label3D = null

@onready var _model: Node3D = find_child("Model") as Node3D
@onready var _puppet: Puppet = find_child("Puppet") as Puppet
@onready var _swing_sound: AudioStreamPlayer3D = find_child("SwingSound") as AudioStreamPlayer3D
@onready var _hurt_sound: AudioStreamPlayer3D = find_child("HurtSound") as AudioStreamPlayer3D


func _ready() -> void:
	add_to_group(GROUP)
	health = max_health
	if patrol_center == Vector3.ZERO:
		patrol_center = global_position
	_ensure_castle_clearance()
	_patrol_target = patrol_center

	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.albedo_color = Color(1.0, 0.2, 0.2, 0.65)
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	if _model == null:
		_model = MODEL_SCENE.instantiate() as Node3D
		_model.name = "Model"
		add_child(_model)

	if _puppet == null:
		_puppet = Puppet.new()
		_puppet.name = "Puppet"
		_puppet.model = _model
		add_child(_puppet)

	if _swing_sound == null:
		_swing_sound = AudioStreamPlayer3D.new()
		_swing_sound.name = "SwingSound"
		_swing_sound.stream = SWING_SOUND
		_swing_sound.volume_db = -8.0
		add_child(_swing_sound)

	if _hurt_sound == null:
		_hurt_sound = AudioStreamPlayer3D.new()
		_hurt_sound.name = "HurtSound"
		_hurt_sound.stream = HURT_SOUND
		_hurt_sound.volume_db = -4.0
		add_child(_hurt_sound)

	for mesh: Node in _model.find_children("*", "GeometryInstance3D", true, false):
		_meshes.append(mesh as GeometryInstance3D)
		if mesh.name != &"Body":
			(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Distinct mercenary appearance (bronze/forest green tunic)
	var tunic_mat := StandardMaterial3D.new()
	tunic_mat.albedo_color = Color(0.28, 0.48, 0.32)
	for mesh in _meshes:
		if mesh.name == &"Body":
			mesh.material_override = tunic_mat

	# Overhead badge and health bar
	_badge = Label3D.new()
	_badge.name = "Badge"
	_badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_badge.no_depth_test = true
	_badge.font_size = 18
	_badge.pixel_size = 0.0035
	_badge.position = Vector3(0.0, 1.35, 0.0)
	_badge.text = "🛡 " + tr("CARD_HIRE_NAME")
	_badge.modulate = Color(0.85, 1.0, 0.85)
	add_child(_badge)

	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(0.65, 0.08)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.8)
	_hp_bg = MeshInstance3D.new()
	_hp_bg.name = "HealthBarBg"
	_hp_bg.mesh = bg_mesh
	_hp_bg.material_override = bg_mat
	_hp_bg.position = Vector3(0.0, 1.18, 0.0)
	add_child(_hp_bg)

	var bar_mesh := QuadMesh.new()
	bar_mesh.size = Vector2(0.62, 0.06)
	var bar_mat := StandardMaterial3D.new()
	bar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar_mat.albedo_color = Color(0.2, 0.85, 0.3, 0.95)
	_hp_bar = MeshInstance3D.new()
	_hp_bar.name = "HealthBar"
	_hp_bar.mesh = bar_mesh
	_hp_bar.material_override = bar_mat
	_hp_bar.position = Vector3(0.0, 1.18, 0.01)
	add_child(_hp_bar)


func _process(_delta: float) -> void:
	if not is_alive():
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		if _hp_bg != null and is_instance_valid(_hp_bg):
			_hp_bg.rotation = cam.global_rotation
		if _hp_bar != null and is_instance_valid(_hp_bar):
			_hp_bar.rotation = cam.global_rotation


func _update_hp_bar() -> void:
	if _hp_bar == null or not is_instance_valid(_hp_bar):
		return
	var ratio := clampf(health / max_health, 0.0, 1.0)
	_hp_bar.scale.x = ratio
	_hp_bar.position.x = -0.31 * (1.0 - ratio)
	var mat := _hp_bar.material_override as StandardMaterial3D
	if mat != null:
		if ratio < 0.25:
			mat.albedo_color = Color(0.9, 0.2, 0.2, 0.95)
		elif ratio < 0.5:
			mat.albedo_color = Color(0.95, 0.8, 0.1, 0.95)
		else:
			mat.albedo_color = Color(0.2, 0.85, 0.3, 0.95)


func _physics_process(delta: float) -> void:
	if not is_alive():
		return
	if _damage_flash_timer > 0.0:
		_damage_flash_timer = maxf(_damage_flash_timer - delta, 0.0)
		if _damage_flash_timer == 0.0:
			_set_flash_overlay(false)
	if _recoil_velocity.length_squared() > 0.001:
		_recoil_velocity = _recoil_velocity.move_toward(Vector3.ZERO, delta * 12.0)
	_attack_timer = maxf(_attack_timer - delta, 0.0)

	_update_target_enemy()

	var dir := Vector3.ZERO
	if target_enemy != null:
		var to_enemy: Vector3 = target_enemy.global_position - global_position
		to_enemy.y = 0.0
		var dist: float = to_enemy.length()
		if dist <= attack_range:
			dir = Vector3.ZERO
			if _attack_timer <= 0.0:
				_attack(target_enemy)
		else:
			dir = to_enemy.normalized()
	elif mode == Mode.FOLLOW_HERO and hero != null and is_instance_valid(hero):
		var to_hero: Vector3 = hero.global_position - global_position
		to_hero.y = 0.0
		if to_hero.length() > 2.5:
			dir = to_hero.normalized()
	else:
		dir = _patrol_step(delta)

	velocity = dir * speed + _recoil_velocity
	move_and_slide()
	position.y = 0.0
	_animate(dir, delta)


func _attack(enemy: Enemy) -> void:
	_attack_timer = attack_cooldown
	if _swing_sound != null:
		_swing_sound.pitch_scale = randf_range(0.9, 1.1)
		_swing_sound.play()
	if _puppet != null:
		if _puppet.has_method(&"play_action"):
			_puppet.play_action(&"attack")
		elif _puppet.has_method(&"swing"):
			_puppet.swing()
	if enemy != null and is_instance_valid(enemy) and enemy.is_alive():
		enemy.take_damage(attack_damage)


func take_damage(amount: float, from_dir: Vector3 = Vector3.ZERO) -> void:
	if not is_alive():
		return
	health = maxf(health - amount, 0.0)
	_damage_flash_timer = 0.25
	_set_flash_overlay(true)
	_update_hp_bar()
	if _hurt_sound != null:
		_hurt_sound.pitch_scale = randf_range(0.92, 1.08)
		_hurt_sound.play()
	var recoil_dir: Vector3 = from_dir.normalized()
	if recoil_dir.length_squared() < 0.01:
		recoil_dir = -transform.basis.z
	recoil_dir.y = 0.0
	_recoil_velocity = recoil_dir.normalized() * 3.5
	damaged.emit(amount)
	if health <= 0.0:
		_die()


func is_flashing() -> bool:
	return _damage_flash_timer > 0.0


func _die() -> void:
	died.emit()
	if sim != null:
		sim.remove_mercenary(self)
	if DEATH_FX != null:
		var fx := DEATH_FX.instantiate() as Node3D
		fx.top_level = true
		get_parent().add_child(fx)
		fx.global_position = global_position
	queue_free()


func _set_flash_overlay(on: bool) -> void:
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = _flash_material if on else null


func _get_castle_position() -> Vector3:
	if not is_inside_tree():
		return Vector3.ZERO
	var c := get_node_or_null("../Castle") as Node3D
	if c != null and is_instance_valid(c):
		return c.global_position
	if get_tree().current_scene != null:
		var c_scene := get_tree().current_scene.find_child("Castle", true, false) as Node3D
		if c_scene != null and is_instance_valid(c_scene):
			return c_scene.global_position
	var group_nodes := get_tree().get_nodes_in_group(&"castle")
	if not group_nodes.is_empty():
		var node := group_nodes[0] as Node3D
		if node != null and is_instance_valid(node):
			return node.global_position
	return Vector3.ZERO


func _push_away_from(point: Vector3, center: Vector3, min_dist: float = 3.5, safe_dist: float = 4.0) -> Vector3:
	var offset: Vector3 = point - center
	offset.y = 0.0
	var dist: float = offset.length()
	if dist < min_dist:
		var dir := offset.normalized() if dist >= 0.01 else Vector3(0.0, 0.0, 1.0)
		return center + dir * safe_dist
	return point


func _ensure_castle_clearance() -> void:
	var castle_pos: Vector3 = _get_castle_position()
	patrol_center = _push_away_from(patrol_center, castle_pos)
	if castle_pos != Vector3.ZERO:
		patrol_center = _push_away_from(patrol_center, Vector3.ZERO)


func _patrol_step(delta: float) -> Vector3:
	_ensure_castle_clearance()
	var castle_pos: Vector3 = _get_castle_position()
	_patrol_target = _push_away_from(_patrol_target, castle_pos)
	if castle_pos != Vector3.ZERO:
		_patrol_target = _push_away_from(_patrol_target, Vector3.ZERO)

	_patrol_wait = maxf(_patrol_wait - delta, 0.0)
	var to_target: Vector3 = _patrol_target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.35:
		if _patrol_wait <= 0.0:
			_patrol_angle += randf_range(1.2, 2.8)
			var r: float = randf_range(0.6, patrol_radius)
			var candidate: Vector3 = patrol_center + Vector3(cos(_patrol_angle) * r, 0.0, sin(_patrol_angle) * r)
			candidate = _push_away_from(candidate, castle_pos)
			if castle_pos != Vector3.ZERO:
				candidate = _push_away_from(candidate, Vector3.ZERO)
			_patrol_target = candidate
			_patrol_wait = randf_range(1.0, 2.5)
		return Vector3.ZERO
	return to_target.normalized()


func _update_target_enemy() -> void:
	if target_enemy != null and (not is_instance_valid(target_enemy) or not target_enemy.is_alive()):
		target_enemy = null
	if target_enemy != null:
		var d: float = global_position.distance_to(target_enemy.global_position)
		if d > detection_radius * 1.5:
			target_enemy = null
	if target_enemy == null and sim != null:
		var best: Enemy = null
		var best_d: float = detection_radius
		for enemy: Enemy in sim.enemies:
			if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
				continue
			var d: float = global_position.distance_to(enemy.global_position)
			var d_gate: float = enemy.global_position.distance_to(patrol_center)
			var score: float = minf(d, d_gate * 0.8)
			if score <= best_d:
				best_d = score
				best = enemy
		target_enemy = best


func _animate(direction: Vector3, delta: float) -> void:
	if direction.length() > 0.05:
		var yaw: float = atan2(direction.x, direction.z)
		_model.rotation.y = rotate_toward(_model.rotation.y, yaw, turn_speed * delta)
	elif target_enemy != null and is_instance_valid(target_enemy):
		var offset: Vector3 = target_enemy.global_position - global_position
		offset.y = 0.0
		if offset.length() > 0.01:
			var yaw: float = atan2(offset.x, offset.z)
			_model.rotation.y = rotate_toward(_model.rotation.y, yaw, turn_speed * delta)


func is_alive() -> bool:
	return health > 0.0


func is_patrolling() -> bool:
	return mode == Mode.PATROL_GATE


func sim_step() -> void:
	if not is_alive():
		return
	_update_target_enemy()


func state_ints() -> Array[int]:
	return [
		roundi(global_position.x * 1000.0),
		roundi(global_position.z * 1000.0),
		roundi(health * 10.0),
		mode,
	]
