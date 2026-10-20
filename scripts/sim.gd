class_name Sim
extends Node
## Clock and registry of the battle simulation. Real frame time is collected in
## an accumulator and spent in whole fixed steps of TICK_DT (30 Hz), so what
## happens depends only on the number of steps and on the commands applied
## between them, never on frame rate or time scale. Entities do not use
## `_process(delta)` for gameplay: they register here and get `sim_step()` once
## per step, always in the same order (waves, lumberjacks, enemies by id, towers by id,
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
const VERSION: int = 3
const TICK_RATE: int = 30
const TICK_DT: float = 1.0 / TICK_RATE
## Steps per frame at most (a long hitch must not freeze the game in catch-up).
const MAX_STEPS_PER_FRAME: int = 10
## Wall-clock budget of the steps of one frame, microseconds. When the steps of a frame
## take longer (a weak phone, hundreds of enemies) the rest of the debt is dropped: the
## game slows down instead of falling into a spiral where every frame owes more steps
## than the last and the picture freezes. One step is always done. Not applied when
## `manual` (tests count steps, not time).
const STEP_BUDGET_USEC: int = 22000
const LIFECYCLE_NOTIFICATIONS: Array[int] = [
	NOTIFICATION_APPLICATION_PAUSED,
	NOTIFICATION_APPLICATION_FOCUS_OUT,
	NOTIFICATION_APPLICATION_RESUMED,
	NOTIFICATION_APPLICATION_FOCUS_IN,
]
## Co-op: how many steps of real time may pile up while waiting for the partner.
const COOP_MAX_BACKLOG: int = 3
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
## Co-op: both knights by player slot (empty in single player: `hero` alone).
var heroes: Array[Hero] = []
## Co-op: the lockstep that gates the clock and delivers the commands (null otherwise).
var coop: CoopDriver = null
var villagers: Villagers = null

## Living entities in registration (= id) order.
var enemies: Array[Enemy] = []
var towers: Array[Tower] = []
var projectiles: Array[Projectile] = []
var trees: Array[WoodTree] = []
var outposts: Array[Outpost] = []
var mercenaries: Array[Mercenary] = []

## Frames in which the step budget ran out / steps lost to it (diagnostics, quality guard).
var over_budget_frames: int = 0
var dropped_steps: int = 0
## Wall time of the steps of the last frame, microseconds.
var last_frame_step_usec: int = 0

var _accum: float = 0.0
var _next_id: int = 1
var _next_thicket_id: int = 10000
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


func _notification(what: int) -> void:
	# Home button, phone call, switching apps: real time that passed while the game was
	# away is not game time (no burst of steps on return).
	if what in LIFECYCLE_NOTIFICATIONS:
		_accum = 0.0


## Seconds -> whole steps (at least 1).
static func ticks(seconds: float) -> int:
	return maxi(1, roundi(seconds * TICK_RATE))


## Collects `delta` seconds and runs the steps they pay for.
func advance(delta: float) -> void:
	if coop != null:
		coop.process(delta)  # the network runs even before the level is ready
	if not running:
		return
	_accum += delta
	var steps: int = 0
	var started: int = 0 if manual else Time.get_ticks_usec()
	while _accum >= TICK_DT and steps < MAX_STEPS_PER_FRAME:
		if coop != null and not coop.can_step():
			_accum = minf(_accum, COOP_MAX_BACKLOG * TICK_DT)  # waiting for the partner
			break
		_accum -= TICK_DT
		step()
		steps += 1
		if not manual and Time.get_ticks_usec() - started > STEP_BUDGET_USEC:
			if _accum >= TICK_DT:
				over_budget_frames += 1
				dropped_steps += int(_accum / TICK_DT)
			_accum = minf(_accum, TICK_DT)  # too slow: give up the debt
			break
	if steps >= MAX_STEPS_PER_FRAME:
		_accum = minf(_accum, TICK_DT)  # drop the backlog instead of spiralling
	if not manual:
		last_frame_step_usec = Time.get_ticks_usec() - started


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
	if tree.is_thicket:
		tree.id = _next_thicket_id
		_next_thicket_id += 1
	else:
		tree.id = next_id()
	trees.append(tree)


func add_outpost(outpost: Outpost) -> void:
	outposts.append(outpost)


func add_mercenary(mercenary: Mercenary) -> void:
	mercenaries.append(mercenary)
	mercenary.sim = self


func remove_mercenary(mercenary: Mercenary) -> void:
	mercenaries.erase(mercenary)


## One step of the simulation.
func step() -> void:
	_in_step = true
	_apply_journal()
	if coop != null:
		coop.before_step()
	var due: Array = _scheduled.get(tick, [])
	if not due.is_empty():
		_scheduled.erase(tick)
		for action: Callable in due:
			if action.is_valid():
				action.call()
	if wave_manager != null:
		wave_manager.sim_step(tick)
	if villagers != null:
		villagers.sim_step()
	for enemy in enemies.duplicate():
		enemy.sim_step()
	for merc in mercenaries.duplicate():
		merc.sim_step()
	for tower in towers.duplicate():
		tower.sim_step()
	for projectile in projectiles.duplicate():
		projectile.sim_step()
	_in_step = false
	tick += 1
	if coop != null:
		coop.after_step()
	ticked.emit(tick)


## Hash of everything that decides the battle (integers only, so it is exact).
func state_hash() -> int:
	var h: int = HASH_BASIS
	h = _mix(h, tick)
	h = _mix(h, rng.state())
	if game_state != null:
		h = _mix_all(h, [game_state.gold, game_state.wood, game_state.lives])
		if game_state.castle_level > 0:
			h = _mix(h, game_state.castle_level)
	if wave_manager != null:
		h = _mix_all(h, wave_manager.state_ints())
	if not heroes.is_empty():
		for knight in heroes:
			h = _mix_all(h, knight.state_ints())
	elif hero != null:
		h = _mix_all(h, hero.state_ints())
	if villagers != null:
		h = _mix(h, villagers.lots_sold)
		h = _mix_all(h, villagers.state_ints())
	if not mercenaries.is_empty():
		h = _mix(h, mercenaries.size())
		for merc in mercenaries:
			h = _mix_all(h, merc.state_ints())
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
		if not tree.is_thicket:
			h = _mix_all(h, tree.state_ints())
		elif tree.hits_left() < tree.hits or tree.regrow_at() >= 0:
			h = _mix_all(h, tree.state_ints())
	for outpost in outposts:
		if outpost.flow_pct() < 100:
			h = _mix_all(h, outpost.state_ints())
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
