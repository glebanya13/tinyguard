# gdlint:disable=max-returns
class_name CoopLobby
extends RefCounted
## Co-op rooms over a CoopTransport (docs/MULTIPLAYER.md 5.3). A room is made by
## a host and joined by ONE guest with a 5-character code; there is no public
## room list (no searching = no reads, no connections). Data:
##
##   rooms/{code}/meta            {host, level, seed, simv, delay, rev, state, created,
##                                 expiresAt, pv}
##   rooms/{code}/players/host    {uid, name, ready}
##   rooms/{code}/players/guest   {uid, name, ready}   created only if absent
##   rooms/{code}/net/{role}/{seq}  lockstep messages (CoopSession)
##   user_rooms/{uid}             "CODE": the room this user hosts or joined
##
## `ready` is the settings revision (meta.rev) the player accepted, 0 = not
## ready: when the host changes the level, rev grows and everybody is "not
## ready" again without any race. The host starts when both equal rev.
## Room life: a guest may join only within ROOM_TTL_MS of creation and only in
## state "lobby" (database.rules.json enforces both); the host removes the room
## on leaving, an own forgotten room is removed on the next create(), and an
## idle host room closes after LOBBY_IDLE seconds. Nothing is ever logged.

## The room as seen by this player changed: see snapshot().
signal room_changed
## The match starts: {"code", "role", "level", "seed", "delay", "simv"}.
signal started(config: Dictionary)
## The room is gone for this player: "host_left" (the room was deleted), "guest_left"
## (a guest removed by the host), "timeout" (nobody joined), "closed", "denied".
signal closed(reason: String)

const CODE_LENGTH := 5
## No O/0 and I/1: 24 letters + digits 2-9 = 32 symbols.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ROOM_TTL_MS := 7200000
const LOBBY_IDLE := 600.0
const NAME_MAX := 16
const LEVEL_MAX := 50
const MAX_CREATE_ATTEMPTS := 5

var transport: CoopTransport = null
var code: String = ""
var role: String = ""  # "host" | "guest" | "" (not in a room)
## Wall clock in ms (injectable for tests).
var clock_ms: Callable = func() -> float: return Time.get_unix_time_from_system() * 1000.0
var rng := RandomNumberGenerator.new()

var _tree := RtdbTree.new()
var _had_room: bool = false
var _idle: float = 0.0
var _begun: bool = false


func _init(net: CoopTransport) -> void:
	transport = net
	rng.randomize()


## A random room code.
func make_code() -> String:
	var out := ""
	for i in CODE_LENGTH:
		out += CODE_ALPHABET[rng.randi_range(0, CODE_ALPHABET.length() - 1)]
	return out


## Upper-cases and strips spaces and dashes; "" if it is not a valid code.
static func normalize_code(raw: String) -> String:
	var text: String = raw.to_upper().replace(" ", "").replace("-", "")
	if text.length() != CODE_LENGTH:
		return ""
	for i in text.length():
		if not CODE_ALPHABET.contains(text[i]):
			return ""
	return text


## Creates a room and becomes its host.
## {"ok", "code", "reason"}: reason = offline | denied | busy (no free code) | invalid.
func create(
	level: int, nickname: String, simv: int, delay: int = CoopProtocol.DEFAULT_DELAY
) -> Dictionary:
	if role != "":
		return {"ok": false, "code": "", "reason": "busy"}
	if level < 1 or level > LEVEL_MAX or not transport.is_ready():
		return {"ok": false, "code": "", "reason": "invalid" if transport.is_ready() else "offline"}
	var me: String = transport.uid()
	var cleaned: Dictionary = await purge_user()  # one room per user: drop a forgotten one
	if not cleaned["ok"]:
		return _fail(cleaned)
	var meta := {
		"host": me,
		"level": level,
		"seed": rng.randi_range(1, 2147483646),
		"simv": simv,
		"delay": clampi(delay, CoopProtocol.MIN_DELAY, CoopProtocol.MAX_DELAY),
		"rev": 1,
		"state": "lobby",
		"created": CoopTransport.SERVER_TIME,
		"expiresAt": int(float(clock_ms.call()) + float(ROOM_TTL_MS)),
		"pv": CoopProtocol.VERSION,
	}
	for attempt in MAX_CREATE_ATTEMPTS:
		var candidate: String = make_code()
		var reply: Dictionary = await transport.write("rooms/%s/meta" % candidate, meta, true)
		if reply["code"] == 412:
			continue  # the code is taken
		if not reply["ok"]:
			return _fail(reply)
		var rest: Dictionary = await (
			transport
			. update(
				{
					"rooms/%s/players/host" % candidate:
					{"uid": me, "name": _clean(nickname), "ready": 1},
					"user_rooms/" + me: candidate,
				}
			)
		)
		if not rest["ok"]:
			await transport.write("rooms/%s/meta" % candidate, null)
			return _fail(rest)
		_enter(candidate, "host")
		return {"ok": true, "code": candidate, "reason": ""}
	return {"ok": false, "code": "", "reason": "busy"}


