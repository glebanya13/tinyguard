extends SceneTree
## MANUAL end-to-end check of the real RtdbClient (HTTPClient: REST writes, SSE
## stream) against the local Realtime Database emulator with database.rules.json
## loaded: lobby, a short lockstep match of two clients, cleanup. Not part of
## run_all.sh (needs the emulator, Java 21 and firebase-tools):
##   firebase emulators:start --only database --project demo-bimbleguard   (port 9189)
##   godot --headless --path . --script res://tests/live_rtdb_emulator.gd
## Tokens are unsigned JWTs, which only the emulator accepts. Never run it against
## a real project.

const URL := "http://127.0.0.1:9189?ns=demo-bimbleguard-default-rtdb"
const MOD := 1000003

var fails := 0


## Auth without any network: the id token is a made-up unsigned JWT.
class StubAuth:
	extends AuthService
	var token: String = ""

	func id_token() -> String:
		return token

	func ensure_token(_allow_create: bool = true) -> Dictionary:
		return {"ok": true, "error": "", "created": false}

	func is_configured() -> bool:
		return true


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _jwt(uid: String) -> String:
	var enc := func(d: Dictionary) -> String:
		var b64: String = Marshalls.raw_to_base64(JSON.stringify(d).to_utf8_buffer())
		return b64.replace("+", "-").replace("/", "_").replace("=", "")
	var now: int = int(Time.get_unix_time_from_system())
	var claims := {
		"iss": "https://securetoken.google.com/demo-bimbleguard",
		"aud": "demo-bimbleguard",
		"sub": uid,
		"user_id": uid,
		"iat": now,
		"exp": now + 3600,
		"firebase": {"identities": {}, "sign_in_provider": "anonymous"},
	}
	return enc.call({"alg": "none", "typ": "JWT"}) + "." + enc.call(claims) + "."


func _client(uid: String) -> RtdbClient:
	var auth := StubAuth.new()
	auth.uid = uid
	auth.token = _jwt(uid)
	var client := RtdbClient.new()
	root.add_child(client)
	check(client.configure(URL, auth), "client configured for " + uid)
	return client


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	var host_net: RtdbClient = _client("liveHost")
	var guest_net: RtdbClient = _client("liveGuest")
	# Plain REST round trip.
	var w: Dictionary = await host_net.write("user_rooms/liveHost", "ABCDE")
	check(w["ok"], "PUT answered 2xx (%s)" % w["code"])
	var r: Dictionary = await host_net.read("user_rooms/liveHost")
	check(r["ok"] and r["value"] == "ABCDE", "GET returns what was written")
	var denied: Dictionary = await guest_net.read("user_rooms/liveHost")
	check(not denied["ok"] and denied["code"] == 401, "someone else's node is refused (401)")
	await host_net.write("user_rooms/liveHost", null)

	var host := CoopLobby.new(host_net)
	var guest := CoopLobby.new(guest_net)
	var started: Array[Dictionary] = []
	host.started.connect(func(c: Dictionary) -> void: started.append(c))
	guest.started.connect(func(c: Dictionary) -> void: started.append(c))
	var made: Dictionary = await host.create(2, "Аня", 1)
	check(made["ok"], "room created through the rules: %s" % made)
	if not made["ok"]:
		quit(1)
		return
	var joined: Dictionary = await guest.join(made["code"], "Боб", 1)
	check(joined["ok"], "guest joined: %s" % joined)
	await _wait(0.5)
	check(
		host.snapshot().get("guest", {}).get("uid", "") == "liveGuest",
		"host sees the guest over SSE"
	)
	await guest.set_ready(true)
	await _wait(0.5)
	check(bool(host.snapshot().get("can_start", false)), "host sees readiness over SSE")
	var go: Dictionary = await host.start_match()
	check(go["ok"], "match started: %s" % go)
	await _wait(0.8)
	check(started.size() == 2, "both sides got `started` (%d)" % started.size())

	var sh := CoopSession.new(host_net, made["code"], "host", 15)
	var sg := CoopSession.new(guest_net, made["code"], "guest", 15)
	var ends: Array[String] = []
	sh.ended.connect(func(r: String) -> void: ends.append("h:" + r))
	sg.ended.connect(func(r: String) -> void: ends.append("g:" + r))
	sh.start()
	sg.start()
	var state := [0, 0]
	var ticks := [0, 0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for frame in 700:
		if rng.randf() < 0.05:
			sh.submit("build", [rng.randi_range(0, 9), 1])
		if rng.randf() < 0.05:
			sg.submit("sell", [rng.randi_range(0, 9)])
		sh.process(1.0 / 30.0)
		sg.process(1.0 / 30.0)
		for i in 2:
			var s: CoopSession = sh if i == 0 else sg
			if s.lockstep.can_simulate():
				if s.lockstep.wants_hash():
					s.lockstep.report_hash(state[i])
				for cmd in s.lockstep.take_commands():
					state[i] = (state[i] * 31 + int(cmd["args"][0]) + int(cmd["player"]) * 7) % MOD
				state[i] = (state[i] + s.lockstep.tick) % MOD
				s.lockstep.advance()
				ticks[i] += 1
		await create_timer(0.01).timeout
	print("    ticks: host %d, guest %d" % [ticks[0], ticks[1]])
	check(ticks[0] > 300 and ticks[1] > 300, "both sides advanced over the real stream")
	check(ends.is_empty(), "no session ended or desynced: %s" % [ends])
	var common: int = mini(ticks[0], ticks[1])
	check(abs(ticks[0] - ticks[1]) <= 20, "tick counts close (%d vs %d)" % [ticks[0], ticks[1]])
	print("    common ticks %d (states compared by checkpoint hashes: no desync above)" % common)

	await sg.finish()
	await _wait(0.5)
	check(ends.has("h:partner_left"), "host was told the guest left: %s" % [ends])
	await host.leave()
	await _wait(0.3)
	var left: Dictionary = await host_net.read("rooms/%s/meta" % made["code"])
	check(left["ok"] and left["value"] == null, "the room is gone after the host left")
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
