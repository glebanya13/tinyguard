class_name WaveConfig
extends Resource
## Wave balance data. Wave numbers are 1-based; every next wave adds enemies
## and multiplies their health.

@export var wave_count: int = 5
@export var first_wave_delay: float = 3.0
@export var time_between_waves: float = 5.0
## Seconds between two enemies of the same wave.
@export var spawn_interval: float = 1.6

@export_group("Enemy count")
@export var base_enemy_count: int = 5
@export var enemy_count_step: int = 1

@export_group("Enemy stats")
@export var base_enemy_health: float = 30.0
## Health multiplier applied once per wave after the first.
@export var enemy_health_growth: float = 1.2
@export var enemy_speed: float = 1.2
@export var enemy_reward: int = 5
@export var enemy_base_damage: int = 1


func get_enemy_count(wave: int) -> int:
	return base_enemy_count + enemy_count_step * (wave - 1)


func get_enemy_health(wave: int) -> float:
	return base_enemy_health * pow(enemy_health_growth, wave - 1)
