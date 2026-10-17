class_name OnlineSync
extends RefCounted
## Profile sync of Online: the read-merge-write against users/{uid} (never overwrites
## newer cloud progress), the sync state shown on the map, the automatic debounced
## sync after local progress changed, and the "to cloud / from cloud" buttons.

## Rounds of read-merge-write when another device writes in between.
const MAX_SYNC_ROUNDS := 3
## Pause after the last local change before the profile goes to the cloud (seconds).
const SYNC_DEBOUNCE := 3.0
## Minimum time between two automatic syncs (keeps a device far below Spark's 20k
## writes a day), and the longest wait after failed ones.
const SYNC_MIN_GAP := 10.0
const SYNC_RETRY_MAX := 300.0
const STATE_TEXT := {
	"off": "SYNC_OFF",
	"syncing": "SYNC_SYNCING",
	"synced": "SYNC_SYNCED",
	"pending": "SYNC_PENDING",
	"offline": "SYNC_OFFLINE",
	"session_lost": "SYNC_SESSION_LOST",
	"newer": "SYNC_NEWER",
	"disabled": "SYNC_DISABLED",
}

var _ctx: OnlineContext
var _auto_sync_waiting: bool = false
var _auto_failures: int = 0
var _last_auto_sync_msec: int = -1000000


func _init(context: OnlineContext) -> void:
	_ctx = context


static func state_text(state: String) -> String:
	return TranslationServer.translate(str(STATE_TEXT.get(state, "")))


## "off" (no Firebase), "syncing", "synced", "pending", "offline",
## "session_lost", "newer", "disabled".
func sync_state() -> String:
	if not _ctx.is_configured():
		return "off"
	if _ctx.sync_busy:
		return "syncing"
	if _ctx.last_error in ["session_lost", "newer", "disabled"]:
		return _ctx.last_error
	if _ctx.last_error in ["offline", "server"]:
		return "offline"  # also with nothing pending: the profile says it syncs later
	if not PlayerProfile.is_pending():
		return "synced"
	return "pending"


## Reads the cloud profile, merges it with the local one and writes the
## result back (never overwrites newer cloud progress: progression only grows,
## and the write is conditional on the document not changing in between).
## One sync at a time: concurrent callers get the running one's result.
## {"ok", "error", "changed" (local progress changed)}.
func sync_now() -> Dictionary:
	if not _ctx.is_configured():
		return {"ok": false, "error": "not_configured", "changed": false}
	if _ctx.switching:
		return {"ok": false, "error": "busy", "changed": false}
	if _ctx.sync_busy:
		return await _ctx.sync_finished
	_ctx.sync_busy = true
	_ctx.sync_state_changed.emit("syncing")
	var result: Dictionary = await _sync()
	_ctx.last_error = "" if result["ok"] else str(result["error"])
	_ctx.sync_busy = false
	_ctx.sync_state_changed.emit(sync_state())
	if _ctx.last_error == "session_lost" and not _ctx.expired_announced:
		_ctx.expired_announced = true
		_ctx.session_expired.emit()
	_ctx.sync_finished.emit(result)
	return result


## Syncs the profile now (the button "В облако").
func cloud_save() -> void:
	var result: Dictionary = await sync_now()
	_ctx.status_changed.emit(_ctx.host.tr("ONLINE_SAVED") if result["ok"] else _error_text(result))


## Merges the cloud profile into the local one (the button "Из облака");
## cloud_loaded(true) when local progress changed.
func cloud_load() -> void:
	var result: Dictionary = await sync_now()
	var changed: bool = result["ok"] and result["changed"]
	if result["ok"]:
		_ctx.status_changed.emit(
			_ctx.host.tr("ONLINE_UPDATED") if changed else _ctx.host.tr("ONLINE_SAME")
		)
	else:
		_ctx.status_changed.emit(_error_text(result))
	_ctx.cloud_loaded.emit(changed)


## The services were rewired (Online.setup): drop what belonged to the old session.
func reset() -> void:
	_auto_sync_waiting = false


## The account was wiped: the failure back-off starts over.
func forget_failures() -> void:
	_auto_failures = 0


## LevelCatalog wrote the save: if the synced part of the profile changed, send it to
## the cloud after a short pause (a burst of changes becomes one write).
func on_local_committed() -> void:
	if not _ctx.auto_sync or not _ctx.is_configured() or _ctx.switching or _ctx.sync_busy:
		return
	if _auto_sync_waiting or not _ctx.auth.has_session():
		return
	if PlayerProfile.is_pending():
		schedule_auto_sync(_ctx.sync_debounce)


func schedule_auto_sync(delay: float) -> void:
	if not _ctx.auto_sync or not _ctx.is_configured() or _auto_sync_waiting:
		return
	if not _ctx.host.is_inside_tree():
		return
	if not _ctx.auth.has_session() or not PlayerProfile.is_pending():
		return
	_auto_sync_waiting = true
	var since: float = float(Time.get_ticks_msec() - _last_auto_sync_msec) / 1000.0
	var wait: float = maxf(delay, _ctx.sync_min_gap - since)
	if _auto_failures > 0:
		wait = maxf(wait, minf(30.0 * pow(2.0, _auto_failures - 1), SYNC_RETRY_MAX))
	if wait > 0.0:
		await _ctx.host.get_tree().create_timer(wait).timeout
	_auto_sync_waiting = false
	if _ctx.switching or not PlayerProfile.is_pending():
		return
	_last_auto_sync_msec = Time.get_ticks_msec()
	var result: Dictionary = await sync_now()
	if result["ok"]:
		_auto_failures = 0
	elif str(result["error"]) in ["offline", "server"]:
		_auto_failures = mini(_auto_failures + 1, 5)
		schedule_auto_sync(0.0)  # waits with the growing back-off
	else:
		_auto_failures = 0


