class_name GameCommand
extends RefCounted
## One player action that changes the battle: the only way input reaches the
## simulation. All arguments are integers (positions in millimetres, angles in
## milliradians) so a command serialises exactly and replays bit for bit.
## `tick` is the number of simulation steps completed when it was issued: it is
## applied before step number `tick`.

enum Type {
	BUILD,  ## args: slot id, tower type index
	UPGRADE,  ## args: slot id
	SELL,  ## args: slot id
	SWORD,  ## forge: sword upgrade, no args
	REPAIR,  ## forge: castle repair, no args
	TRADE,  ## args: lots of wood to sell to a villager
	HERO_ATTACK,  ## args: x mm, z mm, yaw mrad (the hero's position and facing)
	HERO_SPIN,  ## args: x mm, z mm
	SET_PAUSE,  ## args: 1 pause / 0 resume
	SET_SPEED,  ## args: 1 or 2
	SET_PRIORITY,  ## args: slot id, TowerData.Priority value
	## New types are only ever appended: journals store the numbers.
	TRADE_BUY,  ## args: lots of wood to buy from a villager (campaign and co-op only)
	HIRE,  ## args: villager index (spawn order): hire him as a lumberjack (same modes)
	UPGRADE_CASTLE,  ## no args: the next castle upgrade (lives and armor), every mode
}

## Co-op wire names (CoopProtocol.COMMAND_TYPES) and argument counts of the commands
## that travel between players. Pause and speed never do: see GameCommands.submit().
const WIRE_NAMES: Dictionary = {
	Type.BUILD: "build",
	Type.UPGRADE: "upgrade",
	Type.SELL: "sell",
	Type.SWORD: "sword",
	Type.REPAIR: "repair",
	Type.TRADE: "trade",
	Type.HERO_ATTACK: "attack",
	Type.HERO_SPIN: "spin",
	Type.SET_PRIORITY: "priority",
	Type.TRADE_BUY: "buy_wood",
	Type.HIRE: "hire",
	Type.UPGRADE_CASTLE: "castle",
}
const ARG_COUNTS: Dictionary = {
	Type.BUILD: 2,
	Type.UPGRADE: 1,
	Type.SELL: 1,
	Type.SWORD: 0,
	Type.REPAIR: 0,
	Type.TRADE: 1,
	Type.HERO_ATTACK: 3,
	Type.HERO_SPIN: 2,
	Type.SET_PRIORITY: 2,
	Type.TRADE_BUY: 1,
	Type.HIRE: 1,
	Type.UPGRADE_CASTLE: 0,
	Type.SET_PAUSE: 1,
	Type.SET_SPEED: 1,
}

var tick: int = 0
## Who issued it (0 in single player; in co-op the player slot: 0 host, 1 guest).
var player: int = 0
var type: Type = Type.BUILD
var args: Array[int] = []


static func make(command_type: Type, command_args: Array[int] = []) -> GameCommand:
	var cmd := GameCommand.new()
	cmd.type = command_type
	cmd.args = command_args
	return cmd


static func build(slot_id: int, tower_index: int) -> GameCommand:
	return make(Type.BUILD, [slot_id, tower_index])


static func upgrade(slot_id: int) -> GameCommand:
	return make(Type.UPGRADE, [slot_id])


static func sell(slot_id: int) -> GameCommand:
	return make(Type.SELL, [slot_id])


static func sword() -> GameCommand:
	return make(Type.SWORD)


static func repair() -> GameCommand:
	return make(Type.REPAIR)


static func trade(lots: int) -> GameCommand:
	return make(Type.TRADE, [lots])


static func trade_buy(lots: int) -> GameCommand:
	return make(Type.TRADE_BUY, [lots])


static func hire(villager_index: int) -> GameCommand:
	return make(Type.HIRE, [villager_index])


static func upgrade_castle() -> GameCommand:
	return make(Type.UPGRADE_CASTLE)


static func hero_attack(origin: Vector3, yaw: float) -> GameCommand:
	return make(Type.HERO_ATTACK, [to_mm(origin.x), to_mm(origin.z), to_mrad(yaw)])


static func hero_spin(origin: Vector3) -> GameCommand:
	return make(Type.HERO_SPIN, [to_mm(origin.x), to_mm(origin.z)])


static func set_pause(on: bool) -> GameCommand:
	return make(Type.SET_PAUSE, [1 if on else 0])


static func set_speed(speed: int) -> GameCommand:
	return make(Type.SET_SPEED, [speed])


static func set_priority(slot_id: int, priority: int) -> GameCommand:
	return make(Type.SET_PRIORITY, [slot_id, priority])


static func to_mm(metres: float) -> int:
	return roundi(metres * 1000.0)


static func to_mrad(radians: float) -> int:
	return roundi(radians * 1000.0)


## Ground point from two millimetre arguments.
static func point_from_mm(x_mm: int, z_mm: int) -> Vector3:
	return Vector3(x_mm / 1000.0, 0.0, z_mm / 1000.0)


## Name of the command in the co-op protocol ("" for commands that never travel).
func wire_name() -> String:
	return WIRE_NAMES.get(type, "")


## A command received from the partner. null when the name is unknown or the
## argument count is wrong (a partner must never be able to crash the game).
static func from_wire(wire: String, wire_args: Array, slot: int, at_tick: int) -> GameCommand:
	for key: int in WIRE_NAMES:
		if WIRE_NAMES[key] != wire:
			continue
		if wire_args.size() != int(ARG_COUNTS[key]):
			return null
		var cmd := GameCommand.new()
		cmd.type = key as Type
		cmd.player = slot
		cmd.tick = at_tick
		for value: Variant in wire_args:
			cmd.args.append(int(value))
		return cmd
	return null


func to_array() -> Array:
	var out: Array = [tick, player, int(type)]
	out.append_array(args)
	return out


static func from_array(data: Array) -> GameCommand:
	var cmd := GameCommand.new()
	cmd.tick = int(data[0])
	cmd.player = int(data[1])
	cmd.type = int(data[2]) as Type
	for i in range(3, data.size()):
		cmd.args.append(int(data[i]))
	return cmd
