class_name WaveManager
extends Node
## Spawns enemies wave by wave onto enemy_path using a WaveConfig.
## Only one wave can be active at a time.

signal wave_started(wave: int, total: int)
signal wave_cleared(wave: int)
signal all_waves_cleared
signal enemy_killed(reward: int)
signal enemy_reached_base(damage: int)

@export var config: WaveConfig
@export var enemy_scene: PackedScene
@export var enemy_path: Path3D
## Start the next wave automatically after time_between_waves.
@export var auto_continue: bool = true

var current_wave: int = 0

var _wave_active: bool = false
var _stopped: bool = false
var _left_to_spawn: int = 0
var _alive: int = 0
var _wave_health: float = 0.0
var _spawn_timer: Timer
var _next_wave_timer: Timer


func _ready() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)
	_next_wave_timer = Timer.new()
	_next_wave_timer.one_shot = true
	_next_wave_timer.timeout.connect(start_next_wave)
	add_child(_next_wave_timer)


func get_total_waves() -> int:
	return config.wave_count


func is_wave_active() -> bool:
	return _wave_active


func has_next_wave() -> bool:
	return not _stopped and current_wave < config.wave_count


## Starts the next wave after delay seconds unless one starts earlier.
func schedule_next_wave(delay: float) -> void:
	if has_next_wave() and not _wave_active:
		_next_wave_timer.start(delay)


## Returns false if a wave is already running or none are left.
func start_next_wave() -> bool:
	if _wave_active or not has_next_wave():
		return false
	_next_wave_timer.stop()
	current_wave += 1
	_wave_active = true
	_left_to_spawn = config.get_enemy_count(current_wave)
	_wave_health = config.get_enemy_health(current_wave)
	wave_started.emit(current_wave, config.wave_count)
	_spawn_enemy()
	if _left_to_spawn > 0:
		_spawn_timer.start(config.spawn_interval)
	return true


## Stops spawning for good, e.g. after defeat.
func stop() -> void:
	_stopped = true
	_spawn_timer.stop()
	_next_wave_timer.stop()


func _spawn_enemy() -> void:
	var enemy := enemy_scene.instantiate() as Enemy
	enemy.max_health = _wave_health
	enemy.speed = config.enemy_speed
	enemy.reward = config.enemy_reward
	enemy.base_damage = config.enemy_base_damage
	enemy.died.connect(_on_enemy_died)
	enemy.reached_base.connect(_on_enemy_reached_base)
	enemy_path.add_child(enemy)
	_left_to_spawn -= 1
	_alive += 1


func _on_spawn_timer_timeout() -> void:
	if _stopped or _left_to_spawn <= 0:
		_spawn_timer.stop()
		return
	_spawn_enemy()
	if _left_to_spawn <= 0:
		_spawn_timer.stop()


func _on_enemy_died(reward: int) -> void:
	_alive -= 1
	enemy_killed.emit(reward)
	_check_wave_end()


func _on_enemy_reached_base(damage: int) -> void:
	_alive -= 1
	enemy_reached_base.emit(damage)
	_check_wave_end()


func _check_wave_end() -> void:
	if not _wave_active or _left_to_spawn > 0 or _alive > 0:
		return
	_wave_active = false
	wave_cleared.emit(current_wave)
	if _stopped:
		return
	if current_wave >= config.wave_count:
		all_waves_cleared.emit()
	elif auto_continue:
		schedule_next_wave(config.time_between_waves)
