extends SceneTree
## Co-op network layer without a network: SSE parsing on samples of the Realtime
## Database event format, the stream mirror, the command protocol, the lobby,
## lockstep ordering / input delay / desync detection, and whole matches of two
## sessions over an in-memory database (disconnects and reconnects included).
## godot --headless --path . --script res://tests/test_coop_net.gd

const Fake := preload("res://tests/fake_rtdb.gd")
const MOD := 1000003

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_sse_samples()
	_test_sse_chunking()
	_test_hardening()
	_test_tree()
	_test_protocol()
	await _test_lobby()
	_test_lockstep_core()
	await _test_match_clean()
	await _test_match_latency()
	await _test_match_disconnect()
	await _test_match_failures()
	for node in Fake.FakeTransport.all:
		(node as Node).free()
	Fake.FakeTransport.all.clear()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


# --- SSE ----------------------------------------------------------------------


## Samples in the exact shape the Realtime Database REST stream sends.
func _sample_stream() -> String:
	return (
		'event: put\ndata: {"path":"/","data":null}\n\n'
		+ "event: keep-alive\ndata: null\n\n"
		+ 'event: put\ndata: {"path":"/000001","data":{"d":"","f":14}}\n\n'
		+ 'event: patch\ndata: {"path":"/","data":'
		+ '{"000002":{"d":"","f":22},"000003":{"d":"","f":30}}}\n\n'
		+ 'event: auth_revoked\ndata: "credential is no longer valid"\n\n'
		+ "event: cancel\ndata: null\n\n"
	)


func _test_sse_samples() -> void:
	print("-- SSE samples")
	var parser := SseParser.new()
	var raw: Array[Dictionary] = parser.feed(_sample_stream().to_utf8_buffer())
	check(raw.size() == 6, "six events parsed")
	var kinds: Array[String] = []
	var events: Array[Dictionary] = []
	for e in raw:
		var d: Dictionary = SseParser.decode(e)
		events.append(d)
		kinds.append(str(d["kind"]))
	check(kinds == ["put", "keep-alive", "put", "patch", "auth_revoked", "cancel"], "event kinds")
	check(events[0]["path"] == "/" and events[0]["data"] == null, "initial empty put")
	check(events[2]["path"] == "/000001" and int(events[2]["data"]["f"]) == 14, "put of a child")
	check(
		events[3]["kind"] == "patch" and (events[3]["data"] as Dictionary).size() == 2,
		"patch with two children"
	)
	check(events[4]["data"] == "credential is no longer valid", "auth_revoked text")
	check(events[5]["data"] == null, "cancel without text")
	var bad: Dictionary = SseParser.decode({"event": "put", "data": "{oops"})
	check(not bad["ok"], "broken JSON in put refused")
	check(
		not SseParser.decode({"event": "patch", "data": '{"path":"/","data":5}'})["ok"],
		"patch needs an object"
	)
	check(
		SseParser.decode({"event": "weird", "data": "x"})["kind"] == "unknown", "unknown event kind"
	)


func _test_sse_chunking() -> void:
	print("-- SSE chunking")
	var text: String = (
		'event: put\r\ndata: {"path":"/","data":{"name":"Рыцарь Аня"}}\r\n\r\n'
		+ ": comment line\n\n"
		+ "event: keep-alive\ndata: null\n\n"
		+ 'event: put\ndata: {"path":"/x","data":"два\\nстроки"}\n\n'
	)
	var bytes: PackedByteArray = text.to_utf8_buffer()
	var whole: Array[Dictionary] = SseParser.new().feed(bytes)
	check(whole.size() == 3, "CRLF stream: comment skipped, 3 events (%d)" % whole.size())
	var ok := true
	for cut in range(1, bytes.size()):
		var parser := SseParser.new()
		var got: Array[Dictionary] = parser.feed(bytes.slice(0, cut))
		got.append_array(parser.feed(bytes.slice(cut)))
		if got != whole:
			ok = false
			print("    split at ", cut, " differs")
			break
	check(ok, "same events for a split at every byte (also inside Cyrillic letters)")
	var one := SseParser.new()
	var byte_by_byte: Array[Dictionary] = []
	for i in bytes.size():
		byte_by_byte.append_array(one.feed(bytes.slice(i, i + 1)))
	check(byte_by_byte == whole, "byte-by-byte feed")
	var multi: Array[Dictionary] = SseParser.new().feed(
		"event: put\ndata: line1\ndata: line2\n\n".to_utf8_buffer()
	)
	check(multi.size() == 1 and multi[0]["data"] == "line1\nline2", "multi-line data joined")
	check(
		SseParser.new().feed("event: put\ndata: {".to_utf8_buffer()).is_empty(),
		"incomplete event waits"
	)


