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
var villagers: Villagers = null
## Tower slots by id (their index in the level's "slots").
var slots: Array[TowerSlot] = []
var journal := CommandLog.new()


## Live command from the player. Returns true if it changed something.
func submit(cmd: GameCommand) -> bool:
	if sim.is_replaying():
		return false
	if sim.is_in_step():
		push_warning("GameCommands: command issued inside a simulation step")
	cmd.tick = sim.tick
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
			if game_state.spend(hero.sword_upgrade_cost()):
				hero.upgrade_sword()
				ok = true
		GameCommand.Type.REPAIR:
			ok = game_state.repair()
		GameCommand.Type.TRADE:
			ok = villagers.sell(cmd.args[0]) > 0
		GameCommand.Type.HERO_ATTACK:
			var origin: Vector3 = GameCommand.point_from_mm(cmd.args[0], cmd.args[1])
			ok = hero.apply_attack(origin, cmd.args[2] / 1000.0)
		GameCommand.Type.HERO_SPIN:
			ok = hero.apply_spin(GameCommand.point_from_mm(cmd.args[0], cmd.args[1]))
		GameCommand.Type.SET_PAUSE:
			sim.set_paused(cmd.args[0] != 0)
			ok = true
		GameCommand.Type.SET_SPEED:
			sim.set_speed(cmd.args[0])
			ok = true
	applied.emit(cmd, ok)
	return ok


func _slot(id: int) -> TowerSlot:
	return slots[id] if id >= 0 and id < slots.size() else null
