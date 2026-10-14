# gdlint:disable=max-public-methods
extends Node
## Optional online features over Firebase REST APIs (no SDK, no native
## plugins). Autoload "Online": a facade over AuthService (guest sign-in,
## sessions), FirestoreClient (profile sync, leaderboards, nicknames)
## and PlayerProfile (local/cloud merge). Without res://firebase.cfg
## (docs/FIREBASE.md) everything online is disabled and the game, the local
## profile and the onboarding work offline.
## Sent: the anonymous uid, the reserved nickname, progression and settings,
## endless records. An email and password go only to Firebase Auth, only when
## the player links or signs in, and are never stored on the device.
## Never logged: tokens, emails, passwords, raw replies, profile contents.

signal leaderboard_loaded(level_id: int, entries: Array)
signal status_changed(text: String)
signal cloud_loaded(ok: bool)
## See sync_state().
signal sync_state_changed(state: String)
## The signed-in account (uid or type) changed.
signal account_changed
## A sync_now() finished (concurrent callers wait for this).
signal sync_finished(result: Dictionary)

const CONFIG_PATH := "res://firebase.cfg"
const LEADERBOARD_SIZE := 10
const NAME_MAX := 16
## Leaderboard name of players without a reserved nickname (firestore.rules).
const ANONYMOUS_NAME := "Рыцарь"
## Rounds of read-merge-write when another device writes in between.
const MAX_SYNC_ROUNDS := 3
## Minimum time between nickname changes (firestore.rules enforce the same 24 hours).
const NICKNAME_CHANGE_SECONDS := 86400
const _PROFILE_TIMES: Array[String] = ["createdAt", "nicknameChangedAt"]
const STATE_TEXT := {
	"off": "Только на этом устройстве",
	"syncing": "Синхронизация…",
	"synced": "Сохранено в облаке",
	"pending": "Не синхронизировано",
	"offline": "Не синхронизировано · нет связи",
	"session_lost": "Не синхронизировано · вход потерян",
	"newer": "Не синхронизировано · обновите игру",
	"disabled": "Аккаунт заблокирован",
}

var api_key: String = ""
var project_id: String = ""
var auth := AuthService.new()
var firestore := FirestoreClient.new()
## The first start() finished (signed in and synced, or failed offline).
var startup_done: bool = false

var _transport: HttpTransport = null
var _started: bool = false
var _sync_busy: bool = false
var _reserve_busy: bool = false
## A link / sign-in / sign-out request is running (one at a time).
var _email_busy: bool = false
## The account is being switched: no sync may run on a half-switched session.
var _switching: bool = false
## Error of the last sync ("" after a success).
var _last_error: String = ""


func _ready() -> void:
	var cfg := ConfigFile.new()
	var key := ""
	var project := ""
	if cfg.load(CONFIG_PATH) == OK:
		key = str(cfg.get_value("firebase", "api_key", ""))
		project = str(cfg.get_value("firebase", "project_id", ""))
	setup(key, project, HttpTransport.new())


## (Re)wires the services. Tests pass a fake transport and a made-up project.
func setup(key: String, project: String, transport: HttpTransport) -> void:
	if _transport != null and _transport != transport:
		_transport.queue_free()
	_transport = transport
	if transport.get_parent() == null:
		add_child(transport)
	api_key = key
	project_id = project
	auth = AuthService.new()
	auth.api_key = key
	auth.transport = transport
	auth.changed.connect(_on_auth_changed)
	firestore = FirestoreClient.new()
	firestore.project_id = project
	firestore.transport = transport
	firestore.auth = auth
	_started = false
	startup_done = false
	_last_error = ""


func is_configured() -> bool:
	return api_key != "" and project_id != ""


## Boot: restores the session, migrates old saves, signs in as a guest if
## needed and syncs the profile. Idempotent; never blocks the offline game.
func start() -> void:
	if _started:
		return
	_started = true
	var cfg: ConfigFile = LevelCatalog.data()
	auth.restore(str(cfg.get_value(PlayerProfile.SECTION, "account_uid", "")))
	auth.adopt_legacy(
		str(cfg.get_value("online", "uid", "")), str(cfg.get_value("online", "refresh_token", ""))
	)
	PlayerProfile.touch_local()  # migrates a schema-0 save (reads [online] name)
	if cfg.has_section("online"):
		cfg.erase_section("online")  # the refresh token must not stay in plain text
		LevelCatalog.commit()
	_remember_uid()
	if is_configured():
		await sync_now()
	startup_done = true
	sync_state_changed.emit(sync_state())


