class_name OnlineCoop
extends RefCounted
## Co-op side of Online: the Realtime Database transport (docs/MULTIPLAYER.md) and
## the removal of the player's rooms when the account is deleted.

var _ctx: OnlineContext


func _init(context: OnlineContext) -> void:
	_ctx = context


## (Re)creates the transport from database_url; null without a URL or a key.
func configure(key: String) -> void:
	if _ctx.rtdb != null:
		_ctx.rtdb.queue_free()
		_ctx.rtdb = null
	if _ctx.database_url != "" and key != "":
		_ctx.rtdb = RtdbClient.new()
		_ctx.host.add_child(_ctx.rtdb)
		if not _ctx.rtdb.configure(_ctx.database_url, _ctx.auth):
			_ctx.rtdb.queue_free()
			_ctx.rtdb = null


## Deletes the player's co-op rooms (uid, nickname, commands) while the rules still
## see the signed-in user. False when the rooms could not be removed; true without co-op.
func purge_rooms() -> bool:
	if _ctx.rtdb == null:
		return true
	var rooms: Dictionary = await CoopLobby.new(_ctx.rtdb).purge_user()
	return bool(rooms["ok"])