## Joins the room with `raw_code` as the guest.
## {"ok", "reason"}: invalid | not_found | expired | started | full | version | offline | denied.
func join(raw_code: String, nickname: String, simv: int) -> Dictionary:
	if role != "":
		return {"ok": false, "reason": "busy"}
	var room: String = normalize_code(raw_code)
	if room == "":
		return {"ok": false, "reason": "invalid"}
	if not transport.is_ready():
		return {"ok": false, "reason": "offline"}
	var meta_reply: Dictionary = await transport.read("rooms/%s/meta" % room)
	if not meta_reply["ok"]:
		return {"ok": false, "reason": _reason(meta_reply)}
	var meta: Variant = meta_reply["value"]
	if not meta is Dictionary:
		return {"ok": false, "reason": "not_found"}
	if int(meta.get("pv", 0)) != CoopProtocol.VERSION or int(meta.get("simv", -1)) != simv:
		return {"ok": false, "reason": "version"}
	if str(meta.get("state", "")) != "lobby":
		return {"ok": false, "reason": "started"}
	if is_expired(meta):
		return {"ok": false, "reason": "expired"}
	var me: String = transport.uid()
	if str(meta.get("host", "")) == me:
		return {"ok": false, "reason": "own_room"}
	var cleaned: Dictionary = await purge_user()
	if not cleaned["ok"]:
		return {"ok": false, "reason": _reason(cleaned)}
	var reply: Dictionary = await transport.write(
		"rooms/%s/players/guest" % room, {"uid": me, "name": _clean(nickname), "ready": 0}, true
	)
	if reply["code"] == 412:
		return {"ok": false, "reason": "full"}
	if not reply["ok"]:
		return {"ok": false, "reason": _reason(reply)}
	await transport.write("user_rooms/" + me, room)
	_enter(room, "guest")
	return {"ok": true, "reason": ""}


## True when the room is older than the join window (client-side hint; the
## database rules decide).
func is_expired(meta: Dictionary) -> bool:
	var expires: float = float(meta.get("expiresAt", 0))
	return expires <= 0.0 or float(clock_ms.call()) > expires


## Current room as {"code", "role", "meta", "host", "guest", "level", "rev",
## "state", "me_ready", "partner_ready", "can_start"}; {} outside a room.
func snapshot() -> Dictionary:
	if role == "":
		return {}
	var meta: Dictionary = _dict(_tree.get_at("meta"))
	var host: Dictionary = _dict(_tree.get_at("players/host"))
	var guest: Dictionary = _dict(_tree.get_at("players/guest"))
	var rev: int = int(meta.get("rev", 1))
	var me: Dictionary = host if role == "host" else guest
	var other: Dictionary = guest if role == "host" else host
	var me_ready: bool = not me.is_empty() and int(me.get("ready", 0)) == rev
	var other_ready: bool = not other.is_empty() and int(other.get("ready", 0)) == rev
	return {
		"code": code,
		"role": role,
		"meta": meta,
		"host": host,
		"guest": guest,
		"level": int(meta.get("level", 1)),
		"rev": rev,
		"state": str(meta.get("state", "")),
		"me_ready": me_ready,
		"partner_ready": other_ready,
		"can_start": role == "host" and me_ready and other_ready and not guest.is_empty(),
	}


## Marks this player ready (accepts the current settings) or not.
func set_ready(ready: bool) -> Dictionary:
	if role == "" or str(snapshot().get("state", "")) != "lobby":
		return {"ok": false, "reason": "no_room"}
	var rev: int = int(snapshot().get("rev", 1))
	return await transport.write("rooms/%s/players/%s/ready" % [code, role], rev if ready else 0)


## Host only: another level. Bumps the revision, so the guest must accept again.
func set_level(level: int) -> Dictionary:
	if role != "host" or level < 1 or level > LEVEL_MAX:
		return {"ok": false, "reason": "invalid"}
	var rev: int = int(snapshot().get("rev", 1)) + 1
	return await (
		transport
		. update(
			{
				"rooms/%s/meta/level" % code: level,
				"rooms/%s/meta/rev" % code: rev,
				"rooms/%s/players/host/ready" % code: rev,
			}
		)
	)


## Host only, both ready: the match begins (everyone gets `started`).
func start_match() -> Dictionary:
	if not bool(snapshot().get("can_start", false)):
		return {"ok": false, "reason": "not_ready"}
	return await transport.write("rooms/%s/meta/state" % code, "playing")