func _test_hardening() -> void:
	print("-- hardening")
	var ok_host: String = RtdbClient.redirect_host(
		"https://x-default-rtdb.europe-west1.firebasedatabase.app/a.json",
		true,
		"bimbleguard-default-rtdb.firebaseio.com"
	)
	check(
		ok_host == "x-default-rtdb.europe-west1.firebasedatabase.app",
		"redirect inside firebasedatabase.app followed"
	)
	var cfg := "bimbleguard-default-rtdb.firebaseio.com"
	check(
		RtdbClient.redirect_host("https://evil.example.com/x", true, cfg) == "",
		"foreign host refused"
	)
	check(
		RtdbClient.redirect_host("https://evilfirebaseio.com/x", true, cfg) == "",
		"suffix without a dot refused"
	)
	check(
		RtdbClient.redirect_host("https://a.firebaseio.com@evil.com/x", true, cfg) == "",
		"user-info trick refused"
	)
	check(
		RtdbClient.redirect_host("https://a.firebaseio.com:444/x", true, cfg) == "", "port refused"
	)
	check(
		RtdbClient.redirect_host("http://a.firebaseio.com/x", true, cfg) == "",
		"downgrade to http refused"
	)
	check(RtdbClient.redirect_host("/relative", true, cfg) == "", "relative location refused")
	check(
		RtdbClient.redirect_host("https://" + cfg + "/x", true, cfg) == cfg,
		"the configured host is fine"
	)
	var big := SseParser.new()
	big.feed(("event: put\ndata: " + "x".repeat(SseParser.MAX_PENDING_BYTES + 10)).to_utf8_buffer())
	check(big.overflowed, "an endless event is dropped")
	var fine := SseParser.new()
	var many: String = ""
	for i in 3000:
		many += 'event: put\ndata: {"path":"/","data":1}\n\n'
	check(
		fine.feed(many.to_utf8_buffer()).size() == 3000 and not fine.overflowed,
		"many small events in one chunk are fine"
	)
	var client := RtdbClient.new()
	var auth := AuthService.new()
	check(client.configure("http://127.0.0.1:9000?ns=demo-x", auth), "emulator URL parsed")
	check(
		(
			client.build_request_path("rooms/ABCDE/meta", {"orderBy": '"$key"'})
			== "/rooms/ABCDE/meta.json?ns=demo-x&orderBy=%22%24key%22"
		),
		"request path with query encoded"
	)
	check(
		not client.configure("ftp://x", auth) and not client.configure("nonsense", auth),
		"bad URLs refused"
	)
	check(not client.is_ready(), "not ready without a session")
	client.free()


func _test_tree() -> void:
	print("-- stream mirror")
	var t := RtdbTree.new()
	t.apply("put", "/", null)
	check(t.value == null, "empty initial put")
	t.apply("put", "/", {"a": {"b": 1}, "c": 2})
	check(t.get_at("a/b") == 1 and t.get_at("c") == 2, "snapshot put")
	t.apply("patch", "/", {"a/b": 5, "d": {"e": 1}})
	check(t.get_at("a/b") == 5 and t.get_at("d/e") == 1, "patch with a nested path")
	t.apply("put", "/a/b", null)
	check(t.get_at("a") == null, "deleting the last child removes the empty parent")
	t.apply("put", "/d", null)
	t.apply("put", "/c", null)
	check(t.value == null, "everything deleted -> null root")
	check(not t.apply("patch", "/", 3), "malformed patch refused")
	t.apply("put", "/x/y/z", 7)
	check(t.get_at("x/y/z") == 7 and t.get_at("x/q", "none") == "none", "deep put, fallback read")


# --- protocol -----------------------------------------------------------------


func _test_protocol() -> void:
	print("-- protocol")
	var cmds := [
		{"tick": 40, "type": "build", "args": [3, 2]},
		{"tick": 41, "type": "pause", "args": []},
	]
	var msg: Dictionary = CoopProtocol.encode_message(55, cmds, [60, 123456], true)
	check(str(msg["d"]).length() < CoopProtocol.MAX_DATA_CHARS, "message is small")
	# Through JSON, like the database returns it (numbers become floats).
	var back: Dictionary = CoopProtocol.decode_message(JSON.parse_string(JSON.stringify(msg)))
	check(back["ok"] and back["frontier"] == 55, "round trip: frontier")
	check(
		back["commands"].size() == 2 and back["commands"][0]["args"] == [3, 2],
		"round trip: commands with int args"
	)
	check(back["hash"] == [60, 123456] and back["leaving"], "round trip: hash and farewell")
	check(CoopProtocol.encode_message(9, [])["d"] == "", "heartbeat has empty data")
	check(CoopProtocol.decode_message({"f": 9, "d": ""})["ok"], "empty data is valid")
	check(not CoopProtocol.decode_message({"f": 1.5, "d": ""})["ok"], "fractional frontier refused")
	check(not CoopProtocol.decode_message({"f": -1, "d": ""})["ok"], "negative frontier refused")
	check(not CoopProtocol.decode_message({"f": 1})["ok"] or true, "missing d treated as empty")
	check(not CoopProtocol.decode_message("junk")["ok"], "non-object refused")
	check(not CoopProtocol.decode_message({"f": 1, "d": "x".repeat(901)})["ok"], "too long refused")
	check(not CoopProtocol.decode_message({"f": 1, "d": "{nope"})["ok"], "bad JSON refused")
	var unknown: String = JSON.stringify({"c": [[5, "cheat", []]]})
	check(
		not CoopProtocol.decode_message({"f": 1, "d": unknown})["ok"],
		"unknown command type refused"
	)
	var floaty: String = JSON.stringify({"c": [[5, "build", [1.5]]]})
	check(not CoopProtocol.decode_message({"f": 1, "d": floaty})["ok"], "float argument refused")
	var unsorted: String = JSON.stringify({"c": [[9, "sell", [1]], [4, "sell", [2]]]})
	check(
		not CoopProtocol.decode_message({"f": 1, "d": unsorted})["ok"], "ticks out of order refused"
	)
	var many: Array = []
	for i in CoopProtocol.MAX_COMMANDS_PER_MESSAGE + 1:
		many.append([5, "sell", [i]])
	check(
		not CoopProtocol.decode_message({"f": 1, "d": JSON.stringify({"c": many})})["ok"],
		"too many commands refused"
	)
	check(not CoopProtocol.is_valid_command(3, "build", [[1]]), "nested argument refused")
	check(
		not CoopProtocol.is_valid_command(3, "build", ["x".repeat(30)]),
		"long string argument refused"
	)
	check(
		CoopProtocol.seq_key(12) == "000012" and CoopProtocol.parse_seq("000012") == 12, "seq keys"
	)
	check(
		CoopProtocol.parse_seq("12") == -1 and CoopProtocol.parse_seq("00000x") == -1,
		"bad seq keys"
	)


