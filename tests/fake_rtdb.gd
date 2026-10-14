extends RefCounted
## In-memory Realtime Database and a CoopTransport on top of it, for the co-op
## tests (tests/test_coop_net.gd). Never touches the network. It mimics what the
## protocol relies on: multi-path updates, create-if-absent (412), server
## timestamps, and SSE-style stream events (put / patch, a full "put /" snapshot
## on every (re)connect, the orderBy=$key&startAt filter). It does NOT check
## security rules: those are tested in firebase/rules-tests on the emulator.


class FakeServer:
	extends RefCounted
	var tree := RtdbTree.new()
	var clients: Array = []
	var now_ms: int = 1700000000000
	var writes: int = 0

	func get_at(path: String) -> Variant:
		return tree.get_at(path)

	## Applies {path: value} atomically; null deletes. `only` is a client that
	## does not hear its own stream (never used: a client hears itself, like a real one).
	func apply(changes: Dictionary) -> void:
		writes += 1
		for path in changes.keys():
			tree.apply("put", str(path), _resolve(changes[path]))
		for client in clients:
			client._on_server_change(changes)

	func _resolve(value: Variant) -> Variant:
		if value is Dictionary:
			if (value as Dictionary).size() == 1 and value.get(".sv") == "timestamp":
				return now_ms
			var out: Dictionary = {}
			for key in (value as Dictionary).keys():
				out[key] = _resolve((value as Dictionary)[key])
			return out
		return value


class FakeTransport:
	extends CoopTransport
	## Every transport made, so the test can free the nodes at the end.
	static var all: Array = []

	var server: FakeServer = null
	var user_id: String = ""
	## false: no network at all (requests fail, the stream is silent).
	var online: bool = true
	## Stream events wait in `inbox` until deliver() (simulates latency).
	var hold: bool = false
	var inbox: Array = []
	var listen_path: String = ""
	var listen_query: Dictionary = {}
	var pending: Dictionary = {}
	var listens: Array[Dictionary] = []  # every listen() call, for assertions
	var queries_seen: int = 0

	func _init() -> void:
		all.append(self)

	func uid() -> String:
		return user_id

	func is_ready() -> bool:
		return user_id != ""

	func read(path: String) -> Dictionary:
		if not online:
			return _down()
		return {"ok": true, "code": 200, "network": false, "value": server.get_at(path)}

	func write(path: String, value: Variant, if_absent: bool = false) -> Dictionary:
		if not online:
			return _down()
		if if_absent and server.get_at(path) != null:
			return {"ok": false, "code": 412, "network": false, "value": null}
		server.apply({path: value})
		return {"ok": true, "code": 204, "network": false, "value": null}

	func update(changes: Dictionary) -> Dictionary:
		if not online:
			return _down()
		server.apply(changes)
		return {"ok": true, "code": 204, "network": false, "value": null}

	func queue_update(changes: Dictionary) -> void:
		for key in changes.keys():
			pending[key] = changes[key]
		if online:
			flush()

	func flush() -> Dictionary:
		if not online:
			return _down()
		if not pending.is_empty():
			var batch: Dictionary = pending
			pending = {}
			server.apply(batch)
		return {"ok": true, "code": 204, "network": false, "value": null}

	func listen(path: String, query: Dictionary = {}) -> void:
		listen_path = path
		listen_query = query.duplicate()
		listens.append({"path": path, "query": query.duplicate()})
		if online:
			stream_state.emit("open")
			_emit("put", "/", _snapshot())

	func update_query(query: Dictionary) -> void:
		listen_query = query.duplicate()
		queries_seen += 1

	func stop_listen() -> void:
		listen_path = ""
		stream_state.emit("closed")

	## Network goes away / comes back (a new connection, like SSE reconnect).
	func set_online(value: bool) -> void:
		if value == online:
			return
		online = value
		if not online:
			stream_state.emit("reconnecting")
			return
		if listen_path != "":
			stream_state.emit("open")
			_emit("put", "/", _snapshot())
		flush()

	func deliver() -> void:
		var events: Array = inbox
		inbox = []
		for event in events:
			stream_event.emit(event[0], event[1], event[2])

	func _down() -> Dictionary:
		return {"ok": false, "code": 0, "network": true, "value": null}

	func _emit(kind: String, path: String, data: Variant) -> void:
		if hold:
			inbox.append([kind, path, data])
		else:
			stream_event.emit(kind, path, data)

	func _start_key() -> String:
		var raw: String = str(listen_query.get("startAt", ""))
		return raw.trim_prefix('"').trim_suffix('"')

	## The listened location as the server would send it now (with the filter).
	func _snapshot() -> Variant:
		var value: Variant = server.get_at(listen_path)
		var start: String = _start_key()
		if start == "" or not value is Dictionary:
			return value
		var out: Dictionary = {}
		for key in (value as Dictionary).keys():
			if str(key) >= start:
				out[key] = (value as Dictionary)[key]
		return out if not out.is_empty() else null

	func _on_server_change(changes: Dictionary) -> void:
		if listen_path == "" or not online:
			return
		var relative: Dictionary = {}
		var prefix: String = listen_path + "/"
		for path in changes.keys():
			var p: String = str(path)
			if p == listen_path or listen_path.begins_with(p + "/") or p == "":
				_emit("put", "/", _snapshot())  # a parent changed: full snapshot
				return
			if p.begins_with(prefix):
				var rel: String = p.substr(prefix.length())
				var start: String = _start_key()
				if start != "" and rel.get_slice("/", 0) < start:
					continue
				relative[rel] = server.get_at(p)
		if relative.is_empty():
			return
		if changes.size() == 1:
			var only: String = relative.keys()[0]
			_emit("put", "/" + only, relative[only])
		else:
			_emit("patch", "/", relative)
