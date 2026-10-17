class_name OnlineNicknames
extends RefCounted
## Nicknames of Online: the atomic reservation in Firestore (nicknames/{key} is
## create-only, checked by firestore.rules), the 24 hour change clock and the
## renaming of the player's records. The screen-facing entry is reserve_nickname().

## Minimum time between nickname changes (firestore.rules enforce the same 24 hours).
const NICKNAME_CHANGE_SECONDS := 86400
const _PROFILE_TIMES: Array[String] = ["createdAt", "nicknameChangedAt"]

var _ctx: OnlineContext
var _reserve_busy: bool = false


func _init(context: OnlineContext) -> void:
	_ctx = context


static func clock_expired(changed_at: int) -> bool:
	return Time.get_unix_time_from_system() >= changed_at + NICKNAME_CHANGE_SECONDS


func player_name() -> String:
	return str(PlayerProfile.local()["nickname"])


## Sets a new nickname if it is valid; it is reserved on the next sync.
func set_player_name(value: String) -> void:
	var check: Dictionary = NicknameRules.validate(value)
	if not check["ok"] or check["normalized"] == str(PlayerProfile.local()["nicknameNormalized"]):
		return
	Onboarding.set_local_nickname(check["nickname"], check["normalized"], false)
	if _ctx.is_configured():
		_ctx.sync.sync_now()


## Nickname screen: validates, reserves the name in Firestore (one atomic
## commit, checked by firestore.rules: nicknames/{key} is create-only) and
## stores it. {"ok", "reason", "error",
## "saved_locally"}. reason: reserved, local (no Firebase), offline (kept on
## the device as unverified, reserved at the next sync), taken, invalid,
## rate_limited, busy.
func reserve_nickname(raw: String) -> Dictionary:
	var check: Dictionary = NicknameRules.validate(raw)
	if not check["ok"]:
		return {"ok": false, "reason": "invalid", "error": check["error"], "saved_locally": false}
	if _reserve_busy:
		return {"ok": false, "reason": "busy", "error": "", "saved_locally": false}
	_reserve_busy = true
	var result: Dictionary = await _reserve_flow(check)
	_reserve_busy = false
	return result


## Reserves the nickname for the signed-in player and stores it as verified.
## One atomic commit: create nicknames/{key} (fails when taken), release the
## old key, write publicProfiles/{uid}. {"ok", "reason"}: "", invalid, taken,
## rate_limited, offline, server, denied.
func reserve(nickname: String) -> Dictionary:
	var firestore: FirestoreClient = _ctx.firestore
	var check: Dictionary = NicknameRules.validate(nickname)
	if not check["ok"]:
		return {"ok": false, "reason": "invalid"}
	var key: String = check["normalized"]
	var uid: String = _ctx.auth.uid
	var current: Dictionary = await firestore.get_doc("publicProfiles/" + uid)
	if not current["ok"] and not current["missing"]:
		return {"ok": false, "reason": OnlineContext.reply_error(current)}
	var old_key := ""
	if current["ok"]:
		old_key = str(current["fields"].get("nicknameNormalized", ""))
		if old_key == key:  # already reserved (e.g. from another device)
			var stored: String = str(current["fields"].get("nickname", nickname))
			Onboarding.set_local_nickname(stored, key, true)
			return {"ok": true, "reason": ""}
	var blocked: String = await _clock_block(current, uid)
	if blocked != "":
		return {"ok": false, "reason": blocked}
	var writes: Array = []
	if old_key != "":
		writes.append(firestore.write_delete("nicknames/" + old_key))
	var index := {"uid": uid, "nickname": check["nickname"]}
	writes.append(firestore.write_create("nicknames/" + key, index, ["createdAt"]))
	var profile := {"nickname": check["nickname"], "nicknameNormalized": key}
	# The trace keeps the 24 hour clock when the profile is deleted (firestore.rules).
	writes.append(firestore.write_set("nicknameTrace/" + uid, {}, ["changedAt"]))
	if old_key == "":
		writes.append(firestore.write_create("publicProfiles/" + uid, profile, _PROFILE_TIMES))
	else:
		var time_fields: Array[String] = ["nicknameChangedAt"]
		writes.append(firestore.write_update("publicProfiles/" + uid, profile, time_fields))
	var reply: Dictionary = await firestore.commit(writes)
	if not reply["ok"]:
		return {"ok": false, "reason": await _reserve_failure(reply, key, uid)}
	Onboarding.set_local_nickname(check["nickname"], key, true)
	_rename_records(check["nickname"])
	return {"ok": true, "reason": ""}


## Why a nickname commit was refused: the name is taken (another uid owns the
## index document) or something else. The rules answer 403 for both.
func _reserve_failure(reply: Dictionary, key: String, uid: String) -> String:
	var code: int = int(reply.get("code", 0))
	if code == 409:  # precondition: the index document exists
		return "taken"
	if code != 403:
		return OnlineContext.reply_error(reply)
	var owner: Dictionary = await _ctx.firestore.get_doc("nicknames/" + key)
	if owner["ok"] and str(owner["fields"].get("uid", "")) != uid:
		return "taken"
	return "denied"


## "" if the 24 hour nickname clock allows a (re)reservation now, else "rate_limited" or an
## error reason. With a profile its nicknameChangedAt counts; without one (deleted and
## recreated?) the nicknameTrace document does.
func _clock_block(current: Dictionary, uid: String) -> String:
	if current["ok"]:
		var changed_at: int = int(current["fields"].get("nicknameChangedAt", 0))
		return "" if clock_expired(changed_at) else "rate_limited"
	var trace: Dictionary = await _ctx.firestore.get_doc("nicknameTrace/" + uid)
	if not trace["ok"] and not trace["missing"]:
		return OnlineContext.reply_error(trace)
	if trace["ok"] and not clock_expired(int(trace["fields"].get("changedAt", 0))):
		return "rate_limited"
	return ""


## Best effort: the player's old endless records show the new nickname.
func _rename_records(nickname: String) -> void:
	var endless: Dictionary = PlayerProfile.local()["progression"]["endless"]
	var no_times: Array[String] = []
	for id: String in endless:
		var path: String = "leaderboards/level_%d/scores/%s" % [int(id), _ctx.auth.uid]
		await _ctx.firestore.commit(
			[_ctx.firestore.write_update(path, {"name": nickname}, no_times)]
		)


func _reserve_flow(check: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": "", "error": "", "saved_locally": false}
	if not _ctx.is_configured():
		Onboarding.set_local_nickname(check["nickname"], check["normalized"], false)
		out.merge({"ok": true, "reason": "local", "saved_locally": true}, true)
		return out
	var signed: Dictionary = await _ctx.auth.ensure_token(true)
	var reply: Dictionary = {"ok": false, "reason": "offline"}
	if signed["ok"]:
		reply = await reserve(check["nickname"])
	if reply["ok"]:
		out.merge({"ok": true, "reason": "reserved"}, true)
		_ctx.sync.sync_now()
	elif reply["reason"] in ["taken", "invalid", "rate_limited"]:
		out["reason"] = reply["reason"]
		out["error"] = reply["reason"]
	else:
		# No connection or the server is unavailable: keep the name on the device
		# (unverified) and reserve it at the next sync.
		Onboarding.set_local_nickname(check["nickname"], check["normalized"], false)
		out.merge({"reason": "offline", "saved_locally": true}, true)
	return out