## "off" (no Firebase), "syncing", "synced", "pending", "offline",
## "session_lost", "newer", "disabled".
func sync_state() -> String:
	if not is_configured():
		return "off"
	if _sync_busy:
		return "syncing"
	if _last_error in ["session_lost", "newer", "disabled"]:
		return _last_error
	if not PlayerProfile.is_pending():
		return "synced"
	return "offline" if _last_error != "" else "pending"


static func state_text(state: String) -> String:
	return str(STATE_TEXT.get(state, ""))


## "local" (no Firebase), "guest", "email" or "none" (not signed in yet).
func account_type() -> String:
	if not is_configured():
		return "local"
	return auth.account_type if auth.uid != "" else "none"


## Reads the cloud profile, merges it with the local one and writes the
## result back (never overwrites newer cloud progress: progression only grows,
## and the write is conditional on the document not changing in between).
## One sync at a time: concurrent callers get the running one's result.
## {"ok", "error", "changed" (local progress changed)}.
func sync_now() -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "not_configured", "changed": false}
	if _switching:
		return {"ok": false, "error": "busy", "changed": false}
	if _sync_busy:
		return await sync_finished
	_sync_busy = true
	sync_state_changed.emit("syncing")
	var result: Dictionary = await _sync()
	_last_error = "" if result["ok"] else str(result["error"])
	_sync_busy = false
	sync_state_changed.emit(sync_state())
	sync_finished.emit(result)
	return result


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


## Deletes the account from the client (Spark plan, no Cloud Functions): the
## player's own Firestore documents (profile, nickname and its index entry,
## records, legacy save), then the Firebase Auth user (accounts:delete), then
## the local data. Safe to repeat after a partial failure. Without Firebase or
## an account only the local data is erased.
## {"ok", "reason", "scope" ("cloud" | "local")}.
func delete_account() -> Dictionary:
	if not is_configured() or auth.uid == "":
		_wipe_local()
		return {"ok": true, "reason": "", "scope": "local"}
	var signed: Dictionary = await auth.ensure_token(false)
	if not signed["ok"]:
		return {"ok": false, "reason": signed["error"], "scope": ""}
	var plan: Dictionary = await _deletion_writes(auth.uid)
	if not plan["ok"]:
		return {"ok": false, "reason": plan["reason"], "scope": ""}
	var writes: Array = plan["writes"]
	var deleted: Dictionary = await firestore.commit(writes)
	if not deleted["ok"] and int(deleted.get("code", 0)) == 403 and plan["trace_included"]:
		# The server thinks the nickname trace is younger than 24 hours (clock skew):
		# delete everything else; the trace is inert once the Auth user is gone.
		writes = writes.filter(func(w: Dictionary) -> bool: return not _is_trace_delete(w))
		deleted = await firestore.commit(writes)
	if not deleted["ok"]:
		return {"ok": false, "reason": _reply_error(deleted), "scope": ""}
	var removed: Dictionary = await auth.delete_account()
	if not removed["ok"]:
		return {"ok": false, "reason": removed["error"], "scope": ""}
	_wipe_local()
	return {"ok": true, "reason": "", "scope": "cloud"}


