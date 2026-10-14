# gdlint:disable=max-returns
class_name RtdbClient
extends CoopTransport
## Realtime Database over its REST API with the low-level HTTPClient (no SDK, no
## plugin; docs/MULTIPLAYER.md section 3.1). HTTPRequest cannot stream, so:
## - ONE stream: GET with "Accept: text/event-stream", followed through 307
##   redirects, parsed by SseParser (put / patch / keep-alive / cancel /
##   auth_revoked). It reconnects with backoff and jitter, treats silence longer
##   than KEEPALIVE_TIMEOUT as a dead connection, and renews the token on
##   auth_revoked. Each connection is 1 of the 100 Spark connections.
## - ONE persistent writer connection (keep-alive): requests are serialized, so
##   the 3.5 KB TLS handshake is paid once, not per write. queue_update() merges
##   changes made within FLUSH_INTERVAL into one multi-path PATCH. Writes use
##   print=silent (204, no echo of the data, which would count as download).
## Requests are signed with ?auth=<idToken> from AuthService. Tokens, URLs with
## tokens, room data and replies are never logged. Nothing here runs without
## a database URL (firebase.cfg "database_url"): the game stays offline.

## A queued request finished (internal: waiters check their own job).
signal job_finished

const KEEPALIVE_TIMEOUT := 60.0
const FLUSH_INTERVAL := 0.2
const CONNECT_TIMEOUT := 15.0
const REQUEST_TIMEOUT := 15.0
const BACKOFF_FIRST := 0.5
const BACKOFF_MAX := 30.0
const MAX_ATTEMPTS := 3
const MAX_REDIRECTS := 3
## A reply to a read/write larger than this is dropped (rooms are tiny).
const MAX_REPLY_BYTES := 262144
## Token problems that will not heal by retrying.
const FATAL_AUTH: Array[String] = ["session_lost", "disabled", "no_session", "not_configured"]

var auth: AuthService = null
## Multiplies every wait (0 = no backoff, for tests).
var backoff_scale: float = 1.0

var _host: String = ""
var _port: int = 443
var _tls: bool = true
## Extra query parameters on every request (e.g. "ns" for the local emulator).
var _base_query: Dictionary = {}

var _jobs: Array[Dictionary] = []
var _pumping: bool = false
var _writer := HTTPClient.new()
var _writer_target: Array = []  # [host, port, tls] of the live writer connection
var _pending: Dictionary = {}
var _flush_in: float = -1.0
var _flushing: bool = false

var _stream_gen: int = 0
var _stream_path: String = ""
var _stream_query: Dictionary = {}
var _stream_running: bool = false


## "https://x.firebaseio.com", or "http://127.0.0.1:9000?ns=demo-x" for the emulator.
## Returns false for an unusable URL.
func configure(database_url: String, auth_service: AuthService) -> bool:
	auth = auth_service
	_host = ""
	_base_query = {}
	var url: String = database_url.strip_edges()
	var scheme_end: int = url.find("://")
	if scheme_end < 0:
		return false
	_tls = url.substr(0, scheme_end) == "https"
	if not _tls and url.substr(0, scheme_end) != "http":
		return false
	var rest: String = url.substr(scheme_end + 3)
	var query_at: int = rest.find("?")
	if query_at >= 0:
		for pair in rest.substr(query_at + 1).split("&"):
			var kv: PackedStringArray = pair.split("=", true, 1)
			if kv.size() == 2:
				_base_query[kv[0]] = kv[1].uri_decode()
		rest = rest.substr(0, query_at)
	rest = rest.trim_suffix("/")
	var colon: int = rest.rfind(":")
	_port = 443 if _tls else 80
	if colon >= 0:
		_port = int(rest.substr(colon + 1))
		rest = rest.substr(0, colon)
	_host = rest
	return _host != ""


func uid() -> String:
	return auth.uid if auth != null else ""


func is_ready() -> bool:
	return _host != "" and auth != null and auth.is_configured() and auth.uid != ""


## "/path.json?auth=...&..." for a database path; `query` values are raw and get
## URL-encoded. Public for tests; the result holds the token: never log it.
func build_request_path(path: String, query: Dictionary = {}) -> String:
	var params: Array[String] = []
	var token: String = auth.id_token() if auth != null else ""
	if token != "":
		params.append("auth=" + token.uri_encode())
	for key in _base_query.keys():
		params.append("%s=%s" % [key, str(_base_query[key]).uri_encode()])
	for key in query.keys():
		params.append("%s=%s" % [key, str(query[key]).uri_encode()])
	return "/" + path.trim_prefix("/").trim_suffix("/") + ".json?" + "&".join(params)