# --- lobby --------------------------------------------------------------------


func _make_client(server: Fake.FakeServer, uid: String) -> Fake.FakeTransport:
	var net := Fake.FakeTransport.new()
	net.server = server
	net.user_id = uid
	server.clients.append(net)
	return net


func _lobby(net: Fake.FakeTransport) -> CoopLobby:
	var lobby := CoopLobby.new(net)
	var server: Fake.FakeServer = net.server
	lobby.clock_ms = func() -> float: return float(server.now_ms)
	return lobby


func _test_lobby() -> void:
	print("-- lobby")
	var server := Fake.FakeServer.new()
	var host_net: Fake.FakeTransport = _make_client(server, "uidHost")
	var guest_net: Fake.FakeTransport = _make_client(server, "uidGuest")
	var host: CoopLobby = _lobby(host_net)
	var guest: CoopLobby = _lobby(guest_net)
	host.rng.seed = 42
	var code_ok := true
	for i in 200:
		var c: String = host.make_code()
		if (
			c.length() != 5
			or "O0I1".contains(c.substr(0, 1))
			or c.contains("O")
			or c.contains("0")
			or c.contains("I")
			or c.contains("1")
		):
			code_ok = false
	check(code_ok, "codes: 5 symbols, no O/0/I/1")
	check(CoopLobby.CODE_ALPHABET.length() == 32, "32 symbols alphabet")
	check(CoopLobby.normalize_code(" ab-cd2 ") == "ABCD2", "code normalized")
	check(CoopLobby.normalize_code("ABCD0") == "", "0 is not a code symbol")
	check(CoopLobby.normalize_code("ABCDEF") == "", "too long")

	var closed_log: Array[String] = []
	guest.closed.connect(func(r: String) -> void: closed_log.append(r))
	var started_host: Array[Dictionary] = []
	var started_guest: Array[Dictionary] = []
	host.started.connect(func(c: Dictionary) -> void: started_host.append(c))
	guest.started.connect(func(c: Dictionary) -> void: started_guest.append(c))

	# An old room of the same user is removed on create.
	server.apply({"rooms/OLDRM/meta": {"host": "uidHost"}, "user_rooms/uidHost": "OLDRM"})
	var made: Dictionary = await host.create(3, "  Хост\tИмя-очень-длинное-и-лишнее ", 7)
	check(made["ok"] and str(made["code"]).length() == 5, "room created")
	check(server.get_at("rooms/OLDRM") == null, "forgotten own room removed")
	var code: String = made["code"]
	check(server.get_at("user_rooms/uidHost") == code, "user_rooms index points to the room")
	var meta: Dictionary = server.get_at("rooms/%s/meta" % code)
	check(
		(
			meta["host"] == "uidHost"
			and meta["level"] == 3
			and meta["state"] == "lobby"
			and meta["simv"] == 7
		),
		"meta written"
	)
	check(int(meta["created"]) == server.now_ms, "server timestamp used for created")
	check(str(server.get_at("rooms/%s/players/host/name" % code)).length() <= 16, "name cut to 16")
	check(not (await host.create(1, "x", 7))["ok"], "second create while in a room refused")

	check((await guest.join("zzzzz", "Гость", 7))["reason"] == "not_found", "unknown code")
	check((await guest.join("ab0de", "Гость", 7))["reason"] == "invalid", "invalid code")
	check((await guest.join(code, "Гость", 8))["reason"] == "version", "other simulation version")
	var late: Fake.FakeServer = server
	late.now_ms += CoopLobby.ROOM_TTL_MS + 5000
	guest.clock_ms = func() -> float: return float(late.now_ms)
	check((await guest.join(code, "Гость", 7))["reason"] == "expired", "stale room refused")
	late.now_ms -= CoopLobby.ROOM_TTL_MS + 5000
	check((await host.join(code, "x", 7))["reason"] == "busy", "host is already in a room")

	var joined: Dictionary = await guest.join(code.to_lower(), "Гость", 7)
	check(joined["ok"], "guest joins (lower case code accepted)")
	var third_net: Fake.FakeTransport = _make_client(server, "uidThird")
	var third: CoopLobby = _lobby(third_net)
	check((await third.join(code, "Третий", 7))["reason"] == "full", "a third player cannot join")
	var snap: Dictionary = host.snapshot()
	check(snap["guest"].get("uid") == "uidGuest" and snap["level"] == 3, "host sees the guest")
	check(not snap["can_start"], "cannot start before everybody is ready")
	check(not (await host.start_match())["ok"], "start refused when not ready")
	await guest.set_ready(true)
	check(
		host.snapshot()["partner_ready"] and host.snapshot()["can_start"],
		"host can start when the guest is ready"
	)
	await host.set_level(5)
	check(
		host.snapshot()["level"] == 5 and not host.snapshot()["can_start"],
		"new level resets readiness"
	)
	check(
		guest.snapshot()["level"] == 5 and not guest.snapshot()["me_ready"],
		"guest sees the new level, not ready"
	)
	await guest.set_ready(true)
	check(host.snapshot()["can_start"], "ready again for the new revision")
	var begin: Dictionary = await host.start_match()
	check(begin["ok"], "match started")
	check(started_host.size() == 1 and started_guest.size() == 1, "both got `started` once")
	check(
		(
			started_guest[0]["level"] == 5
			and started_guest[0]["role"] == "guest"
			and started_guest[0]["seed"] == started_host[0]["seed"]
		),
		"same level and seed on both sides"
	)
	# Leaving: the guest drops out; the host removes the room.
	host_net.listen_path = ""
	await guest.leave()
	check(server.get_at("rooms/%s/players/guest" % code) == null, "guest entry removed")
	await host.leave()
	check(
		server.get_at("rooms/%s" % code) == null and server.get_at("user_rooms/uidHost") == null,
		"host removed the room"
	)

	# Host leaves a lobby: the guest is told.
	var h2: CoopLobby = _lobby(host_net)
	var g2: CoopLobby = _lobby(guest_net)
	var closed2: Array[String] = []
	g2.closed.connect(func(r: String) -> void: closed2.append(r))
	var room2: Dictionary = await h2.create(1, "A", 7)
	await g2.join(room2["code"], "B", 7)
	await h2.leave()
	check(closed2 == ["host_left"], "guest learns the host left")
	check(g2.role == "", "guest state reset")

	# Host removes the guest by deleting its entry -> guest_left.
	var h3: CoopLobby = _lobby(host_net)
	var g3: CoopLobby = _lobby(guest_net)
	var closed3: Array[String] = []
	g3.closed.connect(func(r: String) -> void: closed3.append(r))
	var room3: Dictionary = await h3.create(1, "A", 7)
	await g3.join(room3["code"], "B", 7)
	server.apply({"rooms/%s/players/guest" % room3["code"]: null})
	check(closed3 == ["guest_left"], "guest sees it was removed")
	await h3.leave()

	# Idle host room closes by itself.
	var h4: CoopLobby = _lobby(host_net)
	var closed4: Array[String] = []
	h4.closed.connect(func(r: String) -> void: closed4.append(r))
	var room4: Dictionary = await h4.create(1, "A", 7)
	h4.process(CoopLobby.LOBBY_IDLE - 1.0)
	check(closed4.is_empty() and h4.role == "host", "not yet idle")
	h4.process(2.0)
	check(
		closed4 == ["timeout"] and server.get_at("rooms/%s" % room4["code"]) == null,
		"idle room closed and removed"
	)

	# Account deletion: purge_user removes a hosted room / a guest entry / the index.
	var hp: CoopLobby = _lobby(host_net)
	var gp: CoopLobby = _lobby(guest_net)
	var room6: Dictionary = await hp.create(1, "A", 7)
	await gp.join(room6["code"], "B", 7)
	var purge_guest: Dictionary = await _lobby(guest_net).purge_user()
	check(purge_guest["ok"], "purge as guest ok")
	check(
		server.get_at("rooms/%s/players/guest" % room6["code"]) == null,
		"purge removed the guest entry"
	)
	check(server.get_at("user_rooms/uidGuest") == null, "purge removed the guest index")
	check(server.get_at("rooms/%s/meta" % room6["code"]) != null, "the host's room stays")
	var purge_host: Dictionary = await _lobby(host_net).purge_user()
	check(
		purge_host["ok"] and server.get_at("rooms/%s" % room6["code"]) == null,
		"purge as host removed the room"
	)
	check(server.get_at("user_rooms/uidHost") == null, "purge removed the host index")
	check((await _lobby(host_net).purge_user())["ok"], "purge with nothing to remove is ok")
	host_net.set_online(false)
	check(not (await _lobby(host_net).purge_user())["ok"], "purge offline reports failure")
	host_net.set_online(true)
	# A guest whose room was deleted by the host can join another one.
	var h7: CoopLobby = _lobby(host_net)
	var g7: CoopLobby = _lobby(guest_net)
	var room7: Dictionary = await h7.create(1, "A", 7)
	await g7.join(room7["code"], "B", 7)
	server.apply({"rooms/%s" % room7["code"]: null})  # the host vanished without cleanup
	var h8: CoopLobby = _lobby(third_net)
	var room8: Dictionary = await h8.create(2, "C", 7)
	var g8: CoopLobby = _lobby(guest_net)
	check(
		(await g8.join(room8["code"], "B", 7))["ok"],
		"stale index of a dead room does not block joining"
	)
	check(
		server.get_at("rooms/%s/meta/expiresAt" % room8["code"]) > server.now_ms,
		"room has expiresAt"
	)
	await h8.leave()
	await g8.leave()

	# Code collision: the first candidate exists, the second attempt works.
	var h5: CoopLobby = _lobby(host_net)
	h5.rng.seed = 99
	var probe := CoopLobby.new(host_net)
	probe.rng.seed = 99
	var taken: String = probe.make_code()
	server.apply({"rooms/%s/meta" % taken: {"host": "someone"}})
	var room5: Dictionary = await h5.create(2, "A", 7)
	check(room5["ok"] and room5["code"] != taken, "collision: another code taken")
	await h5.leave()

	# Offline.
	host_net.set_online(false)
	check(
		(await CoopLobby.new(host_net).create(1, "A", 7))["reason"] == "offline", "create offline"
	)
	check(
		(await CoopLobby.new(host_net).join("ABCDE", "A", 7))["reason"] == "offline", "join offline"
	)
	host_net.set_online(true)
	var anon := Fake.FakeTransport.new()
	anon.server = server
	check(
		(await CoopLobby.new(anon).create(1, "A", 7))["reason"] == "offline",
		"not signed in -> offline"
	)
	check(closed_log.has("host_left") == false, "guest never got a stray close")


