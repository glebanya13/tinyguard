class_name Enemy
extends PathFollow3D
## Walks along the parent Path3D towards the base. Reports death and
## reaching the base through signals and frees itself in both cases.

signal died(reward: int)
signal reached_base(damage: int)

const GROUP := &"enemies"
## Progress ratio treated as "arrived" (avoids float equality at the end).
const ARRIVAL_RATIO := 0.999
## Height of the point projectiles aim at, relative to the path.
const AIM_HEIGHT := 0.25

@export var max_health: float = 30.0
## Movement speed in metres per second along the path.
@export var speed: float = 1.2
@export var reward: int = 5
@export var base_damage: int = 1

var health: float = 0.0

var _is_dead: bool = false

@onready var _health_bar: MeshInstance3D = $HealthBar


func _ready() -> void:
	health = max_health
	add_to_group(GROUP)


func _process(delta: float) -> void:
	if _is_dead:
		return
	progress += speed * delta
	if progress_ratio >= ARRIVAL_RATIO:
		_remove()
		reached_base.emit(base_damage)


func take_damage(amount: float) -> void:
	if _is_dead:
		return
	health = maxf(health - amount, 0.0)
	_health_bar.scale.x = health / max_health
	if health <= 0.0:
		_remove()
		died.emit(reward)


func is_alive() -> bool:
	return not _is_dead


func get_aim_point() -> Vector3:
	return global_position + Vector3.UP * AIM_HEIGHT


func _remove() -> void:
	_is_dead = true
	remove_from_group(GROUP)
	queue_free()
