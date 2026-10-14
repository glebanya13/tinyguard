class_name HttpTransport
extends Node
## One HTTPS request at a time per call (a fresh HTTPRequest child each), used
## by AuthService and FirestoreClient. Tests replace
## it with a fake that answers from a script and never touches the network.
## Nothing here is logged: requests carry tokens and private data.

const TIMEOUT := 10.0


## Returns {"ok": bool (2xx), "code": int (0 = no HTTP reply), "json": Variant,
## "network": bool (no reply at all: offline, DNS, TLS, timeout)}.
func send(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	var error: Error = http.request(url, headers, method, body)
	if error != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "json": null, "network": true}
	var result: Array = await http.request_completed
	http.queue_free()
	var code: int = result[1]
	var text: String = (result[3] as PackedByteArray).get_string_from_utf8()
	var network: bool = result[0] != HTTPRequest.RESULT_SUCCESS
	return {
		"ok": not network and code >= 200 and code < 300,
		"code": 0 if network else code,
		"json": JSON.parse_string(text) if text != "" else null,
		"network": network,
	}


## True for failures worth retrying: no reply, rate limiting, server errors.
static func is_transient(reply: Dictionary) -> bool:
	var code: int = int(reply.get("code", 0))
	return bool(reply.get("network", false)) or code == 0 or code == 429 or code >= 500