## The deletes that remove everything stored under `uid`. The rules only let
## the owner delete an existing nickname index document, so it is looked up first.
## nicknameTrace/{uid} (the 24 hour nickname clock) may only be deleted once 24 hours
## have passed since the last change, so it is included only then.
## {"ok", "reason", "writes", "trace_included"}.
func _deletion_writes(uid: String) -> Dictionary:
	var writes: Array = []
	var trace_included := false
	var profile_path: String = "publicProfiles/" + uid
	var public_doc: Dictionary = await firestore.get_doc(profile_path)
	if not public_doc["ok"] and not public_doc["missing"]:
		return {
			"ok": false,
			"reason": _reply_error(public_doc),
			"writes": writes,
			"trace_included": false
		}
	if public_doc["ok"]:
		var key: String = str(public_doc["fields"].get("nicknameNormalized", ""))
		var name_doc: Dictionary = await firestore.get_doc("nicknames/" + key)
		if not name_doc["ok"] and not name_doc["missing"]:
			return {
				"ok": false,
				"reason": _reply_error(name_doc),
				"writes": writes,
				"trace_included": false
			}
		if name_doc["ok"] and str(name_doc["fields"].get("uid", "")) == uid:
			writes.append(firestore.write_delete("nicknames/" + key))
		writes.append(firestore.write_delete(profile_path))
	var trace: Dictionary = await firestore.get_doc("nicknameTrace/" + uid)
	if not trace["ok"] and not trace["missing"]:
		return {
			"ok": false, "reason": _reply_error(trace), "writes": writes, "trace_included": false
		}
	if trace["ok"] and _nickname_clock_expired(int(trace["fields"].get("changedAt", 0))):
		writes.append(firestore.write_delete("nicknameTrace/" + uid))
		trace_included = true
	writes.append(firestore.write_delete("runs/" + uid))
	writes.append(firestore.write_delete("users/" + uid))
	writes.append(firestore.write_delete("saves/" + uid))
	for level: Dictionary in LevelCatalog.levels():
		var scores: String = "leaderboards/level_%d/scores/%s" % [int(level["id"]), uid]
		writes.append(firestore.write_delete(scores))
	return {"ok": true, "reason": "", "writes": writes, "trace_included": trace_included}


## Erases only this device's data (profile, progress, session).
func erase_local_data() -> void:
	_wipe_local()


## Explicit choice when the old session cannot be restored: new guest account.
func start_new_guest() -> Dictionary:
	var result: Dictionary = await auth.start_new_guest()
	if result["ok"]:
		var p: Dictionary = PlayerProfile.local()
		p["nicknameVerified"] = false
		PlayerProfile.save_local(p)
		_last_error = ""
		sync_now()
	return result


## Links an email and password to the current guest account (accounts:update):
## the uid, the profile and the progress stay, the account can then be opened on
## another device. {"ok", "error"}; error is an EmailRules message key. The
## password lives only in this call (never stored, never logged).
func link_email(email: String, password: String) -> Dictionary:
	var check: Dictionary = _check_credentials(email, password, true)
	if not check["ok"]:
		return check
	if _email_busy:
		return {"ok": false, "error": "busy"}
	_email_busy = true
	var result: Dictionary = await auth.link_email(check["email"], password)
	_email_busy = false
	return result


## Signs in with email and password. On another device this switches to that
## account: its cloud profile is merged with the local one (progress only grows:
## best stars and records, most open levels; the account's nickname wins, the
## nickname of the abandoned guest is dropped). Signing in again to the account
## that is already open only refreshes the login (needed before deleting it).
## {"ok", "error", "switched", "synced" (the merge reached the cloud)}.
func sign_in_email(email: String, password: String) -> Dictionary:
	var check: Dictionary = _check_credentials(email, password, false)
	if not check["ok"]:
		return {"ok": false, "error": check["error"], "switched": false, "synced": false}
	if _email_busy:
		return {"ok": false, "error": "busy", "switched": false, "synced": false}
	_email_busy = true
	if _sync_busy:
		await sync_finished  # a sync of the old account must not meet the new session
	_switching = true
	var reply: Dictionary = await auth.sign_in_email(check["email"], password)
	var result := {"ok": false, "error": str(reply["error"]), "switched": false, "synced": false}
	if reply["ok"]:
		if reply["switched"]:
			_forget_nickname_of_old_account()
		_last_error = ""
		result.merge({"ok": true, "error": "", "switched": reply["switched"]}, true)
	_switching = false
	if reply["ok"]:
		var synced: Dictionary = await sync_now()
		result["synced"] = synced["ok"]
	_email_busy = false
	return result


## Sends the password reset mail. Unknown addresses look like success on purpose.
## {"ok", "error"}.
func send_password_reset(email: String) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "not_configured"}
	var check: Dictionary = EmailRules.check_email(email)
	if not check["ok"]:
		return {"ok": false, "error": check["error"]}
	return await auth.send_password_reset(check["email"])


## Signs out of an email account: unsaved progress is pushed first (without a
## connection the sign-out is refused so nothing is lost), then this device
## forgets the session and its local data; the progress stays in the cloud under
## the email. A guest cannot sign out (its only copy would be lost).
## {"ok", "error"}.
func sign_out() -> Dictionary:
	if not is_configured() or auth.account_type != AuthService.TYPE_EMAIL:
		return {"ok": false, "error": "guest_cannot_sign_out"}
	if _email_busy:
		return {"ok": false, "error": "busy"}
	_email_busy = true
	var synced: Dictionary = await sync_now()
	if not synced["ok"] and PlayerProfile.is_pending():
		_email_busy = false
		return {"ok": false, "error": "unsynced"}
	_wipe_local()
	_email_busy = false
	return {"ok": true, "error": ""}