func read(path: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, path, null, {}, false, false)


func write(path: String, value: Variant, if_absent: bool = false) -> Dictionary:
	return await _request(HTTPClient.METHOD_PUT, path, value, {}, true, if_absent)


func update(changes: Dictionary) -> Dictionary:
	return await _request(HTTPClient.METHOD_PATCH, "", changes, {}, true, false)


func queue_update(changes: Dictionary) -> void:
	for key in changes.keys():
		_pending[key] = changes[key]
	if _flush_in < 0.0:
		_flush_in = FLUSH_INTERVAL * backoff_scale


func flush() -> Dictionary:
	_flush_in = -1.0
	while _flushing:
		await job_finished
	if _pending.is_empty():
		return {"ok": true, "code": 204, "network": false, "value": null}
	_flushing = true
	var batch: Dictionary = _pending
	_pending = {}
	var reply: Dictionary = await update(batch)
	_flushing = false
	if not reply["ok"]:
		if HttpTransport.is_transient(reply):
			# Keep the batch; changes queued meanwhile are newer and win.
			for key in batch.keys():
				if not _pending.has(key):
					_pending[key] = batch[key]
			_flush_in = maxf(FLUSH_INTERVAL, 1.0) * backoff_scale
		else:
			write_failed.emit(int(reply["code"]))
	job_finished.emit()
	return reply


func listen(path: String, query: Dictionary = {}) -> void:
	stop_listen()
	_stream_path = path
	_stream_query = query.duplicate()
	_stream_gen += 1
	_stream_running = true
	_stream_loop(_stream_gen)


func update_query(query: Dictionary) -> void:
	_stream_query = query.duplicate()


func stop_listen() -> void:
	if _stream_running:
		_stream_running = false
		_stream_gen += 1
		stream_state.emit("closed")


func _process(delta: float) -> void:
	if _flush_in >= 0.0:
		_flush_in -= delta
		if _flush_in <= 0.0 and not _flushing:
			flush()


func _exit_tree() -> void:
	_stream_gen += 1
	_stream_running = false
	_writer.close()


# --- Writer: one persistent connection, requests one at a time ---------------


## {"ok", "code", "network", "value"}. `signed_write` adds print=silent.
func _request(
	method: int, path: String, body: Variant, query: Dictionary, signed_write: bool, if_absent: bool
) -> Dictionary:
	var job := {
		"method": method,
		"path": path,
		"body": "" if body == null and method == HTTPClient.METHOD_GET else JSON.stringify(body),
		"query": query.duplicate(),
		"silent": signed_write,
		"if_absent": if_absent,
		"done": false,
		"reply": {},
	}
	_jobs.append(job)
	if not _pumping:
		_pump()
	while not job["done"]:
		await job_finished
	return job["reply"]


func _pump() -> void:
	_pumping = true
	while not _jobs.is_empty():
		var job: Dictionary = _jobs.pop_front()
		job["reply"] = await _run_job(job)
		job["done"] = true
		job_finished.emit()
	_pumping = false


func _run_job(job: Dictionary) -> Dictionary:
	var reply: Dictionary = _failure(0, true)
	var refreshed := false
	var redirects: int = 0
	var attempt: int = 0
	while attempt < MAX_ATTEMPTS:
		if attempt > 0:
			await _backoff(attempt)
		var token: Dictionary = await auth.ensure_token(false)
		if not token["ok"]:
			var fatal: bool = FATAL_AUTH.has(str(token["error"]))
			return _failure(401 if fatal else 0, not fatal)
		var query: Dictionary = (job["query"] as Dictionary).duplicate()
		if job["silent"] and not job["if_absent"]:  # the server refuses silent + if-match
			query["print"] = "silent"
		var headers := PackedStringArray()
		if job["body"] != "":
			headers.append("Content-Type: application/json")
		if job["if_absent"]:
			headers.append("if-match: null_etag")
		var request_path: String = build_request_path(str(job["path"]), query)
		reply = await _exchange(int(job["method"]), request_path, headers, str(job["body"]))
		var code: int = int(reply["code"])
		if code == 401 and not refreshed:
			refreshed = true
			auth.invalidate_token()
			continue  # the retry with a new token is not an attempt
		if reply.has("location") and redirects < MAX_REDIRECTS:
			redirects += 1
			if _follow_location(str(reply["location"])):
				continue
		if not HttpTransport.is_transient(reply):
			break
		attempt += 1
	reply.erase("location")
	return reply


