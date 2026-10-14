class_name WaveManager
extends Node
## Spawns enemies onto enemy_path following a WavePlan. Waves run on a fixed
## clock: every wave lasts plan.wave_duration seconds (its enemies are spread
## over the first plan.spawn_window of it) and then the next one starts,
## whether or not the previous one is cleared. Waves may overlap.

signal wave_started(wave: int, total: int, boss: bool)
## All enemies of `wave` are gone (killed or reached the castle).
signal wave_cleared(wave: int)
signal all_waves_cleared
signal enemy_killed(reward: int)
signal enemy_reached_base(damage: int)

@export var enemy_scene: PackedScene
@export var enemy_path: Path3D
## Shared MultiMesh renderer for all enemies (optional).
@export var crowd: EnemyCrowd

var current_wave: int = 0
var plan: WavePlan = null

var _stopped: bool = false
var _alive: int = 0
## Per running wave: {"wave": int, "queue": Array[Dictionary], "interval": float, "left": float}
var _spawners: Array[Dictionary] = []
## Enemies still alive (or still to spawn) per wave number.
var _remaining: Dictionary = {}
var _next_wave_timer: Timer


func _ready() -> void:
	_next_wave_timer = Timer.new()
	_next_wave_timer.one_shot = true
	_next_wave_timer.timeout.connect(start_next_wave)
	add_child(_next_wave_timer)


func _process(delta: float) -> void:
	if _stopped:
		return
	var i: int = 0
	while i < _spawners.size():
		var spawner: Dictionary = _spawners[i]
		spawner["left"] -= delta
		var queue: Array = spawner["queue"]
		if queue.is_empty():
			_spawners.remove_at(i)
			continue
		if spawner["left"] <= 0.0:
			_spawn_enemy(queue.pop_front(), spawner["wave"])
			spawner["left"] += spawner["interval"]
			if queue.is_empty():
				_spawners.remove_at(i)
				continue
		i += 1


func get_total_waves() -> int:
	return plan.wave_count


## Seconds until the next wave starts, or -1 if none is coming.
func time_to_next_wave() -> float:
	if _stopped or _next_wave_timer.is_stopped():
		return -1.0
	return _next_wave_timer.time_left


## True while enemies of any wave are on the map or still to spawn.
func is_wave_active() -> bool:
	return not _remaining.is_empty()


func has_next_wave() -> bool:
	return not _stopped and current_wave < plan.wave_count


func alive_count() -> int:
	return _alive


## Starts the next wave after `delay` seconds unless one starts earlier.
func schedule_next_wave(delay: float) -> void:
	if has_next_wave():
		_next_wave_timer.start(delay)


## Starts the next wave now (the clock for the one after restarts).
## Returns false if no waves are left.
func start_next_wave() -> bool:
	if not has_next_wave():
		return false
	current_wave += 1
	var queue: Array[Dictionary] = plan.spawns(current_wave)
	_remaining[current_wave] = queue.size()
	var interval: float = plan.spawn_window / maxf(queue.size(), 1.0)
	_spawners.append({"wave": current_wave, "queue": queue, "interval": interval, "left": 0.0})
	wave_started.emit(current_wave, plan.wave_count, plan.is_boss_wave(current_wave))
	if has_next_wave():
		_next_wave_timer.start(plan.wave_duration)
	return true


## Stops spawning for good, e.g. after defeat.
func stop() -> void:
	_stopped = true
	_spawners.clear()
	_next_wave_timer.stop()


## Adds an extra enemy of `data` at `progress` along the path (e.g. the halves
## of a splitting slime); it counts towards `wave`.
func spawn_extra(data: EnemyData, health_mult: float, progress: float, wave: int) -> void:
	if _stopped:
		return
	_remaining[wave] = int(_remaining.get(wave, 0)) + 1
	var enemy := _spawn_enemy({"data": data, "hp": health_mult}, wave)
	enemy.progress = progress


func _spawn_enemy(entry: Dictionary, wave: int) -> Enemy:
	var enemy := enemy_scene.instantiate() as Enemy
	enemy.setup(entry["data"], entry["hp"])
	enemy.wave = wave
	enemy.crowd = crowd
	enemy.died.connect(_on_enemy_gone.bind(wave, true), CONNECT_ONE_SHOT)
	enemy.died.connect(enemy_killed.emit)
	enemy.reached_base.connect(_on_enemy_gone.bind(wave, false), CONNECT_ONE_SHOT)
	enemy.reached_base.connect(enemy_reached_base.emit)
	enemy.split.connect(_on_enemy_split)
	enemy_path.add_child(enemy)
	_alive += 1
	return enemy


func _on_enemy_split(data: EnemyData, health_mult: float, progress: float, wave: int) -> void:
	spawn_extra(data, health_mult, progress, wave)


func _on_enemy_gone(_value: int, wave: int, _killed: bool) -> void:
	_alive -= 1
	_remaining[wave] = int(_remaining.get(wave, 1)) - 1
	if _remaining[wave] <= 0:
		_remaining.erase(wave)
		wave_cleared.emit(wave)
	if not _stopped and not has_next_wave() and _remaining.is_empty() and _spawners.is_empty():
		all_waves_cleared.emit()