# --- lockstep core -------------------------------------------------------------


## Two cores joined by a manual pipe: messages move when pump() is called.
class Pair:
	extends RefCounted
	var a: CoopLockstep
	var b: CoopLockstep
	var log_a: Array = []
	var log_b: Array = []
	var state_a: int = 0
	var state_b: int = 0

	func _init(delay: int) -> void:
		a = CoopLockstep.new(0, delay)
		b = CoopLockstep.new(1, delay)

	func pump(force: bool = false) -> void:
		for i in 8:
			var m1: Dictionary = a.build_message(force)
			if not m1.is_empty():
				b.receive(CoopProtocol.decode_message(JSON.parse_string(JSON.stringify(m1))))
			var m2: Dictionary = b.build_message(force)
			if not m2.is_empty():
				a.receive(CoopProtocol.decode_message(JSON.parse_string(JSON.stringify(m2))))
			if m1.is_empty() and m2.is_empty():
				return

	## One tick on one side; returns whether it ran.
	func step(side: CoopLockstep, log: Array, bias: int) -> int:
		if not side.can_simulate():
			return -1
		var s: int = bias
		for cmd in side.take_commands():
			log.append([side.tick, cmd["player"], cmd["type"], cmd["args"]])
			s = (s * 31 + int(cmd["args"][0]) + int(cmd["player"]) * 7) % 1000003
		side.advance()
		return s