## Frame update: closes a host room nobody joined for LOBBY_IDLE seconds.
func process(delta: float) -> void:
	if role != "host" or _begun:
		return
	if _dict(_tree.get_at("players/guest")).is_empty():
		_idle += delta
		if _idle >= LOBBY_IDLE:
			closed.emit("timeout")
			leave()
	else:
		_idle = 0.0


## Removes whatever this user still has in rooms: the room it hosts (all of it) or
## its guest entry elsewhere, and the user_rooms index. Used before create/join
## (one room per user) and by account deletion (no Cloud Functions: the client
## cleans up). {"ok", "code", "network"}; ok when there was nothing too.
func purge_user() -> Dictionary:
	var me: String = transport.uid()
	if me == "":
		return {"ok": true, "code": 0, "network": false}
	var index: Dictionary = await transport.read("user_rooms/" + me)
	if not index["ok"]:
		return index
	if not index["value"] is String:
		return {"ok": true, "code": 200, "network": false}
	var room: String = str(index["value"])
	var meta: Dictionary = await transport.read("rooms/%s/meta" % room)
	if not meta["ok"]:
		return meta
	if meta["value"] is Dictionary and str(meta["value"].get("host", "")) == me:
		return await _remove_room(room, true)
	return await (
		transport
		. update(
			{
				"rooms/%s/players/guest" % room: null,
				"rooms/%s/net/guest" % room: null,
				"user_rooms/" + me: null,
			}
		)
	)


## Leaves: the host removes the whole room, the guest only its own entries.
func leave() -> void:
	if role == "":
		return
	var room: String = code
	var was_host: bool = role == "host"
	_reset()
	transport.stop_listen()
	if was_host:
		await _remove_room(room, true)
	else:
		await (
			transport
			. update(
				{
					"rooms/%s/players/guest" % room: null,
					"rooms/%s/net/guest" % room: null,
					"user_rooms/" + transport.uid(): null,
				}
			)
		)


func _enter(room: String, as_role: String) -> void:
	code = room
	role = as_role
	_tree = RtdbTree.new()
	_had_room = false
	_idle = 0.0
	_begun = false
	transport.stream_event.connect(_on_stream_event)
	transport.stream_error.connect(_on_stream_error)
	transport.listen("rooms/" + room)


func _detach() -> void:
	if transport.stream_event.is_connected(_on_stream_event):
		transport.stream_event.disconnect(_on_stream_event)
		transport.stream_error.disconnect(_on_stream_error)


func _reset() -> void:
	_detach()
	code = ""
	role = ""
	_had_room = false


func _on_stream_event(kind: String, path: String, data: Variant) -> void:
	if role == "" or not _tree.apply(kind, path, data):
		return
	var info: Dictionary = snapshot()
	if _tree.value == null:
		if _had_room:
			_gone("host_left" if role == "guest" else "closed")
		return
	_had_room = true
	if role == "guest" and info["guest"].is_empty() and not info["host"].is_empty():
		_gone("guest_left")  # removed by the host
		return
	room_changed.emit()
	if info["state"] == "playing" and not _begun:
		_begun = true
		_detach()  # the match stream (CoopSession) takes over the transport
		var meta: Dictionary = info["meta"]
		(
			started
			. emit(
				{
					"code": code,
					"role": role,
					"level": int(meta.get("level", 1)),
					"seed": int(meta.get("seed", 0)),
					"delay": int(meta.get("delay", CoopProtocol.DEFAULT_DELAY)),
					"simv": int(meta.get("simv", 0)),
				}
			)
		)


func _on_stream_error(reason: String) -> void:
	if role != "" and (reason == "permission_denied" or reason == "auth"):
		_gone("denied")


func _gone(reason: String) -> void:
	_reset()
	transport.stop_listen()
	closed.emit(reason)


## Deletes a room's data (host only, rules allow it); also this user's index.
func _remove_room(room: String, include_index: bool) -> Dictionary:
	var changes := {
		"rooms/%s/net/host" % room: null,
		"rooms/%s/net/guest" % room: null,
		"rooms/%s/players/guest" % room: null,
		"rooms/%s/players/host" % room: null,
		"rooms/%s/meta" % room: null,
	}
	if include_index:
		changes["user_rooms/" + transport.uid()] = null
	return await transport.update(changes)


func _fail(reply: Dictionary) -> Dictionary:
	return {"ok": false, "code": "", "reason": _reason(reply)}


func _reason(reply: Dictionary) -> String:
	if reply.get("network", false) or int(reply.get("code", 0)) == 0:
		return "offline"
	return "denied"


func _clean(raw: String) -> String:
	var text: String = raw.strip_edges().replace("\n", " ").replace("\t", " ")
	return text.substr(0, NAME_MAX)


func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
