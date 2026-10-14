class_name WaveManager
extends Node
## Spawns enemies onto the level's paths following a WavePlan. Waves run on a fixed
## clock: every wave lasts plan.wave_duration seconds (its enemies are spread
## over the first plan.spawn_window of it) and then the next one starts,
## whether or not the previous one is cleared. Waves may overlap.
## With several paths every enemy kind takes them in turn (the 1st slime the
## first path, the 2nd slime the second, ...; bosses alternate the same way).
## Runs on the simulation clock: sim_step() is called by Sim once per step and
## all times here are step numbers, not frames.

signal wave_started(wave: int, total: int, boss: bool)
## All enemies of `wave` are gone (killed or reached the castle).
signal wave_cleared(wave: int)
signal all_waves_cleared
signal enemy_killed(reward: int)
signal enemy_reached_base(damage: int)

@export var enemy_scene: PackedScene
## The only path when enemy_paths is empty.
@export var enemy_path: Path3D
## Shared MultiMesh renderer for all enemies (optional).
@export var crowd: EnemyCrowd
## The simulation clock (set by the level before the first wave is scheduled).
var sim: Sim = null

var current_wave: int = 0
var plan: WavePlan = null
## Every route from a portal to the castle (set by the level).
var enemy_paths: Array[Path3D] = []

## Enemies killed / that reached the castle so far.
var killed: int = 0
var leaked: int = 0

var _stopped: bool = false
var _alive: int = 0
## Per running wave: {"wave", "queue": Array[Dictionary], "start": step the wave began,
## "span": steps over which its enemies come out, "index": next one to spawn}.
var _spawners: Array[Dictionary] = []
## Enemies still alive (or still to spawn) per wave number.
var _remaining: Dictionary = {}
## Step at which the next wave starts, or -1.
var _next_wave_tick: int = -1
## Enemies spawned so far per EnemyData: picks the next path for that kind.
var _spawned_by_kind: Dictionary = {}

## One fixed simulation step (called by Sim): the wave clock and spawning.
@warning_ignore("integer_division")
func sim_step(tick: int) -> void:
	if _stopped:
		return
	if _next_wave_tick >= 0 and tick >= _next_wave_tick:
		start_next_wave()
	var i: int = 0
	while i < _spawners.size():
		var spawner: Dictionary = _spawners[i]
		var queue: Array = spawner["queue"]
		var total: int = queue.size()
		var index: int = spawner["index"]
		# Enemy k comes out at step start + k * span / total (whole steps; several
		# can come in one step if the span is shorter than the queue).
		while (
			index < total and tick - int(spawner["start"]) >= index * int(spawner["span"]) / total
		):
			_spawn_enemy(queue[index], spawner["wave"])
			index += 1
		spawner["index"] = index
		if index >= total:
			_spawners.remove_at(i)
			continue
		i += 1


## Integers describing the wave state (for Sim.state_hash).
func state_ints() -> Array[int]:
	var out: Array[int] = [current_wave, _alive, _next_wave_tick, killed, leaked, _spawners.size()]
	for spawner in _spawners:
		out.append(int(spawner["index"]))
		out.append(int(spawner["start"]))
	return out


func get_total_waves() -> int:
	return plan.wave_count


## Seconds until the next wave starts, or -1 if none is coming.
func time_to_next_wave() -> float:
	if _stopped or _next_wave_tick < 0:
		return -1.0
	return maxi(_next_wave_tick - sim.tick, 0) * Sim.TICK_DT


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
		_next_wave_tick = sim.tick + Sim.ticks(delay)


## Starts the next wave now (the clock for the one after restarts).
## Returns false if no waves are left.
func start_next_wave() -> bool:
	if not has_next_wave():
		return false
	current_wave += 1
	_next_wave_tick = -1
	var queue: Array[Dictionary] = plan.spawns(current_wave)
	_remaining[current_wave] = queue.size()
	(
		_spawners
		. append(
			{
				"wave": current_wave,
				"queue": queue,
				"start": sim.tick,
				"span": Sim.ticks(plan.spawn_window),
				"index": 0,
			}
		)
	)
	wave_started.emit(current_wave, plan.wave_count, plan.is_boss_wave(current_wave))
	if has_next_wave():
		_next_wave_tick = sim.tick + Sim.ticks(plan.wave_duration)
	return true


## Stops spawning for good, e.g. after defeat.
func stop() -> void:
	_stopped = true
	_spawners.clear()
	_next_wave_tick = -1


## Paths enemies walk: enemy_paths, or just enemy_path.
func get_paths() -> Array[Path3D]:
	if enemy_paths.is_empty():
		return [enemy_path]
	return enemy_paths


## Adds an extra enemy of `data` at `progress` along `path` (default: the first)
## (e.g. the halves of a splitting slime); it counts towards `wave`.
func spawn_extra(
	data: EnemyData, health_mult: float, progress: float, wave: int, path: Path3D = null
) -> void:
	if _stopped:
		return
	_remaining[wave] = int(_remaining.get(wave, 0)) + 1
	var enemy := _spawn_enemy({"data": data, "hp": health_mult}, wave, path)
	enemy.place(progress)


## `path` null: the next path in turn for this enemy kind.
func _spawn_enemy(entry: Dictionary, wave: int, path: Path3D = null) -> Enemy:
	if path == null:
		var paths: Array[Path3D] = get_paths()
		var spawned: int = _spawned_by_kind.get(entry["data"], 0)
		_spawned_by_kind[entry["data"]] = spawned + 1
		path = paths[spawned % paths.size()]
	var enemy := enemy_scene.instantiate() as Enemy
	enemy.setup(entry["data"], entry["hp"])
	enemy.wave = wave
	enemy.crowd = crowd
	enemy.sim = sim
	enemy.path = path
	# The enemy's own report (gold, lost lives) goes out before "wave cleared".
	enemy.died.connect(enemy_killed.emit)
	enemy.died.connect(_on_enemy_gone.bind(wave, true), CONNECT_ONE_SHOT)
	enemy.reached_base.connect(enemy_reached_base.emit)
	enemy.reached_base.connect(_on_enemy_gone.bind(wave, false), CONNECT_ONE_SHOT)
	enemy.split.connect(_on_enemy_split.bind(path))
	path.add_child(enemy)
	_alive += 1
	return enemy


func _on_enemy_split(
	data: EnemyData, health_mult: float, progress: float, wave: int, path: Path3D
) -> void:
	spawn_extra(data, health_mult, progress, wave, path)


func _on_enemy_gone(_value: int, wave: int, was_killed: bool) -> void:
	_alive -= 1
	if was_killed:
		killed += 1
	else:
		leaked += 1
	_remaining[wave] = int(_remaining.get(wave, 1)) - 1
	if _remaining[wave] <= 0:
		_remaining.erase(wave)
		wave_cleared.emit(wave)
	if not _stopped and not has_next_wave() and _remaining.is_empty() and _spawners.is_empty():
		all_waves_cleared.emit()
