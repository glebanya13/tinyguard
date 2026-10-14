class_name SseParser
extends RefCounted
## Incremental parser of a Server-Sent-Events stream (text/event-stream) as sent
## by the Realtime Database REST API. Chunks may split an event, a line or a
## UTF-8 character anywhere; only complete events are returned.
## Never logs: payloads can carry room data.

var _buffer := PackedByteArray()


## Adds a chunk; returns the complete events: [{"event": String, "data": String}].
func feed(chunk: PackedByteArray) -> Array[Dictionary]:
	_buffer.append_array(chunk)
	_normalize_newlines()
	var events: Array[Dictionary] = []
	while true:
		var cut: int = _find_blank_line()
		if cut < 0:
			break
		var block: String = _buffer.slice(0, cut).get_string_from_utf8()
		_buffer = _buffer.slice(cut + 2)
		var event: Dictionary = _parse_block(block)
		if not event.is_empty():
			events.append(event)
	return events


func reset() -> void:
	_buffer = PackedByteArray()


## Decodes the JSON payload of an event the way RtdbClient needs it:
## {"ok", "kind": "put"|"patch"|"keep-alive"|"cancel"|"auth_revoked"|"unknown",
## "path": String, "data": Variant}. put/patch carry {"path", "data"}.
static func decode(event: Dictionary) -> Dictionary:
	var kind: String = str(event.get("event", ""))
	var raw: String = str(event.get("data", ""))
	match kind:
		"keep-alive":
			return {"ok": true, "kind": kind, "path": "", "data": null}
		"cancel", "auth_revoked":
			return {"ok": true, "kind": kind, "path": "", "data": _parse(raw)}
		"put", "patch":
			var parsed: Variant = _parse(raw)
			if not parsed is Dictionary or not (parsed as Dictionary).has("path"):
				return {"ok": false, "kind": kind, "path": "", "data": null}
			var body: Dictionary = parsed
			if kind == "patch" and not body.get("data") is Dictionary:
				return {"ok": false, "kind": kind, "path": "", "data": null}
			return {"ok": true, "kind": kind, "path": str(body["path"]), "data": body.get("data")}
	return {"ok": true, "kind": "unknown", "path": "", "data": null}


## "\r\n" and a lone "\r" become "\n". A "\r" at the very end stays: the next
## chunk may start with "\n".
func _normalize_newlines() -> void:
	var n: int = _buffer.size()
	var out := PackedByteArray()
	out.resize(0)
	var i: int = 0
	while i < n:
		var c: int = _buffer[i]
		if c == 13:
			if i + 1 >= n:
				out.append(13)
			elif _buffer[i + 1] == 10:
				pass  # the "\n" that follows is kept
			else:
				out.append(10)
		else:
			out.append(c)
		i += 1
	_buffer = out


## Index of the first "\n\n", or -1.
func _find_blank_line() -> int:
	for i in range(_buffer.size() - 1):
		if _buffer[i] == 10 and _buffer[i + 1] == 10:
			return i
	return -1


func _parse_block(block: String) -> Dictionary:
	var event_name := ""
	var data_lines: Array[String] = []
	for line in block.split("\n"):
		if line == "" or line.begins_with(":"):
			continue
		var colon: int = line.find(":")
		var field: String = line if colon < 0 else line.substr(0, colon)
		var value: String = "" if colon < 0 else line.substr(colon + 1)
		if value.begins_with(" "):
			value = value.substr(1)
		if field == "event":
			event_name = value
		elif field == "data":
			data_lines.append(value)
	if event_name == "" and data_lines.is_empty():
		return {}
	return {"event": event_name if event_name != "" else "message", "data": "\n".join(data_lines)}


## JSON without the engine's error print for broken input (null on failure).
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data
