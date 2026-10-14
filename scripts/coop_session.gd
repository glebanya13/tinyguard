class_name CoopSession
extends RefCounted
## One running co-op match over a CoopTransport: glue between CoopLockstep and
## the database (docs/MULTIPLAYER.md 5.3-5.4). Owns no timers: the game calls
## process(delta) every frame, so tests drive time by hand.
##
## Outgoing: lockstep messages go to rooms/{code}/net/{role}/{seq} through the
## transport's batching queue (about FLUSH_INTERVAL apart, only when there is
## something to say). Incoming: ONE stream on rooms/{code}/net/{partner_role}
## filtered with orderBy=$key&startAt=<next seq>, so a reconnect never replays
## the history (that would cost download quota). The stream's puts and patches
## go through RtdbTree and are consumed strictly in seq order.
## Silence from the partner: "waiting" after WAIT_AFTER seconds, "lost" (and the
## match ends) after DROP_AFTER.

## "ok", "waiting" (silent for WAIT_AFTER s) or "lost".
signal partner_state_changed(state: String)
## "partner_left", "lost", "desync", "protocol", "denied".
signal ended(reason: String)

const FLUSH_INTERVAL := 0.2
const WAIT_AFTER := 10.0
const DROP_AFTER := 30.0
## A stalled side repeats its frontier this often (a lost message must not deadlock).
const NUDGE_INTERVAL := 1.0
## Seconds a missing message may hold back later ones before the stream restarts.
const GAP_TIMEOUT := 5.0
const MAX_MESSAGES_PER_FLUSH := 4

var transport: CoopTransport = null
var code: String = ""
var role: String = "host"
var lockstep: CoopLockstep = null
var partner_state: String = "ok"
var finished: bool = false
var end_reason: String = ""

var _tree := RtdbTree.new()
var _send_seq: int = 1
var _next_seq: int = 1
var _flush_in: float = 0.0
var _silence: float = 0.0
var _stalled: float = 0.0
var _gap: float = 0.0


func _init(net: CoopTransport, room_code: String, local_role: String, input_delay: int) -> void:
	transport = net
	code = room_code
	role = local_role
	lockstep = CoopLockstep.new(0 if local_role == "host" else 1, input_delay)
	lockstep.desync_detected.connect(_on_desync)
	lockstep.protocol_error.connect(_on_protocol_error)


func partner_role() -> String:
	return "guest" if role == "host" else "host"


## Starts listening to the partner. Call once, when both sides are in the match.
func start() -> void:
	transport.stream_event.connect(_on_stream_event)
	transport.stream_error.connect(_on_stream_error)
	transport.listen(_net_path(partner_role()), _query())


## Issues a local command (executes after the input delay on both sides).
func submit(type: String, args: Array = []) -> bool:
	return not finished and lockstep.submit(type, args)


## Frame update; `delta` in seconds of real time.
func process(delta: float) -> void:
	if finished:
		return
	_flush_in -= delta
	if lockstep.can_simulate():
		_stalled = 0.0
	else:
		_stalled += delta
	if _flush_in <= 0.0:
		_flush_in = FLUSH_INTERVAL
		_send(_stalled >= NUDGE_INTERVAL)
		if _stalled >= NUDGE_INTERVAL:
			_stalled = 0.0
	if _tree.value is Dictionary:
		_gap += delta
		if _gap > GAP_TIMEOUT:
			_gap = 0.0
			_restart_stream()  # a message is missing: ask again from the first gap
	_silence += delta
	if _silence >= DROP_AFTER:
		_set_partner_state("lost")
		_end("lost")
	elif _silence >= WAIT_AFTER:
		_set_partner_state("waiting")


## Leaves the match: tells the partner and stops listening.
func finish() -> void:
	if finished:
		return
	lockstep.leave()
	_send(true)
	await transport.flush()
	_end("left")


func _send(force: bool) -> void:
	for i in MAX_MESSAGES_PER_FLUSH:
		var msg: Dictionary = lockstep.build_message(force)
		if msg.is_empty():
			return
		msg["s"] = _send_seq  # the rules check that seq numbers have no gaps
		transport.queue_update({_net_path(role) + "/" + CoopProtocol.seq_key(_send_seq): msg})
		_send_seq += 1
		force = false


func _on_stream_event(kind: String, path: String, data: Variant) -> void:
	if finished or not _tree.apply(kind, path, data):
		return
	_drain()


func _drain() -> void:
	while not finished:
		var raw: Variant = _tree.get_at(CoopProtocol.seq_key(_next_seq))
		if raw == null:
			break
		_tree.apply("put", CoopProtocol.seq_key(_next_seq), null)
		var claimed: Variant = raw.get("s") if raw is Dictionary else null
		if not (claimed is int or claimed is float) or int(claimed) != _next_seq:
			_end("protocol")
			return
		_next_seq += 1
		_gap = 0.0
		if not lockstep.receive(CoopProtocol.decode_message(raw)):
			return  # protocol_error ended the match
		_silence = 0.0
		_set_partner_state("ok")
		transport.update_query(_query())
		if lockstep.partner_left:
			_end("partner_left")
	# Keys below the expected one (a replay after a reconnect) are dropped.
	if _tree.value is Dictionary:
		for key in (_tree.value as Dictionary).keys():
			if CoopProtocol.parse_seq(str(key)) < _next_seq:
				_tree.apply("put", str(key), null)
	if not _tree.value is Dictionary:
		_gap = 0.0


func _restart_stream() -> void:
	_tree.clear()
	transport.listen(_net_path(partner_role()), _query())


func _on_desync(_tick: int, _mine: int, _theirs: int) -> void:
	_end("desync")


func _on_protocol_error(_reason: String) -> void:
	_end("protocol")


func _on_stream_error(reason: String) -> void:
	if reason == "permission_denied" or reason == "auth":
		_end("denied")


func _set_partner_state(state: String) -> void:
	if state != partner_state:
		partner_state = state
		partner_state_changed.emit(state)


func _end(reason: String) -> void:
	if finished:
		return
	if reason == "desync":
		# Tell the partner our hash, so it sees the divergence too.
		lockstep.leave()
		_send(true)
		transport.flush()
	finished = true
	end_reason = reason
	if transport.stream_event.is_connected(_on_stream_event):
		transport.stream_event.disconnect(_on_stream_event)
		transport.stream_error.disconnect(_on_stream_error)
	transport.stop_listen()
	ended.emit(reason)


func _net_path(which: String) -> String:
	return "rooms/%s/net/%s" % [code, which]


func _query() -> Dictionary:
	return {"orderBy": '"$key"', "startAt": '"%s"' % CoopProtocol.seq_key(_next_seq)}
