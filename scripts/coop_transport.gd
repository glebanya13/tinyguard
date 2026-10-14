class_name CoopTransport
extends Node
## Abstract transport of the co-op layer (docs/MULTIPLAYER.md, stage 2): a thin
## view of a Realtime Database. RtdbClient is the real one (REST + SSE);
## tests use tests/fake_rtdb.gd. Lobby, protocol and lockstep depend only on
## this interface, so they run without a network.
##
## Paths are database paths without a leading slash ("rooms/ABCDE/meta").
## Replies of read/write/update: {"ok": bool, "code": int (HTTP-like, 0 = no
## reply), "network": bool (no reply at all), "value": Variant (read only)}.
## A value of null deletes a node. SERVER_TIME is replaced by the server clock.

## One stream event. kind: "put" | "patch"; path is relative to the listened
## location ("/" = the whole location); data is the new value (put) or a
## Dictionary of child changes (patch).
signal stream_event(kind: String, path: String, data: Variant)
## "connecting", "open", "reconnecting" (lost, trying again), "closed" (stopped
## or refused for good: see stream_error).
signal stream_state(state: String)
## Why the stream was closed for good: "permission_denied", "auth", ...
signal stream_error(reason: String)
## A queued change was refused for good (permission, validation): the code.
signal write_failed(code: int)

const SERVER_TIME := {".sv": "timestamp"}


## The signed-in user id ("" when not signed in).
func uid() -> String:
	return ""


## True when requests can be attempted (configured and signed in).
func is_ready() -> bool:
	return false


func read(_path: String) -> Dictionary:
	return _unsupported()


## Replaces the node. With `if_absent` it succeeds only when the node does not
## exist (code 412 otherwise): the atomic "create" primitive.
func write(_path: String, _value: Variant, _if_absent: bool = false) -> Dictionary:
	return _unsupported()


## Multi-path update (one atomic request): {"rooms/ABCDE/meta": {...}, "user_rooms/u": null}.
func update(_changes: Dictionary) -> Dictionary:
	return _unsupported()


## Like update(), but batched: changes made within a short window go out as one
## request (saves quota), failures are retried. Later changes of the same
## path win. Returns nothing: watch `write_failed`.
func queue_update(_changes: Dictionary) -> void:
	pass


## Sends queued changes now; resolves when they are acknowledged.
func flush() -> Dictionary:
	return {"ok": true, "code": 200, "network": false, "value": null}


## Starts (or replaces) the single stream. `query` holds raw REST parameters,
## for example {"orderBy": "\"$key\"", "startAt": "\"000012\""}.
func listen(_path: String, _query: Dictionary = {}) -> void:
	pass


## Changes the query used at the next (re)connect without touching the live
## connection (the session moves `startAt` forward after every message).
func update_query(_query: Dictionary) -> void:
	pass


func stop_listen() -> void:
	pass


func _unsupported() -> Dictionary:
	return {"ok": false, "code": 0, "network": true, "value": null}
