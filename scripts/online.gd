extends Node
## Optional online features over the Firebase REST API (no native plugins):
## anonymous sign-in, an endless-siege leaderboard per level (Firestore) and a
## cloud copy of the progress. Autoload "Online". Without res://firebase.cfg
## (see docs/FIREBASE.md) everything is disabled and the game stays offline.
## Only an anonymous id, the chosen nickname and records are sent.

signal leaderboard_loaded(level_id: int, entries: Array)
signal status_changed(text: String)
signal cloud_loaded(ok: bool)

const CONFIG_PATH := "res://firebase.cfg"
const AUTH_URL := "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s"
const REFRESH_URL := "https://securetoken.googleapis.com/v1/token?key=%s"
const FIRESTORE_HOST := "https://firestore.googleapis.com/v1"
const FIRESTORE_PATH := "/projects/%s/databases/(default)/documents"
const LEADERBOARD_SIZE := 10
const NAME_MAX := 16
const TIMEOUT := 10.0

var api_key: String = ""
var project_id: String = ""

var _uid: String = ""
var _id_token: String = ""
var _refresh_token: String = ""
var _token_expires: float = 0.0


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		api_key = str(cfg.get_value("firebase", "api_key", ""))
		project_id = str(cfg.get_value("firebase", "project_id", ""))
	var saved: ConfigFile = LevelCatalog.data()
	_uid = str(saved.get_value("online", "uid", ""))
	_refresh_token = str(saved.get_value("online", "refresh_token", ""))


func is_configured() -> bool:
	return api_key != "" and project_id != ""


func player_name() -> String:
	return str(LevelCatalog.data().get_value("online", "name", ""))


func set_player_name(value: String) -> void:
	LevelCatalog.data().set_value("online", "name", clean_name(value))
	LevelCatalog.commit()


## Sends the endless record of a level (keeps the best on the server via rules
## and by sending only the local best).
func submit_record(level_id: int, wave: int) -> void:
	if not is_configured() or wave <= 0:
		return
	if not await _ensure_auth():
		return
	var nick: String = player_name() if player_name() != "" else "Рыцарь"
	var body := {
		"fields":
		{
			"name": {"stringValue": nick},
			"wave": {"integerValue": str(wave)},
			"updated": {"timestampValue": Time.get_datetime_string_from_system(true) + "Z"},
		}
	}
	var url: String = "%s/leaderboards/level_%d/scores/%s" % [_base(), level_id, _uid]
	var reply: Dictionary = await _request(HTTPClient.METHOD_PATCH, url, body, true)
	status_changed.emit("Рекорд отправлен" if reply["ok"] else "Не удалось отправить рекорд")


func fetch_leaderboard(level_id: int) -> void:
	if not is_configured():
		leaderboard_loaded.emit(level_id, [])
		return
	var query := {
		"structuredQuery":
		{
			"from": [{"collectionId": "scores"}],
			"orderBy": [{"field": {"fieldPath": "wave"}, "direction": "DESCENDING"}],
			"limit": LEADERBOARD_SIZE,
		}
	}
	var url: String = "%s/leaderboards/level_%d:runQuery" % [_base(), level_id]
	var reply: Dictionary = await _request(HTTPClient.METHOD_POST, url, query, false)
	leaderboard_loaded.emit(level_id, parse_leaderboard(reply["json"]) if reply["ok"] else [])


## Uploads the whole progress file (stars, perks, records, settings).
func cloud_save() -> void:
	if not is_configured() or not await _ensure_auth():
		status_changed.emit("Облако недоступно")
		return
	var body := {"fields": {"progress": {"stringValue": LevelCatalog.data().encode_to_text()}}}
	var reply: Dictionary = await _request(
		HTTPClient.METHOD_PATCH, "%s/saves/%s" % [_base(), _uid], body, true
	)
	status_changed.emit("Прогресс сохранён в облаке" if reply["ok"] else "Не удалось сохранить")


