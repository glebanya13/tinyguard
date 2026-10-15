class_name CoopRun
extends RefCounted
## Hand-over between the lobby screen and the battle scene: the scene change
## frees every node, so what the match needs travels in static variables.
## The lobby sets `config` and `lobby` when the match starts; the battle scene
## takes them in its _ready(). Nothing here is ever saved or logged.

## {"code", "role", "level", "seed", "delay", "simv", "name", "partner"} or {}.
static var config: Dictionary = {}
## The room object of this player (leaves the room when the match is over).
static var lobby: CoopLobby = null


static func is_pending() -> bool:
	return not config.is_empty()


## Hands the prepared match to the battle scene (once).
static func take() -> Dictionary:
	var out: Dictionary = config
	config = {}
	return out


static func clear() -> void:
	config = {}
	lobby = null


## Tells the partner, closes the stream and removes this player from the room.
static func leave_match(session: CoopSession, room: CoopLobby) -> void:
	if session != null:
		await session.finish()
	if room != null:
		await room.leave()
	clear()