# --- API used by the map and the level (kept from the first version) ---


func player_name() -> String:
	return str(PlayerProfile.local()["nickname"])


## Sets a new nickname if it is valid; it is reserved on the next sync.
func set_player_name(value: String) -> void:
	var check: Dictionary = NicknameRules.validate(value)
	if not check["ok"] or check["normalized"] == str(PlayerProfile.local()["nicknameNormalized"]):
		return
	Onboarding.set_local_nickname(check["nickname"], check["normalized"], false)
	if is_configured():
		sync_now()


## Marks the start of an endless run on the server (runs/{uid}, server time). The
## rules accept a record of wave N only (N-1)*15 s after this moment, so call it
## when the run begins. Fire and forget; without a connection the run simply
## has no online record. Returns true if the start was stored.
func start_run(level_id: int) -> bool:
	if not is_configured():
		return false
	var signed: Dictionary = await auth.ensure_token(true)
	if not signed["ok"]:
		return false
	var data := {"level": "level_%d" % level_id}
	var write: Dictionary = firestore.write_set("runs/" + auth.uid, data, ["startedAt"])
	var reply: Dictionary = await firestore.commit([write])
	return reply["ok"]


## Sends the endless record of a level (the rules keep only higher records, stamp
## the time with the server clock and check it against start_run()).
## The name is the reserved nickname, else ANONYMOUS_NAME.
func submit_record(level_id: int, wave: int) -> void:
	if not is_configured() or wave <= 0:
		return
	var signed: Dictionary = await auth.ensure_token(true)
	if not signed["ok"]:
		return
	var p: Dictionary = PlayerProfile.local()
	var nick: String = str(p["nickname"]) if bool(p["nicknameVerified"]) else ANONYMOUS_NAME
	var path: String = "leaderboards/level_%d/scores/%s" % [level_id, auth.uid]
	var write: Dictionary = firestore.write_set(path, {"name": nick, "wave": wave}, ["updated"])
	var reply: Dictionary = await firestore.commit([write])
	status_changed.emit("Рекорд отправлен" if reply["ok"] else "Не удалось отправить рекорд")


func fetch_leaderboard(level_id: int) -> void:
	if not is_configured():
		leaderboard_loaded.emit(level_id, [])
		return
	var query := {
		"from": [{"collectionId": "scores"}],
		"orderBy": [{"field": {"fieldPath": "wave"}, "direction": "DESCENDING"}],
		"limit": LEADERBOARD_SIZE,
	}
	var reply: Dictionary = await firestore.run_query(
		"leaderboards/level_%d" % level_id, query, false
	)
	leaderboard_loaded.emit(level_id, parse_leaderboard(reply["json"]) if reply["ok"] else [])


## Syncs the profile now (the button "В облако").
func cloud_save() -> void:
	var result: Dictionary = await sync_now()
	status_changed.emit("Прогресс сохранён в облаке" if result["ok"] else _error_text(result))


## Merges the cloud profile into the local one (the button "Из облака");
## cloud_loaded(true) when local progress changed.
func cloud_load() -> void:
	var result: Dictionary = await sync_now()
	var changed: bool = result["ok"] and result["changed"]
	if result["ok"]:
		status_changed.emit("Прогресс обновлён из облака" if changed else "Прогресс уже совпадает")
	else:
		status_changed.emit(_error_text(result))
	cloud_loaded.emit(changed)


## Firestore runQuery reply -> [{name, wave}], best first.
static func parse_leaderboard(json: Variant) -> Array:
	var out: Array = []
	if not json is Array:
		return out
	for row: Variant in json:
		if not row is Dictionary or not (row as Dictionary).has("document"):
			continue
		var fields: Dictionary = row["document"].get("fields", {})
		(
			out
			. append(
				{
					"name": str(fields.get("name", {}).get("stringValue", "?")),
					"wave": int(fields.get("wave", {}).get("integerValue", "0")),
				}
			)
		)
	return out


