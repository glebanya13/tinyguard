class_name FirestoreClient
extends RefCounted
## Cloud Firestore REST v1 (documents.get / commit / delete / runQuery) and
## callable Cloud Functions over HTTPS, signed with AuthService's id token.
## Values are converted between Godot types and Firestore's typed JSON here.
## Transient failures are retried with backoff; a 401 refreshes the token once.

const HOST := "https://firestore.googleapis.com/v1"
const ROOT := "projects/%s/databases/(default)/documents"
const FUNCTIONS_URL := "https://%s-%s.cloudfunctions.net/%s"
const MAX_ATTEMPTS := 3
const BACKOFF_SECONDS := 0.8

var project_id: String = ""
var functions_region: String = "europe-west1"
var transport: HttpTransport = null
var auth: AuthService = null
## 0 makes retries immediate (tests).
var backoff_scale: float = 1.0


## Full resource name of a document ("users/abc" -> "projects/p/.../users/abc").
func doc_name(path: String) -> String:
	return (ROOT % project_id) + "/" + path


func doc_url(path: String) -> String:
	return HOST + "/" + doc_name(path)


## {"ok", "code", "missing" (404), "fields" (decoded Dictionary), "update_time", "network"}.
func get_doc(path: String) -> Dictionary:
	var reply: Dictionary = await request(HTTPClient.METHOD_GET, doc_url(path), null, true)
	var json: Dictionary = reply["json"] if reply["json"] is Dictionary else {}
	reply["missing"] = int(reply["code"]) == 404
	reply["fields"] = decode_fields(json.get("fields", {})) if reply["ok"] else {}
	reply["update_time"] = str(json.get("updateTime", ""))
	return reply


func delete_doc(path: String) -> Dictionary:
	return await request(HTTPClient.METHOD_DELETE, doc_url(path), null, true)


## documents:commit with the given writes (atomic).
func commit(writes: Array) -> Dictionary:
	var url: String = HOST + "/" + (ROOT % project_id) + ":commit"
	return await request(HTTPClient.METHOD_POST, url, {"writes": writes}, true)


## Structured query under `parent` ("" = root, else e.g. "leaderboards/level_1").
func run_query(parent: String, query: Dictionary, signed: bool) -> Dictionary:
	var base: String = HOST + "/" + (ROOT % project_id)
	var url: String = (base + "/" + parent if parent != "" else base) + ":runQuery"
	return await request(HTTPClient.METHOD_POST, url, {"structuredQuery": query}, signed)


## Calls an HTTPS callable function. {"ok", "result", "reason", "status", "network"}.
func call_function(name: String, data: Dictionary) -> Dictionary:
	var url: String = FUNCTIONS_URL % [functions_region, project_id, name]
	var reply: Dictionary = await request(HTTPClient.METHOD_POST, url, {"data": data}, true)
	var parsed: Dictionary = parse_callable_reply(reply)
	parsed["network"] = reply.get("network", false)
	return parsed


## One request with retries. `body` is null or a Dictionary (sent as JSON).
func request(method: int, url: String, body: Variant, signed: bool) -> Dictionary:
	var reply: Dictionary = {}
	var refreshed := false
	var attempt: int = 0
	while attempt < MAX_ATTEMPTS:
		if attempt > 0 and backoff_scale > 0.0:
			var delay: float = BACKOFF_SECONDS * pow(2.0, attempt - 1) * randf_range(0.8, 1.2)
			await transport.get_tree().create_timer(delay * backoff_scale).timeout
		var headers := PackedStringArray()
		if body != null:
			headers.append("Content-Type: application/json")
		if signed:
			headers.append("Authorization: Bearer " + auth.id_token())
		var payload: String = JSON.stringify(body) if body != null else ""
		reply = await transport.send(method, url, headers, payload)
		if int(reply["code"]) == 401 and signed and not refreshed:
			refreshed = true
			auth.invalidate_token()
			var again: Dictionary = await auth.ensure_token(false)
			if not again["ok"]:
				break
			continue  # the retry with a new token does not count as an attempt
		if not HttpTransport.is_transient(reply) or _is_app_error(reply):
			break
		attempt += 1
	return reply


## A deliberate answer of our functions (e.g. 429 rate_limited): do not retry.
static func _is_app_error(reply: Dictionary) -> bool:
	var json: Variant = reply.get("json")
	if not json is Dictionary or not (json as Dictionary).get("error") is Dictionary:
		return false
	var details: Variant = (json["error"] as Dictionary).get("details")
	return details is Dictionary and (details as Dictionary).has("reason")


## Callable protocol reply -> {"ok", "result", "reason", "status"}. Errors come
## as {"error": {"status": "ALREADY_EXISTS", "message", "details": {"reason"}}}.
static func parse_callable_reply(reply: Dictionary) -> Dictionary:
	var json: Dictionary = reply.get("json") if reply.get("json") is Dictionary else {}
	if reply.get("ok", false) and json.has("result"):
		return {"ok": true, "result": json["result"], "reason": "", "status": "OK"}
	var error: Dictionary = json.get("error") if json.get("error") is Dictionary else {}
	var details: Dictionary = error.get("details") if error.get("details") is Dictionary else {}
	var status: String = str(error.get("status", ""))
	var reason: String = str(details.get("reason", ""))
	if reason == "":
		if HttpTransport.is_transient(reply):
			reason = "offline" if reply.get("network", false) else "unavailable"
		elif int(reply.get("code", 0)) == 404:
			reason = "unavailable"  # function not deployed
		else:
			reason = "server"
	return {"ok": false, "result": null, "reason": reason, "status": status}


static func encode_value(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_BOOL:
			return {"booleanValue": value}
		TYPE_INT:
			return {"integerValue": str(value)}
		TYPE_FLOAT:
			return {"doubleValue": value}
		TYPE_STRING, TYPE_STRING_NAME:
			return {"stringValue": str(value)}
		TYPE_DICTIONARY:
			return {"mapValue": {"fields": encode_fields(value)}}
		TYPE_ARRAY:
			var values: Array = []
			for item: Variant in value:
				values.append(encode_value(item))
			return {"arrayValue": {"values": values}}
	return {"nullValue": null}


static func encode_fields(data: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in data:
		out[str(key)] = encode_value(data[key])
	return out


## Typed Firestore value -> Godot value. Timestamps become unix seconds (int).
static func decode_value(value: Variant) -> Variant:
	if not value is Dictionary:
		return null
	var v: Dictionary = value
	if v.has("booleanValue"):
		return bool(v["booleanValue"])
	if v.has("integerValue"):
		return int(str(v["integerValue"]))
	if v.has("doubleValue"):
		return float(v["doubleValue"])
	if v.has("stringValue"):
		return str(v["stringValue"])
	if v.has("timestampValue"):
		return parse_timestamp(str(v["timestampValue"]))
	if v.has("mapValue"):
		return decode_fields((v["mapValue"] as Dictionary).get("fields", {}))
	if v.has("arrayValue"):
		var out: Array = []
		for item: Variant in (v["arrayValue"] as Dictionary).get("values", []):
			out.append(decode_value(item))
		return out
	return null


static func decode_fields(fields: Variant) -> Dictionary:
	var out := {}
	if fields is Dictionary:
		for key: Variant in fields:
			out[str(key)] = decode_value(fields[key])
	return out


## "2026-10-14T12:30:00.123456Z" -> unix seconds.
static func parse_timestamp(text: String) -> int:
	var plain: String = text.get_slice(".", 0).trim_suffix("Z")
	return Time.get_unix_time_from_datetime_string(plain)
