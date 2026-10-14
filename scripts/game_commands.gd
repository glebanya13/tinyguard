class_name GameCommands
extends Node
## The single entry for everything the player does in a battle (build, upgrade,
## sell, forge, trade, hero swings, pause, speed). UI code builds a GameCommand
## and calls submit(): it is stamped with the current tick, executed and
## written to the journal. A replay (Sim.begin_replay) calls apply() with the
## journal's commands instead and refuses live ones.
##
## Reach checks ("is the knight at the slot?") stay in the UI, which walks the
## hero there before issuing the command; the simulation only validates what it
## owns (prices, free slots, cooldowns). See docs/MULTIPLAYER.md.

## A command was executed (`ok` false: refused, nothing changed). UI listens.
signal applied(cmd: GameCommand, ok: bool)

var sim: Sim = null
var game_state: GameState = null
var build_manager: BuildManager = null
var hero: Hero = null
## Co-op: the heroes by player slot (0 host, 1 guest); empty in single player.
var heroes: Array[Hero] = []
## Co-op: commands go through the session and run after the input delay (apply_coop).
var coop: CoopSession = null
var local_player: int = 0
var villagers: Villagers = null
## Tower slots by id (their index in the level's "slots").
var slots: Array[TowerSlot] = []
var journal := CommandLog.new()
## Validate hero commands (co-op: both clients reject the same ones). Off in
## single player, where the player cannot cheat against anyone.
var validate_hero: bool = false
## A hero may cover this many times his walking speed between two commands (dashes,
## physics slides, x2 speed jitter) plus a constant slack.
var speed_tolerance_percent: int = 150
var slack_mm: int = 1000

var _bounds_mm: Rect2i = Rect2i()
## player -> [x mm, z mm, tick] of the last accepted hero command.
var _last_hero: Dictionary = {}
var _start_mm: Vector2i = Vector2i.ZERO


## Live command from the player. Returns true if it changed something.
func submit(cmd: GameCommand) -> bool:
	if sim.is_replaying():
		return false
	if coop != null:
		# Pause and speed are not shared (see docs/MULTIPLAYER.md, co-op); everything
		# else is queued and executes at tick + delay on BOTH sides, also on ours.
		return cmd.wire_name() != "" and coop.submit(cmd.wire_name(), cmd.args)
	if sim.is_in_step():
		push_warning("GameCommands: command issued inside a simulation step")
	cmd.tick = sim.tick
	var ok: bool = apply(cmd)
	if ok:
		journal.add(cmd)
	return ok


## Co-op: executes what the lockstep delivers for the current tick (both players'
## commands, in the same order everywhere). `ok` false: refused, same on both sides.
func apply_coop(wire: String, wire_args: Array, slot: int) -> bool:
	var cmd: GameCommand = GameCommand.from_wire(wire, wire_args, slot, sim.tick)
	if cmd == null:
		return false
	var ok: bool = apply(cmd)
	if ok:
		journal.add(cmd)
	return ok


## Executes a command now (live, or from a replay journal).
func apply(cmd: GameCommand) -> bool:
	var ok: bool = false
	match cmd.type:
		GameCommand.Type.BUILD:
			var slot: TowerSlot = _slot(cmd.args[0])
			var index: int = cmd.args[1]
			ok = (
				slot != null
				and index >= 0
				and index < build_manager.tower_types.size()
				and build_manager.build_on(slot, build_manager.tower_types[index])
			)
		GameCommand.Type.UPGRADE:
			var slot: TowerSlot = _slot(cmd.args[0])
			ok = slot != null and slot.tower != null and build_manager.upgrade(slot)
		GameCommand.Type.SELL:
			ok = build_manager.sell(_slot(cmd.args[0]))
		GameCommand.Type.SWORD:
			var smith: Hero = _hero_of(cmd.player)
			if game_state.spend(smith.sword_upgrade_cost()):
				smith.upgrade_sword()
				ok = true
		GameCommand.Type.REPAIR:
			ok = game_state.repair()
		GameCommand.Type.TRADE:
			ok = villagers.sell(cmd.args[0]) > 0
		GameCommand.Type.HERO_ATTACK:
			var origin: Vector3 = GameCommand.point_from_mm(cmd.args[0], cmd.args[1])
			var striker: Hero = _hero_of(cmd.player)
			ok = _hero_position_ok(cmd) and striker.apply_attack(origin, cmd.args[2] / 1000.0)
			if ok:
				striker.ghost_goto(origin)
		GameCommand.Type.HERO_SPIN:
			var spot: Vector3 = GameCommand.point_from_mm(cmd.args[0], cmd.args[1])
			var whirler: Hero = _hero_of(cmd.player)
			ok = _hero_position_ok(cmd) and whirler.apply_spin(spot)
			if ok:
				whirler.ghost_goto(spot)
		GameCommand.Type.SET_PAUSE:
			if coop != null:
				return false  # never shared in co-op
			sim.set_paused(cmd.args[0] != 0)
			ok = true
		GameCommand.Type.SET_SPEED:
			if coop != null:
				return false
			sim.set_speed(cmd.args[0])
			ok = true
	applied.emit(cmd, ok)
	return ok


## Where the hero starts and the map rectangle (metres): the reference for validation.
func set_hero_limits(start: Vector3, map: Rect2) -> void:
	_start_mm = Vector2i(GameCommand.to_mm(start.x), GameCommand.to_mm(start.z))
	_bounds_mm = Rect2i(
		GameCommand.to_mm(map.position.x) - slack_mm,
		GameCommand.to_mm(map.position.y) - slack_mm,
		GameCommand.to_mm(map.size.x) + 2 * slack_mm,
		GameCommand.to_mm(map.size.y) + 2 * slack_mm
	)


## Integer-only check of a hero command's position (x, z in mm): inside the map and
## reachable at hero speed since the player's previous accepted hero command.
## Uses only journal data, so every client decides the same.
@warning_ignore("integer_division")
func _hero_position_ok(cmd: GameCommand) -> bool:
	if not validate_hero:
		return true
	var x: int = cmd.args[0]
	var z: int = cmd.args[1]
	if not _bounds_mm.has_point(Vector2i(x, z)):
		return false
	var last: Array = _last_hero.get(cmd.player, [_start_mm.x, _start_mm.y, 0])
	var elapsed: int = maxi(cmd.tick - int(last[2]), 0)
	var walk_mm: int = roundi(_hero_of(cmd.player).speed * 1000.0) * elapsed * speed_tolerance_percent
	var allowed: int = walk_mm / (100 * Sim.TICK_RATE) + slack_mm
	var dx: int = x - int(last[0])
	var dz: int = z - int(last[1])
	if dx * dx + dz * dz > allowed * allowed:
		return false
	_last_hero[cmd.player] = [x, z, cmd.tick]
	return true


func _hero_of(player: int) -> Hero:
	return heroes[player] if player >= 0 and player < heroes.size() else hero


func _slot(id: int) -> TowerSlot:
	return slots[id] if id >= 0 and id < slots.size() else null