## Legacy cloud save document (saves/{uid}) -> progress text ("" if missing).
static func parse_save(json: Variant) -> String:
	if not json is Dictionary:
		return ""
	return str(json.get("fields", {}).get("progress", {}).get("stringValue", ""))


## Legacy free-form name cleanup (control characters dropped, cut to NAME_MAX).
## New names go through NicknameRules.
static func clean_name(value: String) -> String:
	var out := ""
	for ch in value.strip_edges():
		if ch.unicode_at(0) >= 32:
			out += ch
	return out.substr(0, NAME_MAX)


func _sync() -> Dictionary:
	var signed: Dictionary = await auth.ensure_token(true)
	if not signed["ok"]:
		return {"ok": false, "error": signed["error"], "changed": false}
	_remember_uid()
	var local: Dictionary = PlayerProfile.touch_local()
	if signed["created"] and bool(local["nicknameVerified"]):
		# A new guest account replaced a dead one: reserve the name again.
		local["nicknameVerified"] = false
		PlayerProfile.save_local(local)
	if str(local["nickname"]) != "" and not bool(local["nicknameVerified"]):
		if not bool(local["nicknameConflict"]):
			var reserved: Dictionary = await _reserve(str(local["nickname"]))
			if reserved["reason"] in ["taken", "invalid"]:
				Onboarding.flag_nickname_conflict()
				status_changed.emit("Имя «%s» занято — выбери другое" % local["nickname"])
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
	var got: Dictionary = await firestore.get_doc("users/" + auth.uid)
	if not got["ok"] and not got["missing"]:
		return {"ok": false, "error": _reply_error(got), "changed": false}
	var cloud: Dictionary = {}
	var from_legacy := false
	var public_doc: Dictionary = await firestore.get_doc("publicProfiles/" + auth.uid)
	if not public_doc["ok"] and not public_doc["missing"]:
		return {"ok": false, "error": _reply_error(public_doc), "changed": false}
	if got["ok"]:
		cloud = PlayerProfile.from_cloud(got["fields"])
	else:
		var legacy: Dictionary = await firestore.get_doc("saves/" + auth.uid)
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
			await firestore.delete_doc("saves/" + auth.uid)  # held a plain-text token
	elif int(written["code"]) in [400, 404, 409]:
		result.merge({"ok": false, "error": "server", "retry": true}, true)
	else:
		result.merge({"ok": false, "error": _reply_error(written)}, true)
	return result