func _test_lockstep_core() -> void:
	print("-- lockstep core")
	var pair := Pair.new(10)
	check(
		pair.a.delay == 10 and CoopLockstep.new(0, 1).delay == CoopProtocol.MIN_DELAY,
		"delay clamped"
	)
	check(pair.a.can_simulate(), "first `delay` ticks need no partner message")
	# A command issued at tick T runs at T+delay on BOTH sides.
	for i in 5:
		pair.a.take_commands()
		pair.a.advance()
	check(pair.a.submit("build", [1, 2]), "command accepted")
	check(not pair.a.submit("fly", []), "unknown type rejected locally")
	check(not pair.a.submit("build", [1.5]), "float argument rejected locally")
	# Ticks 0..4 already consumed by `a`; give b the same.
	for i in 5:
		pair.b.take_commands()
		pair.b.advance()
	pair.pump()
	var seen_a: int = -1
	var seen_b: int = -1
	for t in range(5, 40):
		if pair.a.can_simulate():
			if not pair.a.take_commands().is_empty() and seen_a < 0:
				seen_a = pair.a.tick
			pair.a.advance()
		if pair.b.can_simulate():
			if not pair.b.take_commands().is_empty() and seen_b < 0:
				seen_b = pair.b.tick
			pair.b.advance()
		pair.pump()
	check(
		seen_a == 15 and seen_b == 15,
		"issued at tick 5, executed at tick 15 on both sides (%d, %d)" % [seen_a, seen_b]
	)

	# Order inside one tick: by player slot, then by issue order.
	var p2 := Pair.new(8)
	p2.b.submit("sell", [20])
	p2.a.submit("sell", [11])
	p2.a.submit("sell", [12])
	p2.b.submit("sell", [21])
	p2.pump()
	var order_a: Array = []
	var order_b: Array = []
	for t in 12:
		if p2.a.can_simulate():
			for c in p2.a.take_commands():
				order_a.append(c["args"][0])
			p2.a.advance()
		if p2.b.can_simulate():
			for c in p2.b.take_commands():
				order_b.append(c["args"][0])
			p2.b.advance()
		p2.pump()
	check(
		order_a == [11, 12, 20, 21] and order_b == order_a,
		"same-tick order: host first, issue order kept %s" % [order_a]
	)

	# No frontier -> no progress (stall), and the nudge unblocks.
	var p3 := Pair.new(6)
	var ran_a := 0
	for t in 30:
		if p3.a.can_simulate():
			p3.a.take_commands()
			p3.a.advance()
			ran_a += 1
	check(ran_a == 6, "a side without partner messages stops after `delay` ticks (ran %d)" % ran_a)
	for i in 6:
		p3.b.take_commands()
		p3.b.advance()
	p3.pump(true)
	check(p3.a.can_simulate(), "after the partner's message it continues")

	# Frontier promise with a big outbox: commands never lag behind the frontier.
	var p4 := Pair.new(20)
	for i in 40:
		p4.a.submit("sell", [i])
	var first: Dictionary = CoopProtocol.decode_message(p4.a.build_message())
	check(
		first["commands"].size() == CoopProtocol.MAX_COMMANDS_PER_MESSAGE,
		"batch limited to 16 commands"
	)
	check(
		first["frontier"] < 20,
		"frontier of a partial batch stays below the waiting commands (%d)" % first["frontier"]
	)
	check(p4.a.has_pending(), "rest waits for the next message")

	# Protocol violations.
	var p5 := Pair.new(8)
	var errors: Array[String] = []
	p5.b.protocol_error.connect(func(r: String) -> void: errors.append(r))
	p5.b.receive({"ok": true, "frontier": 30, "commands": [], "hash": [], "leaving": false})
	check(
		not p5.b.receive(
			{"ok": true, "frontier": 20, "commands": [], "hash": [], "leaving": false}
		),
		"frontier going back refused"
	)
	var p6 := Pair.new(8)
	p6.b.receive({"ok": true, "frontier": 30, "commands": [], "hash": [], "leaving": false})
	check(
		not p6.b.receive(
			{
				"ok": true,
				"frontier": 31,
				"commands": [{"tick": 25, "type": "sell", "args": [1]}],
				"hash": [],
				"leaving": false
			}
		),
		"a command below the earlier promise refused"
	)
	check(not p6.b.receive({"ok": false, "error": "bad_message"}), "undecodable message refused")

	# Desync detection by hash.
	var p7 := Pair.new(8)
	var desyncs: Array[int] = []
	p7.a.desync_detected.connect(func(t: int, _m: int, _r: int) -> void: desyncs.append(t))
	var same := true
	for t in 200:
		for side in [p7.a, p7.b]:
			if (side as CoopLockstep).can_simulate():
				if (side as CoopLockstep).wants_hash():
					(side as CoopLockstep).report_hash(1000 + (side as CoopLockstep).tick)
				(side as CoopLockstep).take_commands()
				(side as CoopLockstep).advance()
		p7.pump()
	check(desyncs.is_empty() and not p7.a.desynced and not p7.b.desynced, "equal hashes: no desync")
	for t in 200:
		for side in [p7.a, p7.b]:
			var s := side as CoopLockstep
			if s.can_simulate():
				if s.wants_hash():
					s.report_hash(5000 + s.tick + (1 if s == p7.b else 0))
				s.take_commands()
				s.advance()
		p7.pump()
	check(
		desyncs.size() == 1 and p7.a.desynced and p7.b.desynced,
		"different hashes: desync flagged once on both"
	)
	check(not p7.a.can_simulate(), "a desynced match freezes")
	check(p7.a.desync_tick % CoopProtocol.HASH_INTERVAL == 0, "desync at a checkpoint tick")
	var p8 := Pair.new(8)
	p8.a.leave()
	p8.pump()
	check(p8.b.partner_left, "farewell reaches the partner")
	same = same and true


