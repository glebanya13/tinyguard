extends Node
## Optional online features over Firebase REST APIs (no SDK, no native
## plugins). Autoload "Online": a facade over AuthService (guest sign-in,
## sessions), FirestoreClient (profile sync, leaderboards, callable functions)
## and PlayerProfile (local/cloud merge). Without res://firebase.cfg
## (docs/FIREBASE.md) everything online is disabled and the game, the local
## profile and the onboarding work offline.
## Sent: the anonymous uid, the reserved nickname, progression and settings,
## endless records. Never logged: tokens, raw replies, profile contents.

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
var functions_region: String = "europe-west1"
var auth := AuthService.new()
var firestore := FirestoreClient.new()
## The first start() finished (signed in and synced, or failed offline).
var startup_done: bool = false

var _transport: HttpTransport = null
var _started: bool = false
var _sync_busy: bool = false
var _reserve_busy: bool = false
## Error of the last sync ("" after a success).
var _last_error: String = ""


func _ready() -> void:
	var cfg := ConfigFile.new()
	var key := ""
	var project := ""
	var region := functions_region
	if cfg.load(CONFIG_PATH) == OK:
		key = str(cfg.get_value("firebase", "api_key", ""))
		project = str(cfg.get_value("firebase", "project_id", ""))
		region = str(cfg.get_value("firebase", "functions_region", region))
	setup(key, project, region, HttpTransport.new())


## (Re)wires the services. Tests pass a fake transport and a made-up project.
func setup(key: String, project: String, region: String, transport: HttpTransport) -> void:
	if _transport != null and _transport != transport:
		_transport.queue_free()
	_transport = transport
	if transport.get_parent() == null:
		add_child(transport)
	api_key = key
	project_id = project
	functions_region = region
	auth = AuthService.new()
	auth.api_key = key
	auth.transport = transport
	auth.changed.connect(_on_auth_changed)
	firestore = FirestoreClient.new()
	firestore.project_id = project
	firestore.functions_region = region
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


## Nickname screen: validates, reserves the name on the server (callable
## function reserveNickname) and stores it. {"ok", "reason", "error",
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


## Deletes the account: server data through the deleteAccount function, then
## the session and the local save. Without Firebase or an account only the
## local data is erased. {"ok", "reason", "scope" ("cloud" | "local")}.
func delete_account() -> Dictionary:
	if not is_configured() or auth.uid == "":
		_wipe_local()
		return {"ok": true, "reason": "", "scope": "local"}
	var signed: Dictionary = await auth.ensure_token(false)
	if not signed["ok"]:
		return {"ok": false, "reason": signed["error"], "scope": ""}
	var reply: Dictionary = await firestore.call_function("deleteAccount", {})
	if not reply["ok"]:
		return {"ok": false, "reason": reply["reason"], "scope": ""}
	_wipe_local()
	return {"ok": true, "reason": "", "scope": "cloud"}


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


## Sends the endless record of a level (the rules keep only higher records).
## The name is the reserved nickname, else ANONYMOUS_NAME.
func submit_record(level_id: int, wave: int) -> void:
	if not is_configured() or wave <= 0:
		return
	var signed: Dictionary = await auth.ensure_token(true)
	if not signed["ok"]:
		return
	var p: Dictionary = PlayerProfile.local()
	var nick: String = str(p["nickname"]) if bool(p["nicknameVerified"]) else ANONYMOUS_NAME
	var body := {
		"fields":
		{
			"name": {"stringValue": nick},
			"wave": {"integerValue": str(wave)},
			"updated": {"timestampValue": Time.get_datetime_string_from_system(true) + "Z"},
		}
	}
	var url: String = firestore.doc_url("leaderboards/level_%d/scores/%s" % [level_id, auth.uid])
	var reply: Dictionary = await firestore.request(HTTPClient.METHOD_PATCH, url, body, true)
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
			if reserved["reason"] in ["taken", "invalid", "reserved"]:
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
	if got["ok"]:
		cloud = PlayerProfile.from_cloud(got["fields"])
	else:
		var legacy: Dictionary = await firestore.get_doc("saves/" + auth.uid)
		if legacy["ok"]:
			cloud = PlayerProfile.from_legacy_text(str(legacy["fields"].get("progress", "")))
			from_legacy = not cloud.is_empty()
	if cloud.get("newer", false):
		return {"ok": false, "error": "newer", "changed": false}
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


## Calls reserveNickname; on success stores the name as verified.
## {"ok", "reason"}: "", taken, invalid, rate_limited, offline, unavailable...
func _reserve(nickname: String) -> Dictionary:
	var reply: Dictionary = await firestore.call_function("reserveNickname", {"nickname": nickname})
	if not reply["ok"]:
		return {"ok": false, "reason": reply["reason"]}
	var result: Dictionary = reply["result"] if reply["result"] is Dictionary else {}
	Onboarding.set_local_nickname(
		str(result.get("nickname", nickname)), str(result.get("normalized", "")), true
	)
	return {"ok": true, "reason": ""}


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
	elif reply["reason"] in ["taken", "invalid", "rate_limited", "reserved"]:
		out["reason"] = reply["reason"]
		out["error"] = "taken" if reply["reason"] == "reserved" else reply["reason"]
	else:
		# No connection or the server is unavailable: keep the name on the device
		# (unverified) and reserve it at the next sync.
		Onboarding.set_local_nickname(check["nickname"], check["normalized"], false)
		out.merge({"reason": "offline", "saved_locally": true}, true)
	return out


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
