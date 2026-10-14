class_name Sim
extends Node
## Clock and registry of the battle simulation. Real frame time is collected in
## an accumulator and spent in whole fixed steps of TICK_DT (30 Hz), so what
## happens depends only on the number of steps and on the commands applied
## between them, never on frame rate or time scale. Entities do not use
## `_process(delta)` for gameplay: they register here and get `sim_step()` once
## per step, always in the same order (waves, enemies by id, towers by id,
## projectiles by id). Their nodes only draw (interpolating by `alpha()`).
##
## Commands (GameCommands) are applied between steps; with a journal set by
## begin_replay() they come from the journal instead of the player.

## A step was finished; `tick` is the number of steps done.
signal ticked(tick: int)
signal pause_changed(paused: bool)
signal speed_changed(speed: int)
## A replay is about to run: listeners adopt what its header says (perks).
signal replay_begun(header: Dictionary)

## Bump on any change that alters battle results (replays of other versions are stale).
const VERSION: int = 1
const TICK_RATE: int = 30
const TICK_DT: float = 1.0 / TICK_RATE
## Steps per frame at most (a long hitch must not freeze the game in catch-up).
const MAX_STEPS_PER_FRAME: int = 10
## FNV-1a 64-bit (as signed integers).
const HASH_BASIS: int = -3750763034362895579
const HASH_PRIME: int = 1099511628211

## The simulation of the running battle: entities made outside the main scene's
## wiring (tests, tools) find it here. Everything else gets `sim` passed in.
static var current: Sim = null

## Steps done so far.
var tick: int = 0
## False until the level is ready (walk grid built); the clock does not run before.
var running: bool = false
## Tests drive the clock by calling advance() themselves.
var manual: bool = false
var seed_value: int = 0
## Gameplay randomness (see SimRng). Nothing in the battle uses it yet.
var rng: SimRng = SimRng.new()
## Last value of the pause / speed commands (the clock itself ignores them:
## a paused tree simply gets no frames, and x2 is just twice as many frames).
var paused: bool = false
var speed: int = 1

var commands: GameCommands = null
var game_state: GameState = null
var wave_manager: WaveManager = null
var hero: Hero = null
var villagers: Villagers = null

## Living entities in registration (= id) order.
var enemies: Array[Enemy] = []
var towers: Array[Tower] = []
var projectiles: Array[Projectile] = []
var trees: Array[WoodTree] = []

var _accum: float = 0.0
var _next_id: int = 1
var _in_step: bool = false
## tick -> Array[Callable] run at the start of that step, in scheduling order.
var _scheduled: Dictionary = {}
var _replay: CommandLog = null
var _replay_index: int = 0


func _init() -> void:
	process_priority = -100  # before every node that draws what the sim computed


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func _process(delta: float) -> void:
	if not manual:
		advance(delta)


## Seconds -> whole steps (at least 1).
static func ticks(seconds: float) -> int:
	return maxi(1, roundi(seconds * TICK_RATE))


## Collects `delta` seconds and runs the steps they pay for.
func advance(delta: float) -> void:
	if not running:
		return
	_accum += delta
	var steps: int = 0
	while _accum >= TICK_DT and steps < MAX_STEPS_PER_FRAME:
		_accum -= TICK_DT
		step()
		steps += 1
	if steps >= MAX_STEPS_PER_FRAME:
		_accum = minf(_accum, TICK_DT)  # drop the backlog instead of spiralling


## Position between the last two steps (0..1) for drawing.
func alpha() -> float:
	return clampf(_accum / TICK_DT, 0.0, 1.0) if running else 1.0


## Begins the clock (called once the level is built).
func start() -> void:
	running = true


func set_seed(new_seed: int) -> void:
	seed_value = new_seed
	rng.reseed(new_seed)


## Next stable id (enemies, towers, projectiles and trees share one counter).
func next_id() -> int:
	var id: int = _next_id
	_next_id += 1
	return id


## Journal of a recorded battle: its commands are applied at their ticks and
## live commands are refused. Call before the clock starts.
func begin_replay(journal: CommandLog) -> void:
	_replay = journal
	_replay_index = 0
	set_seed(int(journal.header.get("seed", 0)))
	replay_begun.emit(journal.header)


func is_replaying() -> bool:
	return _replay != null


func is_in_step() -> bool:
	return _in_step


func set_paused(on: bool) -> void:
	paused = on
	pause_changed.emit(on)


func set_speed(new_speed: int) -> void:
	speed = new_speed
	speed_changed.emit(new_speed)


## Runs `action` at the start of the step `delay` steps from now (a replacement
## for Timer / create_timer in gameplay).
func schedule_in(delay: int, action: Callable) -> void:
	var at: int = tick + maxi(delay, 1 if _in_step else 0)
	if not _scheduled.has(at):
		_scheduled[at] = []
	(_scheduled[at] as Array).append(action)


func add_enemy(enemy: Enemy) -> void:
	enemy.id = next_id()
	enemies.append(enemy)


func remove_enemy(enemy: Enemy) -> void:
	enemies.erase(enemy)


func add_tower(tower: Tower) -> void:
	tower.id = next_id()
	towers.append(tower)


func remove_tower(tower: Tower) -> void:
	towers.erase(tower)


func add_projectile(projectile: Projectile) -> void:
	projectile.id = next_id()
	projectiles.append(projectile)


func remove_projectile(projectile: Projectile) -> void:
	projectiles.erase(projectile)


func add_tree(tree: WoodTree) -> void:
	tree.id = next_id()
	trees.append(tree)


## One step of the simulation.
func step() -> void:
	_in_step = true
	_apply_journal()
	var due: Array = _scheduled.get(tick, [])
	if not due.is_empty():
		_scheduled.erase(tick)
		for action: Callable in due:
			if action.is_valid():
				action.call()
	if wave_manager != null:
		wave_manager.sim_step(tick)
	for enemy in enemies.duplicate():
		enemy.sim_step()
	for tower in towers.duplicate():
		tower.sim_step()
	for projectile in projectiles.duplicate():
		projectile.sim_step()
	_in_step = false
	tick += 1
	ticked.emit(tick)


## Hash of everything that decides the battle (integers only, so it is exact).
func state_hash() -> int:
	var h: int = HASH_BASIS
	h = _mix(h, tick)
	h = _mix(h, rng.state())
	if game_state != null:
		h = _mix_all(h, [game_state.gold, game_state.wood, game_state.lives])
	if wave_manager != null:
		h = _mix_all(h, wave_manager.state_ints())
	if hero != null:
		h = _mix_all(h, hero.state_ints())
	if villagers != null:
		h = _mix(h, villagers.lots_sold)
	h = _mix(h, enemies.size())
	for enemy in enemies:
		h = _mix_all(h, enemy.state_ints())
	h = _mix(h, towers.size())
	for tower in towers:
		h = _mix_all(h, tower.state_ints())
	h = _mix(h, projectiles.size())
	for projectile in projectiles:
		h = _mix_all(h, projectile.state_ints())
	for tree in trees:
		h = _mix_all(h, tree.state_ints())
	return h


func _apply_journal() -> void:
	if _replay == null or commands == null:
		return
	var list: Array[GameCommand] = _replay.commands
	while _replay_index < list.size() and list[_replay_index].tick <= tick:
		commands.apply(list[_replay_index])
		_replay_index += 1


func _mix(h: int, value: int) -> int:
	return (h ^ value) * HASH_PRIME


func _mix_all(h: int, values: Array) -> int:
	for value: int in values:
		h = _mix(h, value)
	return h