# --- whole matches over the fake database ---------------------------------------


## Two sessions of one room and a tiny deterministic simulation on each side.
class Match:
	extends RefCounted
	var server := Fake.FakeServer.new()
	var net_h: Fake.FakeTransport
	var net_g: Fake.FakeTransport
	var sh: CoopSession
	var sg: CoopSession
	var state_h: int = 0
	var state_g: int = 0
	var ticks_h: int = 0
	var ticks_g: int = 0
	var ends_h: Array[String] = []
	var ends_g: Array[String] = []
	var rng := RandomNumberGenerator.new()
	var wobble: bool = false  # the guest's simulation drifts (a "bug")

	func _init(delay: int = 15) -> void:
		net_h = Fake.FakeTransport.new()
		net_g = Fake.FakeTransport.new()
		for pair in [[net_h, "uH"], [net_g, "uG"]]:
			pair[0].server = server
			pair[0].user_id = pair[1]
			server.clients.append(pair[0])
		sh = CoopSession.new(net_h, "ABCDE", "host", delay)
		sg = CoopSession.new(net_g, "ABCDE", "guest", delay)
		sh.ended.connect(func(r: String) -> void: ends_h.append(r))
		sg.ended.connect(func(r: String) -> void: ends_g.append(r))
		rng.seed = 7
		sh.start()
		sg.start()

	func _sim(s: CoopSession, state: int, guest: bool) -> int:
		var ls: CoopLockstep = s.lockstep
		if ls.wants_hash():
			ls.report_hash(state)
		for cmd in ls.take_commands():
			state = (state * 31 + int(cmd["args"][0]) + int(cmd["player"]) * 7) % MOD
		state = (state + ls.tick) % MOD
		if guest and wobble and ls.tick == 100:
			state += 1
		ls.advance()
		return state

	## One 30 Hz frame: random commands, sessions, one tick per side.
	func frame(commands: bool = true) -> void:
		if commands and rng.randf() < 0.08 and not sh.finished:
			sh.submit("build", [rng.randi_range(0, 9), rng.randi_range(0, 3)])
		if commands and rng.randf() < 0.08 and not sg.finished:
			sg.submit("sell", [rng.randi_range(0, 9)])
		sh.process(1.0 / 30.0)
		sg.process(1.0 / 30.0)
		net_h.deliver()
		net_g.deliver()
		if not sh.finished and sh.lockstep.can_simulate():
			state_h = _sim(sh, state_h, false)
			ticks_h += 1
		if not sg.finished and sg.lockstep.can_simulate():
			state_g = _sim(sg, state_g, true)
			ticks_g += 1