## One request on the persistent connection (connecting first if needed).
func _exchange(
	method: int, request_path: String, headers: PackedStringArray, body: String
) -> Dictionary:
	var target: Array = [_host, _port, _tls]
	if _writer.get_status() != HTTPClient.STATUS_CONNECTED or _writer_target != target:
		_writer.close()
		if not await _connect(_writer, _host, _port, _tls):
			return _failure(0, true)
		_writer_target = target
	var err: Error = _writer.request(method, request_path, headers, body)
	if err != OK:
		_writer.close()
		return _failure(0, true)
	var deadline: int = Time.get_ticks_msec() + int(REQUEST_TIMEOUT * 1000.0)
	while _writer.get_status() == HTTPClient.STATUS_REQUESTING:
		_writer.poll()
		if Time.get_ticks_msec() > deadline:
			_writer.close()
			return _failure(0, true)
		await get_tree().process_frame
	if not _writer.has_response():
		_writer.close()  # an idle keep-alive connection the server dropped
		return _failure(0, true)
	var code: int = _writer.get_response_code()
	var location := ""
	for header in _writer.get_response_headers():
		if str(header).to_lower().begins_with("location:"):
			location = str(header).substr(9).strip_edges()
	var bytes := PackedByteArray()
	while _writer.get_status() == HTTPClient.STATUS_BODY:
		_writer.poll()
		var chunk: PackedByteArray = _writer.read_response_body_chunk()
		if chunk.is_empty():
			if Time.get_ticks_msec() > deadline:
				_writer.close()
				return _failure(0, true)
			await get_tree().process_frame
		else:
			bytes.append_array(chunk)
			if bytes.size() > MAX_REPLY_BYTES:
				_writer.close()
				return _failure(0, true)
	var text: String = bytes.get_string_from_utf8()
	var reply: Dictionary = {
		"ok": code >= 200 and code < 300,
		"code": code,
		"network": false,
		"value": JSON.parse_string(text) if text != "" else null,
	}
	if location != "" and code >= 300 and code < 400:
		reply["location"] = location
	return reply


func _failure(code: int, network: bool) -> Dictionary:
	return {"ok": false, "code": code, "network": network, "value": null}


## Follows a redirect of the writer connection: only to an acceptable host.
func _follow_location(location: String) -> bool:
	var host: String = redirect_host(location, _tls, _host)
	if host == "":
		return false
	_host = host
	return true


## The host a redirect Location may lead to, or "": our token must never go to a
## foreign host. Allowed: the configured host itself, or a plain host name under
## *.firebasedatabase.app / *.firebaseio.com, over https when we use https.
static func redirect_host(location: String, tls: bool, configured_host: String) -> String:
	var scheme_end: int = location.find("://")
	if scheme_end < 0:
		return ""
	if tls and location.substr(0, scheme_end) != "https":
		return ""
	var rest: String = location.substr(scheme_end + 3)
	var host: String = rest.get_slice("/", 0).get_slice("?", 0).to_lower()
	if host == "":
		return ""
	if host == configured_host.to_lower():
		return host
	for i in host.length():
		if not "abcdefghijklmnopqrstuvwxyz0123456789-.".contains(host[i]):
			return ""  # no user info, ports, spaces or other tricks
	if host.ends_with(".firebasedatabase.app") or host.ends_with(".firebaseio.com"):
		return host
	return ""


func _backoff(attempt: int) -> void:
	if backoff_scale <= 0.0:
		return
	var seconds: float = BACKOFF_FIRST * pow(2.0, attempt - 1) * randf_range(0.8, 1.2)
	await get_tree().create_timer(seconds * backoff_scale).timeout


## Opens a connection and waits for it. False on failure or timeout.
func _connect(client: HTTPClient, host: String, port: int, tls: bool) -> bool:
	var options: TLSOptions = TLSOptions.client() if tls else null
	if client.connect_to_host(host, port, options) != OK:
		return false
	var deadline: int = Time.get_ticks_msec() + int(CONNECT_TIMEOUT * 1000.0)
	while true:
		client.poll()
		var status: int = client.get_status()
		if status == HTTPClient.STATUS_CONNECTED:
			return true
		if status != HTTPClient.STATUS_CONNECTING and status != HTTPClient.STATUS_RESOLVING:
			return false
		if Time.get_ticks_msec() > deadline:
			client.close()
			return false
		await get_tree().process_frame
	return false


