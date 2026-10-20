class_name CoopProtocol
extends RefCounted
## Wire format and constants of the co-op lockstep (docs/MULTIPLAYER.md, 5.3-5.4).
##
## A match is a stream of messages per player at rooms/{code}/net/{role}/{seq}:
##   {"s": seq, "f": frontier, "d": "<json>"}   key = "%06d" of seq, written once, gap-free
## ("s" is checked by the database rules: a message needs its predecessor)
## "f" (frontier): the sender promises that no command with an execution tick
## <= f will come in this or any later message. "d" is "" or JSON
##   {"c": [[tick, "type", [args...]], ...], "h": [checkpoint_tick, hash], "x": 1}
## c = commands (execution tick, type, args), h = state hash at a checkpoint,
## x = the sender is leaving. Everything is integers, strings and booleans: no
## floats, so both sides decode exactly the same values.

const VERSION := 1
## Simulation ticks per second (fixed step of the lockstep simulation).
const TICK_RATE := 30
## Ticks between a command being issued and executed: covers the REST round trip.
const DEFAULT_DELAY := 15
const MIN_DELAY := 6
const MAX_DELAY := 60
## A message with the frontier alone is sent when it advanced this many ticks.
const HEARTBEAT_TICKS := 8
## State hash exchange every N ticks (2 s).
const HASH_INTERVAL := 60
const MAX_COMMANDS_PER_MESSAGE := 16
const MAX_ARGS := 8
const MAX_ARG_STRING := 24
## rooms/*/net/*/* ".validate" in database.rules.json uses the same limit.
const MAX_DATA_CHARS := 900
## Messages one player may send in a room (database.rules.json).
const MAX_SEQ := 40000
## Command types (docs/MULTIPLAYER.md 5.1). The gameplay stage adds its own
## argument checks; here only the shape is verified.
const COMMAND_TYPES: Array[String] = [
	"build",
	"upgrade",
	"sell",
	"sword",
	"repair",
	"trade",
	"move_to",
	"joystick",
	"attack",
	"spin",
	"priority",
	"buy_wood",
	"hire",
	"castle",
	"speed",
	"pause",
]


static func seq_key(seq: int) -> String:
	return "%06d" % seq


## Parses "000012" -> 12; -1 if it is not a message key.
static func parse_seq(key: String) -> int:
	if key.length() != 6 or not key.is_valid_int():
		return -1
	var value: int = int(key)
	return value if value >= 1 else -1


## True for a well-formed command: a known type, a non-negative tick and a short
## list of ints, bools and short strings.
static func is_valid_command(tick: Variant, type: Variant, args: Variant) -> bool:
	if not (tick is int or tick is float) or not _is_whole(tick) or int(tick) < 0:
		return false
	if not type is String or not COMMAND_TYPES.has(type):
		return false
	if not args is Array or (args as Array).size() > MAX_ARGS:
		return false
	for arg in args:
		if arg is String:
			if (arg as String).length() > MAX_ARG_STRING:
				return false
		elif not (arg is bool or arg is int or (arg is float and _is_whole(arg))):
			return false
	return true


## Builds the message dictionary for rooms/.../net/{role}/{seq}.
## `commands`: [{"tick", "type", "args"}]; `hash`: [] or [tick, value].
static func encode_message(
	frontier: int, commands: Array, hash_entry: Array = [], leaving: bool = false
) -> Dictionary:
	var body: Dictionary = {}
	if not commands.is_empty():
		var list: Array = []
		for cmd in commands:
			list.append([int(cmd["tick"]), str(cmd["type"]), cmd["args"]])
		body["c"] = list
	if hash_entry.size() == 2:
		body["h"] = [int(hash_entry[0]), int(hash_entry[1])]
	if leaving:
		body["x"] = 1
	return {"f": frontier, "d": JSON.stringify(body) if not body.is_empty() else ""}


## Decodes and validates one message from the partner.
## {"ok", "error", "frontier", "commands": [{"tick","type","args"}], "hash": [] | [t, v],
## "leaving"}. Never trusts the sender: anything off makes ok = false.
static func decode_message(raw: Variant) -> Dictionary:
	var bad := {
		"ok": false,
		"error": "bad_message",
		"frontier": 0,
		"commands": [],
		"hash": [],
		"leaving": false
	}
	if not raw is Dictionary:
		return bad
	var msg: Dictionary = raw
	var frontier: Variant = msg.get("f")
	var data: Variant = msg.get("d", "")
	if not (frontier is int or frontier is float) or not _is_whole(frontier) or int(frontier) < 0:
		return bad
	if not data is String or (data as String).length() > MAX_DATA_CHARS:
		return bad
	var out := {
		"ok": true,
		"error": "",
		"frontier": int(frontier),
		"commands": [],
		"hash": [],
		"leaving": false,
	}
	if data == "":
		return out
	var body: Variant = _parse(data)
	if not body is Dictionary:
		return bad
	var cmds: Variant = (body as Dictionary).get("c", [])
	if not cmds is Array or (cmds as Array).size() > MAX_COMMANDS_PER_MESSAGE:
		return bad
	var last_tick: int = -1
	for entry in cmds:
		if not entry is Array or (entry as Array).size() != 3:
			return bad
		if not is_valid_command(entry[0], entry[1], entry[2]):
			return bad
		var args: Array = []
		for arg in entry[2]:
			args.append(int(arg) if arg is float else arg)
		var tick: int = int(entry[0])
		if tick < last_tick:
			return bad  # commands of one message are in tick order
		last_tick = tick
		out["commands"].append({"tick": tick, "type": entry[1], "args": args})
	var hash_entry: Variant = (body as Dictionary).get("h", [])
	if hash_entry is Array and (hash_entry as Array).size() == 2:
		if _is_whole(hash_entry[0]) and _is_whole(hash_entry[1]):
			out["hash"] = [int(hash_entry[0]), int(hash_entry[1])]
		else:
			return bad
	elif not (hash_entry is Array and (hash_entry as Array).is_empty()):
		return bad
	out["leaving"] = (body as Dictionary).get("x", 0) == 1
	return out


static func _is_whole(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_equal_approx(floorf(value), value) and absf(value) < 9.0e15


static func _parse(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data