## users/{uid} write: client fields only (updateMask), server timestamps, and
## a precondition (document unchanged since read / does not exist yet).
func _profile_write(p: Dictionary, exists: bool, update_time: String) -> Dictionary:
	var transforms: Array = [{"fieldPath": "updatedAt", "setToServerValue": "REQUEST_TIME"}]
	var write := {
		"update":
		{
			"name": firestore.doc_name("users/" + auth.uid),
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


## Reserves the nickname for the signed-in player and stores it as verified.
## One atomic commit: create nicknames/{key} (fails when taken), release the
## old key, write publicProfiles/{uid}. {"ok", "reason"}: "", invalid, taken,
## rate_limited, offline, server, denied.
func _reserve(nickname: String) -> Dictionary:
	var check: Dictionary = NicknameRules.validate(nickname)
	if not check["ok"]:
		return {"ok": false, "reason": "invalid"}
	var key: String = check["normalized"]
	var uid: String = auth.uid
	var current: Dictionary = await firestore.get_doc("publicProfiles/" + uid)
	if not current["ok"] and not current["missing"]:
		return {"ok": false, "reason": _reply_error(current)}
	var old_key := ""
	if current["ok"]:
		old_key = str(current["fields"].get("nicknameNormalized", ""))
		if old_key == key:  # already reserved (e.g. from another device)
			var stored: String = str(current["fields"].get("nickname", nickname))
			Onboarding.set_local_nickname(stored, key, true)
			return {"ok": true, "reason": ""}
	var blocked: String = await _nickname_clock_block(current, uid)
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
		return _reply_error(reply)
	var owner: Dictionary = await firestore.get_doc("nicknames/" + key)
	if owner["ok"] and str(owner["fields"].get("uid", "")) != uid:
		return "taken"
	return "denied"


## "" if the 24 hour nickname clock allows a (re)reservation now, else "rate_limited" or an
## error reason. With a profile its nicknameChangedAt counts; without one (deleted and
## recreated?) the nicknameTrace document does.
func _nickname_clock_block(current: Dictionary, uid: String) -> String:
	if current["ok"]:
		var changed_at: int = int(current["fields"].get("nicknameChangedAt", 0))
		return "" if _nickname_clock_expired(changed_at) else "rate_limited"
	var trace: Dictionary = await firestore.get_doc("nicknameTrace/" + uid)
	if not trace["ok"] and not trace["missing"]:
		return _reply_error(trace)
	if trace["ok"] and not _nickname_clock_expired(int(trace["fields"].get("changedAt", 0))):
		return "rate_limited"
	return ""


func _nickname_clock_expired(changed_at: int) -> bool:
	return Time.get_unix_time_from_system() >= changed_at + NICKNAME_CHANGE_SECONDS


func _is_trace_delete(write: Dictionary) -> bool:
	return str(write.get("delete", "")).contains("/nicknameTrace/")


## Best effort: the player's old endless records show the new nickname.
func _rename_records(nickname: String) -> void:
	var endless: Dictionary = PlayerProfile.local()["progression"]["endless"]
	var no_times: Array[String] = []
	for id: String in endless:
		var path: String = "leaderboards/level_%d/scores/%s" % [int(id), auth.uid]
		await firestore.commit([firestore.write_update(path, {"name": nickname}, no_times)])


func _reserve_flow(check: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": "", "error": "", "saved_locally": false}
	if not is_configured():
		Onboarding.set_local_nickname(check["nickname"], check["normalized"], false)
		out.merge({"ok": true, "reason": "local", "saved_locally": true}, true)
		return out
	var signed: Dictionary = await auth.ensure_token(true)
	var reply: Dictionary = {"ok": false, "reason": "offline"}
	if signed["ok"]:
		reply = await _reserve(check["nickname"])
	if reply["ok"]:
		out.merge({"ok": true, "reason": "reserved"}, true)
		sync_now()
	elif reply["reason"] in ["taken", "invalid", "rate_limited"]:
		out["reason"] = reply["reason"]
		out["error"] = reply["reason"]
	else:
		# No connection or the server is unavailable: keep the name on the device
		# (unverified) and reserve it at the next sync.
		Onboarding.set_local_nickname(check["nickname"], check["normalized"], false)
		out.merge({"reason": "offline", "saved_locally": true}, true)
	return out


## {"ok", "error", "email"}: client-side checks before any request is sent.
func _check_credentials(email: String, password: String, new_password: bool) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "not_configured"}
	var mail: Dictionary = EmailRules.check_email(email)
	if not mail["ok"]:
		return mail
	var word: Dictionary = (
		EmailRules.check_new_password(password)
		if new_password
		else EmailRules.check_password(password)
	)
	if not word["ok"]:
		return word
	return mail


## After switching to another account the nickname of the old guest (reserved
## under its uid) is not ours any more: the account's own nickname comes with the
## next sync, and an account without one is asked for a name.
func _forget_nickname_of_old_account() -> void:
	var p: Dictionary = PlayerProfile.local()
	p["nickname"] = ""
	p["nicknameNormalized"] = ""
	p["nicknameVerified"] = false
	p["nicknameConflict"] = false
	PlayerProfile.save_local(p)


func _wipe_local() -> void:
	auth.forget()
	LevelCatalog.erase_all()
	LevelCatalog.tutorial = false
	_started = false
	startup_done = false
	_last_error = ""
	sync_state_changed.emit(sync_state())


func _remember_uid() -> void:
	var cfg: ConfigFile = LevelCatalog.data()
	if str(cfg.get_value(PlayerProfile.SECTION, "account_uid", "")) != auth.uid:
		cfg.set_value(PlayerProfile.SECTION, "account_uid", auth.uid)
		LevelCatalog.commit()


func _on_auth_changed() -> void:
	_remember_uid()
	account_changed.emit()


static func _reply_error(reply: Dictionary) -> String:
	if reply.get("network", false):
		return "offline"
	var code: int = int(reply.get("code", 0))
	if code == 401 or code == 403:
		return "denied"
	return "server"


func _error_text(result: Dictionary) -> String:
	match str(result.get("error", "")):
		"offline":
			return "Нет связи с сервером"
		"newer":
			return "Облачный прогресс из новой версии — обновите игру"
		"session_lost":
			return "Вход потерян — откройте Профиль"
		"not_configured":
			return "Облако недоступно"
	return "Не удалось синхронизировать"