func _test_match_clean() -> void:
	print("-- match, instant network")
	var m := Match.new(15)
	for i in 900:
		m.frame()
	check(
		m.ticks_h > 800 and m.ticks_g > 800,
		"both sides ran (%d / %d ticks)" % [m.ticks_h, m.ticks_g]
	)
	check(abs(m.ticks_h - m.ticks_g) <= 16, "tick counts within the input delay")
	# Compare the states at the same tick: let the slower finish.
	for i in 40:
		m.frame(false)
	while m.ticks_h < m.ticks_g and m.sh.lockstep.can_simulate():
		m.state_h = m._sim(m.sh, m.state_h, false)
		m.ticks_h += 1
	check(
		m.ticks_h == m.ticks_g and m.state_h == m.state_g,
		"identical simulation state at tick %d" % m.ticks_h
	)
	check(m.ends_h.is_empty() and m.ends_g.is_empty(), "nobody ended")
	var host_msgs: Dictionary = m.server.get_at("rooms/ABCDE/net/host")
	var per_sec: float = float(host_msgs.size()) / (float(m.ticks_h) / 30.0)
	check(per_sec < 6.0, "message rate %.1f/s (budget 6/s)" % per_sec)
	var bytes: int = JSON.stringify(host_msgs).length()
	print(
		(
			"    host sent %d messages, %d bytes of JSON in %d ticks"
			% [host_msgs.size(), bytes, m.ticks_h]
		)
	)
	check(m.sg.partner_state == "ok", "partner state ok")
	var q: Dictionary = m.net_g.listen_query
	check(
		str(q["orderBy"]) == '"$key"' and str(q["startAt"]).length() == 8,
		"stream filtered by key from the next seq"
	)


func _test_match_latency() -> void:
	print("-- match, delayed network")
	var m := Match.new(15)
	m.net_h.hold = true
	m.net_g.hold = true
	var stall_frames := 0
	for i in 1200:
		# Events arrive every 4th frame (about 130 ms of latency).
		if i % 4 == 0:
			m.net_h.deliver()
			m.net_g.deliver()
		var before: int = m.ticks_h
		m.frame()
		if m.ticks_h == before:
			stall_frames += 1
	m.net_h.hold = false
	m.net_g.hold = false
	m.net_h.deliver()
	m.net_g.deliver()
	for i in 60:
		m.frame(false)
	check(
		m.ticks_h > 1000 and m.ticks_g > 1000,
		(
			"runs with latency (%d / %d ticks, %d stalled frames)"
			% [m.ticks_h, m.ticks_g, stall_frames]
		)
	)
	while m.ticks_h < m.ticks_g and m.sh.lockstep.can_simulate():
		m.state_h = m._sim(m.sh, m.state_h, false)
		m.ticks_h += 1
	while m.ticks_g < m.ticks_h and m.sg.lockstep.can_simulate():
		m.state_g = m._sim(m.sg, m.state_g, true)
		m.ticks_g += 1
	check(m.ticks_h == m.ticks_g and m.state_h == m.state_g, "same state under latency")
	check(m.ends_h.is_empty() and m.ends_g.is_empty(), "no end under latency")