# --- Stream ------------------------------------------------------------------


## Runs until stop_listen()/listen() bumps the generation or the server refuses
## for good (cancel / permission denied / fatal auth).
func _stream_loop(gen: int) -> void:
	var failures: int = 0
	var first := true
	while gen == _stream_gen:
		stream_state.emit("connecting" if first else "reconnecting")
		first = false
		var token: Dictionary = await auth.ensure_token(false)
		if gen != _stream_gen:
			return
		var outcome := "retry"
		if token["ok"]:
			outcome = await _stream_once(gen)
		elif FATAL_AUTH.has(str(token["error"])):
			outcome = "fatal:auth"
		if gen != _stream_gen:
			return
		if outcome.begins_with("fatal:"):
			_stream_running = false
			_stream_gen += 1
			stream_error.emit(outcome.substr(6))
			stream_state.emit("closed")
			return
		if outcome == "opened_then_lost" or outcome == "revoked":
			failures = 0  # it worked for a while: start the backoff over
		if outcome == "revoked":
			auth.invalidate_token()
			continue  # reconnect at once with a new token
		failures += 1
		if backoff_scale > 0.0:
			var base: float = minf(BACKOFF_MAX, BACKOFF_FIRST * pow(2.0, failures - 1))
			await get_tree().create_timer(base * randf_range(0.8, 1.2) * backoff_scale).timeout


## One connection attempt. Returns "retry" (never opened), "opened_then_lost",
## "revoked" (auth_revoked) or "fatal:<reason>".
func _stream_once(gen: int) -> String:
	var client := HTTPClient.new()
	var host: String = _host
	var port: int = _port
	var tls: bool = _tls
	var redirects: int = 0
	var parser := SseParser.new()
	var result := "retry"
	while true:
		if not await _connect(client, host, port, tls) or gen != _stream_gen:
			client.close()
			return result
		var request_path: String = build_request_path(_stream_path, _stream_query)
		var headers := PackedStringArray(["Accept: text/event-stream", "Cache-Control: no-cache"])
		if client.request(HTTPClient.METHOD_GET, request_path, headers) != OK:
			client.close()
			return result
		var deadline: int = Time.get_ticks_msec() + int(REQUEST_TIMEOUT * 1000.0)
		while client.get_status() == HTTPClient.STATUS_REQUESTING:
			client.poll()
			if Time.get_ticks_msec() > deadline or gen != _stream_gen:
				client.close()
				return result
			await get_tree().process_frame
		if not client.has_response():
			client.close()
			return result
		var code: int = client.get_response_code()
		if code >= 300 and code < 400 and redirects < MAX_REDIRECTS:
			redirects += 1
			var location := ""
			for header in client.get_response_headers():
				if str(header).to_lower().begins_with("location:"):
					location = str(header).substr(9).strip_edges()
			client.close()
			var new_host: String = redirect_host(location, _tls, _host)
			if new_host == "":
				return "fatal:redirect"
			host = new_host
			continue  # connect to the new host and repeat the request
		if code == 401:
			auth.invalidate_token()
			client.close()
			return "retry"
		if code == 403:
			client.close()
			return "fatal:permission_denied"
		if code != 200:
			client.close()
			return "fatal:http_%d" % code if code >= 400 and code < 500 and code != 429 else "retry"
		break
	stream_state.emit("open")
	result = "opened_then_lost"
	var last_data: int = Time.get_ticks_msec()
	while gen == _stream_gen:
		client.poll()
		var status: int = client.get_status()
		if status != HTTPClient.STATUS_BODY:
			break  # the server closed the stream
		var chunk: PackedByteArray = client.read_response_body_chunk()
		if chunk.is_empty():
			if (Time.get_ticks_msec() - last_data) / 1000.0 > KEEPALIVE_TIMEOUT:
				break  # no keep-alive for too long: the connection is dead
			await get_tree().process_frame
			continue
		last_data = Time.get_ticks_msec()
		var parsed_events: Array[Dictionary] = parser.feed(chunk)
		if parser.overflowed:
			client.close()
			return "retry"  # an oversized event is not ours: start again
		for raw in parsed_events:
			var event: Dictionary = SseParser.decode(raw)
			if not event["ok"]:
				continue
			match str(event["kind"]):
				"put", "patch":
					stream_event.emit(event["kind"], event["path"], event["data"])
				"cancel":
					client.close()
					return "fatal:permission_denied"
				"auth_revoked":
					client.close()
					return "revoked"
	client.close()
	return result