## Replaces the local progress with the cloud copy (keeps the online identity).
func cloud_load() -> void:
	if not is_configured() or not await _ensure_auth():
		cloud_loaded.emit(false)
		return
	var reply: Dictionary = await _request(
		HTTPClient.METHOD_GET, "%s/saves/%s" % [_base(), _uid], {}, true
	)
	var text: String = parse_save(reply["json"]) if reply["ok"] else ""
	var ok: bool = text != "" and LevelCatalog.replace_with(text)
	if ok:
		_store_identity()
	status_changed.emit("Прогресс загружен из облака" if ok else "В облаке нет сохранения")
	cloud_loaded.emit(ok)


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


## Firestore document reply -> saved progress text ("" if missing).
static func parse_save(json: Variant) -> String:
	if not json is Dictionary:
		return ""
	return str(json.get("fields", {}).get("progress", {}).get("stringValue", ""))


## Nickname without control characters, trimmed to NAME_MAX.
static func clean_name(value: String) -> String:
	var out := ""
	for ch in value.strip_edges():
		if ch.unicode_at(0) >= 32:
			out += ch
	return out.substr(0, NAME_MAX)


func _base() -> String:
	return FIRESTORE_HOST + FIRESTORE_PATH % project_id


## Signs in anonymously once, then refreshes the token when it expires.
func _ensure_auth() -> bool:
	var now: float = Time.get_unix_time_from_system()
	if _id_token != "" and now < _token_expires - 60.0:
		return true
	var reply: Dictionary
	if _refresh_token != "":
		var form := "grant_type=refresh_token&refresh_token=" + _refresh_token.uri_encode()
		reply = await _request(HTTPClient.METHOD_POST, REFRESH_URL % api_key, form, false)
		if reply["ok"]:
			var j: Dictionary = reply["json"]
			_id_token = str(j.get("id_token", ""))
			_refresh_token = str(j.get("refresh_token", _refresh_token))
			_uid = str(j.get("user_id", _uid))
			_token_expires = now + float(j.get("expires_in", "3600"))
			_store_identity()
			return _id_token != ""
	reply = await _request(
		HTTPClient.METHOD_POST, AUTH_URL % api_key, {"returnSecureToken": true}, false
	)
	if not reply["ok"]:
		status_changed.emit("Нет связи с сервером")
		return false
	var data: Dictionary = reply["json"]
	_id_token = str(data.get("idToken", ""))
	_refresh_token = str(data.get("refreshToken", ""))
	_uid = str(data.get("localId", ""))
	_token_expires = now + float(data.get("expiresIn", "3600"))
	_store_identity()
	return _id_token != ""


func _store_identity() -> void:
	var saved: ConfigFile = LevelCatalog.data()
	saved.set_value("online", "uid", _uid)
	saved.set_value("online", "refresh_token", _refresh_token)
	LevelCatalog.commit()


## One HTTP call. `body` is a Dictionary (sent as JSON) or a String (form data).
## Returns {ok, code, json}.
func _request(method: int, url: String, body: Variant, auth: bool) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var headers: PackedStringArray = []
	var payload := ""
	if body is String:
		headers.append("Content-Type: application/x-www-form-urlencoded")
		payload = body
	elif method != HTTPClient.METHOD_GET:
		headers.append("Content-Type: application/json")
		payload = JSON.stringify(body)
	if auth:
		headers.append("Authorization: Bearer " + _id_token)
	var error: Error = http.request(url, headers, method, payload)
	if error != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "json": null}
	var result: Array = await http.request_completed
	http.queue_free()
	var code: int = result[1]
	var text: String = (result[3] as PackedByteArray).get_string_from_utf8()
	return {
		"ok": result[0] == HTTPRequest.RESULT_SUCCESS and code < 300,
		"code": code,
		"json": JSON.parse_string(text) if text != "" else null
	}
