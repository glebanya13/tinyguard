class_name CoopLockstep
extends RefCounted
## Lockstep core for two players, independent of any transport and of the game
## (docs/MULTIPLAYER.md 5.4). The simulation owner drives it every frame:
##
##   if lockstep.can_simulate():
##       if lockstep.wants_hash(): lockstep.report_hash(state_hash())
##       for cmd in lockstep.take_commands(): apply(cmd)   # same order on both sides
##       simulate_one_tick()
##       lockstep.advance()
##
## Rules:
## - A command issued at tick T executes at tick T + delay on BOTH sides, also
##   on the issuer's (never earlier): that is the input delay.
## - Every message carries the sender's frontier = its tick + delay - 1: "no
##   more commands with execution tick <= frontier". Tick T may be simulated
##   when the partner's frontier >= T, so it cannot be missing a command.
## - Commands of one tick run ordered by (player slot, issue order).
## - Every HASH_INTERVAL ticks both sides report a hash of their state; a
##   mismatch freezes the match and raises `desync_detected`.

## The hashes at a checkpoint tick differ: the simulations diverged.
signal desync_detected(tick: int, local_hash: int, remote_hash: int)
## The partner broke the protocol (a command from the past, a bad message).
signal protocol_error(reason: String)

const HASH_KEEP := 8

## 0 = host, 1 = guest.
var local_slot: int = 0
var delay: int = CoopProtocol.DEFAULT_DELAY
## The next tick to simulate.
var tick: int = 0
var remote_frontier: int = 0
var partner_left: bool = false
var desynced: bool = false
## Checkpoint tick of the first mismatch (-1: none).
var desync_tick: int = -1

var _schedule: Dictionary = {}  # exec tick -> Array of {"player","n","type","args"}
var _outbox: Array[Dictionary] = []
var _issued: int = 0
var _remote_issued: int = 0
var _sent_frontier: int = -1
var _local_hashes: Dictionary = {}
var _remote_hashes: Dictionary = {}
var _hash_to_send: Array = []
var _hash_reported_for: int = -1
var _leaving: bool = false
var _leave_sent: bool = false


func _init(slot: int = 0, input_delay: int = CoopProtocol.DEFAULT_DELAY) -> void:
	local_slot = slot
	delay = clampi(input_delay, CoopProtocol.MIN_DELAY, CoopProtocol.MAX_DELAY)
	remote_frontier = delay - 1  # nobody can have issued anything before tick `delay`


## The frontier this side promises right now.
func local_frontier() -> int:
	return tick + delay - 1


## True when tick `tick` has all its commands and may be simulated.
func can_simulate() -> bool:
	return not desynced and remote_frontier >= tick


## Issues a local command; it executes at tick + delay. False if malformed.
func submit(type: String, args: Array = []) -> bool:
	if not CoopProtocol.is_valid_command(tick + delay, type, args):
		return false
	_issued += 1
	var exec_tick: int = tick + delay
	_add(exec_tick, local_slot, _issued, type, args)
	_outbox.append({"tick": exec_tick, "type": type, "args": args})
	return true


## Commands to apply before simulating the current tick (and forgets them).
func take_commands() -> Array:
	var list: Array = _schedule.get(tick, [])
	_schedule.erase(tick)
	list.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["player"] != b["player"]:
				return a["player"] < b["player"]
			return a["n"] < b["n"]
	)
	return list


## True when a state hash for this tick must be given via report_hash().
func wants_hash() -> bool:
	return tick > 0 and tick % CoopProtocol.HASH_INTERVAL == 0 and _hash_reported_for != tick


## `value`: any int hash of the state before simulating the current tick.
func report_hash(value: int) -> void:
	_hash_reported_for = tick
	_local_hashes[tick] = value
	_hash_to_send = [tick, value]
	_compare(tick)
	_trim_hashes()


func advance() -> void:
	tick += 1


## Marks this side as leaving: the next message carries the farewell.
func leave() -> void:
	_leaving = true


## Next message to send, or {} when there is nothing worth sending: pending
## commands, a hash, the farewell, or a frontier that moved HEARTBEAT_TICKS
## (or `force`). Large outboxes are split over several calls.
## Returns {"f", "d"} ready for CoopProtocol.encode_message's output shape.
func build_message(force: bool = false) -> Dictionary:
	var frontier: int = local_frontier()
	var heartbeat: bool = frontier - _sent_frontier >= CoopProtocol.HEARTBEAT_TICKS
	var farewell: bool = _leaving and not _leave_sent
	if _outbox.is_empty() and _hash_to_send.is_empty() and not farewell:
		if not heartbeat and not (force and frontier > _sent_frontier):
			return {}
	var batch: Array = _outbox.slice(0, CoopProtocol.MAX_COMMANDS_PER_MESSAGE)
	_outbox = _outbox.slice(batch.size())
	var hash_entry: Array = _hash_to_send
	_hash_to_send = []
	var last: bool = _outbox.is_empty()
	if farewell and last:
		_leave_sent = true
	if not last:
		# Commands still waiting must not be covered by this message's promise.
		frontier = maxi(_sent_frontier, mini(frontier, int(_outbox[0]["tick"]) - 1))
	_sent_frontier = maxi(_sent_frontier, frontier)
	return CoopProtocol.encode_message(frontier, batch, hash_entry, farewell and last)


## True while commands, a hash or a farewell wait to be sent.
func has_pending() -> bool:
	return not _outbox.is_empty() or not _hash_to_send.is_empty() or (_leaving and not _leave_sent)


## Takes one decoded partner message (CoopProtocol.decode_message). False if it
## was refused (then `protocol_error` is emitted and the match should end).
func receive(msg: Dictionary) -> bool:
	if not msg.get("ok", false):
		protocol_error.emit(str(msg.get("error", "bad_message")))
		return false
	var frontier: int = msg["frontier"]
	if frontier < remote_frontier:
		protocol_error.emit("frontier_went_back")
		return false
	var partner: int = 1 - local_slot
	for cmd in msg["commands"]:
		var exec_tick: int = cmd["tick"]
		# A command at or below the partner's earlier promise would change a tick
		# that may already have been simulated.
		if exec_tick <= remote_frontier or exec_tick < tick:
			protocol_error.emit("late_command")
			return false
	for cmd in msg["commands"]:
		_remote_issued += 1
		_add(int(cmd["tick"]), partner, _remote_issued, cmd["type"], cmd["args"])
	remote_frontier = frontier
	if (msg["hash"] as Array).size() == 2:
		var checkpoint: int = msg["hash"][0]
		_remote_hashes[checkpoint] = msg["hash"][1]
		_compare(checkpoint)
		_trim_hashes()
	if msg["leaving"]:
		partner_left = true
	return true


func _add(exec_tick: int, player: int, n: int, type: String, args: Array) -> void:
	if not _schedule.has(exec_tick):
		_schedule[exec_tick] = []
	(_schedule[exec_tick] as Array).append({"player": player, "n": n, "type": type, "args": args})


func _compare(checkpoint: int) -> void:
	if desynced or not _local_hashes.has(checkpoint) or not _remote_hashes.has(checkpoint):
		return
	var mine: int = _local_hashes[checkpoint]
	var theirs: int = _remote_hashes[checkpoint]
	if mine != theirs:
		desynced = true
		desync_tick = checkpoint
		desync_detected.emit(checkpoint, mine, theirs)


func _trim_hashes() -> void:
	for store in [_local_hashes, _remote_hashes]:
		while (store as Dictionary).size() > HASH_KEEP:
			var oldest: int = (store as Dictionary).keys().min()
			(store as Dictionary).erase(oldest)
