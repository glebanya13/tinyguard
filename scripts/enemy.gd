class_name Enemy
extends PathFollow3D
## Walks along the parent Path3D towards the base. Built from EnemyData via
## setup() before entering the tree. Reports death and reaching the base
## through signals and frees itself in both cases.

signal died(reward: int)
signal reached_base(damage: int)

const GROUP := &"enemies"
const LOOPING_MODEL := preload("res://scripts/looping_model.gd")
## Progress ratio treated as "arrived" (avoids float equality at the end).
const ARRIVAL_RATIO := 0.999
## Height of the point projectiles aim at, relative to the model height.
const AIM_FRACTION := 0.45

@export var max_health: float = 30.0
## Movement speed in metres per second along the path.
@export var speed: float = 1.2
@export var reward: int = 5
@export var base_damage: int = 1
## Splash and coin burst spawned where the enemy dies.
@export var death_fx: PackedScene

var health: float = 0.0
var data: EnemyData = null

var _is_dead: bool = false
var _slow_factor: float = 1.0
var _slow_left: float = 0.0
var _bar_width: float = 1.0
var _model: Node3D = null

@onready var _health_bar: MeshInstance3D = $HealthBar


## Configure from an enemy type; health is multiplied by the wave factor.
func setup(enemy_data: EnemyData, health_multiplier: float) -> void:
	data = enemy_data
	max_health = data.health * health_multiplier
	speed = data.speed
	reward = data.reward
	base_damage = data.base_damage


func _ready() -> void:
	health = max_health
	add_to_group(GROUP)
	if data:
		_model = data.model.instantiate() as Node3D
		_model.set_script(LOOPING_MODEL)
		_model.rotation.y = PI  # models face +Z, PathFollow3D moves along -Z
		_model.position.y = data.fly_height
		add_child(_model)
		_health_bar.position.y = data.health_bar_height + data.fly_height
		_bar_width = data.health_bar_width / 0.6
		_health_bar.scale.x = _bar_width
		if data.is_boss:
			_health_bar.scale.y = 1.8
	# A full bar says nothing; hiding it saves a draw call per fresh enemy.
	_health_bar.visible = is_boss()


func _process(delta: float) -> void:
	if _is_dead:
		return
	if _slow_left > 0.0:
		_slow_left -= delta
		if _slow_left <= 0.0:
			_slow_factor = 1.0
	progress += speed * _slow_factor * delta
	if progress_ratio >= ARRIVAL_RATIO:
		_remove()
		reached_base.emit(base_damage)


## `kind` is the damage type of the hit (&"arrow" for archers, &"" otherwise).
func take_damage(amount: float, kind: StringName = &"") -> void:
	if _is_dead:
		return
	if kind == &"arrow" and data:
		amount *= data.arrow_damage_mult
	health = maxf(health - amount, 0.0)
	_health_bar.visible = true
	_health_bar.scale.x = _bar_width * health / max_health
	if health <= 0.0:
		_spawn_death_fx()
		_remove()
		died.emit(reward)
	elif _model:
		# Squash on hit.
		var tween := create_tween()
		_model.scale = Vector3(1.18, 0.82, 1.18)
		tween.tween_property(_model, "scale", Vector3.ONE, 0.18)


## Slows movement to `factor` of the normal speed for `duration` seconds.
func apply_slow(factor: float, duration: float) -> void:
	_slow_factor = minf(_slow_factor, factor)
	_slow_left = maxf(_slow_left, duration)


func is_alive() -> bool:
	return not _is_dead


func is_flying() -> bool:
	return data != null and data.flying


func is_boss() -> bool:
	return data != null and data.is_boss


func get_aim_point() -> Vector3:
	var height: float = data.health_bar_height * AIM_FRACTION + data.fly_height if data else 0.25
	return global_position + Vector3.UP * height


func _spawn_death_fx() -> void:
	if death_fx == null:
		return
	var fx := death_fx.instantiate() as Node3D
	add_sibling(fx)
	fx.global_position = get_aim_point()
	if is_boss():
		fx.scale = Vector3.ONE * 2.5


func _remove() -> void:
	_is_dead = true
	remove_from_group(GROUP)
	queue_free()