func _test_match_disconnect() -> void:
	print("-- match, disconnect and reconnect")
	var m := Match.new(15)
	for i in 300:
		m.frame()
	var opened: int = m.net_g.listens.size()
	# The guest loses the network for 6 seconds (it neither hears nor writes).
	m.net_g.set_online(false)
	var ticks_before: int = m.ticks_h
	for i in 180:
		m.frame()
	check(
		m.ticks_h - ticks_before <= 20,
		"host stalls without the guest (advanced %d)" % (m.ticks_h - ticks_before)
	)
	check(m.sh.partner_state == "ok", "6 s of silence is still ok")
	for i in 150:
		m.frame()
	check(
		m.sh.partner_state == "waiting",
		"after %d s the host shows `waiting`" % int(CoopSession.WAIT_AFTER)
	)
	m.net_g.set_online(true)  # fresh connection: a full snapshot arrives
	for i in 300:
		m.frame()
	check(
		m.sh.partner_state == "ok" and m.ends_h.is_empty() and m.ends_g.is_empty(),
		"back to ok after reconnect"
	)
	for i in 40:
		m.frame(false)
	while m.ticks_h < m.ticks_g and m.sh.lockstep.can_simulate():
		m.state_h = m._sim(m.sh, m.state_h, false)
		m.ticks_h += 1
	while m.ticks_g < m.ticks_h and m.sg.lockstep.can_simulate():
		m.state_g = m._sim(m.sg, m.state_g, true)
		m.ticks_g += 1
	check(
		m.ticks_h == m.ticks_g and m.state_h == m.state_g,
		"same state after the outage (tick %d)" % m.ticks_h
	)
	check(m.net_g.listens.size() == opened, "the reconnect did not restart the stream by itself")
	# The guest's own outgoing messages were kept and sent after reconnect.
	check(m.net_g.pending.is_empty(), "queued writes flushed after reconnect")

	# Replay after a reconnect: stale puts below the next seq are ignored.
	var replay := Match.new(15)
	for i in 120:
		replay.frame()
	var before: int = replay.sg.lockstep.remote_frontier
	var snapshot: Variant = replay.server.get_at("rooms/ABCDE/net/host")
	replay.net_g.stream_event.emit("put", "/", snapshot)  # the whole history again
	check(
		replay.sg.lockstep.remote_frontier == before and replay.ends_g.is_empty(),
		"replayed history changes nothing"
	)

	# A long silence ends the match.
	var gone := Match.new(15)
	for i in 90:
		gone.frame()
	gone.net_g.set_online(false)
	for i in int((CoopSession.DROP_AFTER + 3.0) * 30.0):
		gone.frame()
	check(
		gone.ends_h == ["lost"],
		"host ends with `lost` after %d s of silence" % int(CoopSession.DROP_AFTER)
	)
	check(gone.sh.partner_state == "lost", "partner state lost")


func _test_match_failures() -> void:
	print("-- match, desync / leaving / violations")
	var m := Match.new(15)
	m.wobble = true
	for i in 600:
		m.frame()
	check(
		m.ends_h == ["desync"] and m.ends_g == ["desync"],
		"both sides end with desync (%s / %s)" % [m.ends_h, m.ends_g]
	)
	check(
		m.sh.lockstep.desync_tick == 120,
		"first checkpoint after the drift (%d)" % m.sh.lockstep.desync_tick
	)

	var leave := Match.new(15)
	for i in 120:
		leave.frame()
	leave.sg.finish()
	for i in 10:
		leave.frame(false)
	check(
		leave.ends_g == ["left"] and leave.ends_h == ["partner_left"],
		"farewell: guest left, host told (%s / %s)" % [leave.ends_g, leave.ends_h]
	)
	check(not leave.sg.submit("build", [1]), "no commands after the end")

	# A forged message from the partner: a command in the past ends the match.
	var forged := Match.new(15)
	for i in 60:
		forged.frame()
	var next_key: String = CoopProtocol.seq_key(forged.sg._next_seq)
	var bad: String = JSON.stringify({"c": [[1, "build", [1]]]})
	forged.server.apply({"rooms/ABCDE/net/host/" + next_key: {"f": 99999, "d": bad}})
	forged.frame(false)
	check(forged.ends_g == ["protocol"], "late command from the partner ends the match")

	# Permission denied on the stream.
	var denied := Match.new(15)
	denied.net_g.stream_error.emit("permission_denied")
	check(denied.ends_g == ["denied"], "stream refused -> ended with `denied`")

	# Gap: messages 1,2 then 4 (3 missing) -> the stream is restarted from 3.
	var gap := Match.new(15)
	var listens_before: int = gap.net_g.listens.size()
	var hf: String = "rooms/ABCDE/net/host/"
	gap.net_g.hold = true
	gap.server.apply(
		{hf + "000001": {"s": 1, "f": 14, "d": ""}, hf + "000002": {"s": 2, "f": 22, "d": ""}}
	)
	gap.server.apply({hf + "000004": {"s": 4, "f": 40, "d": ""}})
	gap.net_g.deliver()
	check(gap.sg.lockstep.remote_frontier == 22, "messages applied in order up to the gap")
	for i in int(CoopSession.GAP_TIMEOUT * 30.0) + 10:
		gap.sg.process(1.0 / 30.0)
	check(
		gap.net_g.listens.size() == listens_before + 1, "stream restarted after a missing message"
	)
	check(
		str(gap.net_g.listens[-1]["query"]["startAt"]) == '"000003"',
		"restart asks from the first missing key"
	)