func _sync() -> Dictionary:
	var signed: Dictionary = await _ctx.auth.ensure_token(true)
	if not signed["ok"]:
		return {"ok": false, "error": signed["error"], "changed": false}
	_ctx.session.remember_uid()
	var local: Dictionary = PlayerProfile.touch_local()
	if signed["created"] and bool(local["nicknameVerified"]):
		# A new guest account replaced a dead one: reserve the name again.
		local["nicknameVerified"] = false
		PlayerProfile.save_local(local)
	if str(local["nickname"]) != "" and not bool(local["nicknameVerified"]):
		if not bool(local["nicknameConflict"]):
			var reserved: Dictionary = await _ctx.nicknames.reserve(str(local["nickname"]))
			if reserved["reason"] in ["taken", "invalid"]:
				Onboarding.flag_nickname_conflict()
				_ctx.status_changed.emit(_ctx.host.tr("ONLINE_NAME_TAKEN") % local["nickname"])
	var start_hash: String = PlayerProfile.content_hash(PlayerProfile.local())
	var result: Dictionary = {"ok": false, "error": "server", "changed": false}
	for round_index in MAX_SYNC_ROUNDS:
		result = await _sync_round(start_hash)
		if not result.get("retry", false):
			break
		# Precondition failed: someone wrote in between. Read and merge again.
	result.erase("retry")
	return result


## One read-merge-write round. "retry" is set when the conditional write lost a race.
func _sync_round(start_hash: String) -> Dictionary:
	var firestore: FirestoreClient = _ctx.firestore
	var got: Dictionary = await firestore.get_doc("users/" + _ctx.auth.uid)
	if not got["ok"] and not got["missing"]:
		return {"ok": false, "error": OnlineContext.reply_error(got), "changed": false}
	var cloud: Dictionary = {}
	var from_legacy := false
	var public_doc: Dictionary = await firestore.get_doc("publicProfiles/" + _ctx.auth.uid)
	if not public_doc["ok"] and not public_doc["missing"]:
		return {"ok": false, "error": OnlineContext.reply_error(public_doc), "changed": false}
	if got["ok"]:
		cloud = PlayerProfile.from_cloud(got["fields"])
	else:
		var legacy: Dictionary = await firestore.get_doc("saves/" + _ctx.auth.uid)
		if legacy["ok"]:
			cloud = PlayerProfile.from_legacy_text(str(legacy["fields"].get("progress", "")))
			from_legacy = not cloud.is_empty()
	if cloud.get("newer", false):
		return {"ok": false, "error": "newer", "changed": false}
	if public_doc["ok"]:
		if cloud.is_empty():
			cloud = PlayerProfile.from_cloud({"schemaVersion": PlayerProfile.SCHEMA_VERSION})
		cloud["nickname"] = str(public_doc["fields"].get("nickname", ""))
		cloud["nicknameNormalized"] = str(public_doc["fields"].get("nicknameNormalized", ""))
		cloud["nicknameVerified"] = cloud["nickname"] != ""
	var merged: Dictionary = PlayerProfile.local()
	if not cloud.is_empty():
		merged = PlayerProfile.merge(merged, cloud)
	PlayerProfile.save_local(merged)
	LevelCatalog.apply_sound()
	var result := {
		"ok": true, "error": "", "changed": PlayerProfile.content_hash(merged) != start_hash
	}
	if got["ok"] and PlayerProfile.content_hash(cloud) == PlayerProfile.content_hash(merged):
		PlayerProfile.mark_synced(merged)
		return result
	var written: Dictionary = await firestore.commit(
		[_profile_write(merged, got["ok"], str(got["update_time"]))]
	)
	if written["ok"]:
		PlayerProfile.mark_synced(merged)
		if from_legacy:
			await firestore.delete_doc("saves/" + _ctx.auth.uid)  # held a plain-text token
	elif int(written["code"]) in [400, 404, 409]:
		result.merge({"ok": false, "error": "server", "retry": true}, true)
	else:
		result.merge({"ok": false, "error": OnlineContext.reply_error(written)}, true)
	return result


## users/{uid} write: client fields only (updateMask), server timestamps, and
## a precondition (document unchanged since read / does not exist yet).
func _profile_write(p: Dictionary, exists: bool, update_time: String) -> Dictionary:
	var transforms: Array = [{"fieldPath": "updatedAt", "setToServerValue": "REQUEST_TIME"}]
	var write := {
		"update":
		{
			"name": _ctx.firestore.doc_name("users/" + _ctx.auth.uid),
			"fields": PlayerProfile.to_cloud_fields(p),
		},
		"updateMask": {"fieldPaths": PlayerProfile.SYNC_KEYS.duplicate()},
		"updateTransforms": transforms,
	}
	if exists:
		write["currentDocument"] = {"updateTime": update_time}
	else:
		transforms.append({"fieldPath": "createdAt", "setToServerValue": "REQUEST_TIME"})
		write["currentDocument"] = {"exists": false}
	return write


func _error_text(result: Dictionary) -> String:
	match str(result.get("error", "")):
		"offline":
			return _ctx.host.tr("ONLINE_ERR_OFFLINE")
		"newer":
			return _ctx.host.tr("ONLINE_ERR_NEWER")
		"session_lost":
			return _ctx.host.tr("ONLINE_ERR_SESSION_LOST")
		"not_configured":
			return _ctx.host.tr("ONLINE_ERR_NOT_CONFIGURED")
	return _ctx.host.tr("ONLINE_ERR_GENERIC")
