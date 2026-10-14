extends SceneTree
## Accounts without network: nickname policy table, profile migration and
## merge, onboarding routing (fresh / resumed / done), offline start without
## firebase.cfg, the encrypted session file, AuthService token logic and the
## Online sync / nickname / deletion flows against a fake HTTP layer.
## godot --headless --path . --script res://tests/test_accounts.gd

const SAVE := "user://test_accounts.cfg"
const SESSION := "user://test_accounts_session.dat"
const CASES := "res://tests/nickname_cases.json"


## Answers requests from `handler` (method, url, body) -> [code, json]; code 0 = no reply.
class FakeTransport:
	extends HttpTransport
	var handler: Callable
	var calls: Array[Dictionary] = []

	func send(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
		calls.append({"method": method, "url": url, "headers": headers, "body": body})
		await get_tree().process_frame  # replies arrive later, like real ones
		var answer: Array = handler.call(method, url, body)
		var code: int = answer[0]
		return {
			"ok": code >= 200 and code < 300,
			"code": code,
			"json": answer[1],
			"network": code == 0,
		}

	func count(fragment: String) -> int:
		var n: int = 0
		for call in calls:
			if fragment in str(call["url"]):
				n += 1
		return n


var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	SessionStore.path = SESSION
	_clean()
	_run.call_deferred()


func _clean() -> void:
	LevelCatalog.erase_all()
	SessionStore.clear()


## Simulates an app restart: the save is read from disk again.
func _restart_app() -> void:
	LevelCatalog.save_path = "user://test_accounts_other.cfg"
	LevelCatalog.data()
	LevelCatalog.save_path = SAVE


func _run() -> void:
	_test_nickname_table()
	_test_migration()
	_test_merge()
	await _test_onboarding_offline()
	_test_session_store()
	await _test_auth()
	await _test_online_sync()
	await _test_nickname_and_delete()
	_clean()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_accounts_other.cfg"))
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _test_nickname_table() -> void:
	var table: Variant = JSON.parse_string(FileAccess.get_file_as_string(CASES))
	var bad: Array[String] = []
	for row: Array in table["cases"]:
		var r: Dictionary = NicknameRules.validate(row[0])
		if r["error"] != row[1] or r["nickname"] != row[2] or r["normalized"] != row[3]:
			bad.append("%s -> %s/%s/%s" % [row[0], r["error"], r["nickname"], r["normalized"]])
	check(bad.is_empty(), "nickname table (%d cases) %s" % [table["cases"].size(), ", ".join(bad)])
	check(NicknameRules.message("taken") != "", "taken has a message")


func _test_migration() -> void:
	var legacy := ConfigFile.new()
	legacy.set_value("progress", "won_1", true)
	legacy.set_value("progress", "stars_2", 2)
	legacy.set_value("progress", "unlocked", 3)
	legacy.set_value("progress", "endless_1", 23)
	legacy.set_value("perks", "axe", 1)
	legacy.set_value("settings", "sound", false)
	legacy.set_value("online", "name", "  Аня  ")
	var p: Dictionary = PlayerProfile.from_save(legacy)
	check(p["schemaVersion"] == PlayerProfile.SCHEMA_VERSION, "v0 save migrates to v1")
	check(p["progression"]["stars"] == {"1": 1, "2": 2}, "old won flag = 1 star")
	check(
		p["progression"]["endless"]["1"] == 23 and p["progression"]["perks"]["axe"] == 1,
		"records, perks"
	)
	check(not p["settings"]["sound"], "sound setting kept")
	check(
		p["onboardingCompleted"] and p["tutorialVersionCompleted"] == 1,
		"a player with progress skips the tutorial"
	)
	check(p["nickname"] == "Аня" and not p["nicknameVerified"], "legacy name kept, unverified")
	var fresh: Dictionary = PlayerProfile.from_save(ConfigFile.new())
	check(
		not fresh["onboardingCompleted"] and fresh["tutorialVersionCompleted"] == 0,
		"a fresh install gets the tutorial"
	)
	var cfg := ConfigFile.new()
	PlayerProfile.write_to_save(p, cfg)
	var again: Dictionary = PlayerProfile.from_save(cfg)
	check(PlayerProfile.content_hash(again) == PlayerProfile.content_hash(p), "save round trip")
	var newer: Dictionary = PlayerProfile.from_cloud({"schemaVersion": 99})
	check(newer.get("newer", false) and newer["schemaVersion"] == 99, "newer schema not downgraded")
	var cloud: Dictionary = PlayerProfile.from_cloud(
		FirestoreClient.decode_fields(PlayerProfile.to_cloud_fields(p))
	)
	check(PlayerProfile.content_hash(cloud) == PlayerProfile.content_hash(p), "cloud round trip")
	var old_cloud: Dictionary = PlayerProfile.from_legacy_text(legacy.encode_to_text())
	check(
		old_cloud["progression"]["unlocked"] == 3 and old_cloud["nickname"] == "",
		"legacy cloud save text migrates (name not trusted)"
	)
	check(PlayerProfile.from_legacy_text("[[[").is_empty(), "broken legacy text ignored")


func _test_merge() -> void:
	var local: Dictionary = PlayerProfile.empty()
	local["updatedAt"] = 100
	local["progression"] = {
		"unlocked": 2, "stars": {"1": 3}, "endless": {"1": 5}, "perks": {"gold_start": 1}
	}
	local["settings"] = {"sound": false}
	local["tutorialVersionCompleted"] = 1
	var cloud: Dictionary = PlayerProfile.empty()
	cloud["updatedAt"] = 50
	cloud["progression"] = {
		"unlocked": 4, "stars": {"1": 2, "3": 1}, "endless": {"1": 9}, "perks": {"axe": 2}
	}
	cloud["settings"] = {"sound": true}
	cloud["nickname"] = "Бобр"
	cloud["nicknameNormalized"] = "бобр"
	var m: Dictionary = PlayerProfile.merge(local, cloud)
	var prog: Dictionary = m["progression"]
	check(prog["unlocked"] == 4, "unlocked: max")
	check(prog["stars"] == {"1": 3, "3": 1}, "stars: max per level")
	check(prog["endless"]["1"] == 9, "records: max")
	var more_spent: bool = (
		PlayerProfile.spent_stars({"axe": 2}) > PlayerProfile.spent_stars({"gold_start": 1})
	)
	check(
		prog["perks"] == ({"axe": 2} if more_spent else {"gold_start": 1}),
		"perks from the side that spent more stars"
	)
	check(m["settings"]["sound"] == false, "settings from the newer side (local)")
	check(m["tutorialVersionCompleted"] == 1, "tutorial flag never goes back")
	check(m["nickname"] == "Бобр" and m["nicknameVerified"], "server nickname wins")
	cloud["updatedAt"] = 500
	check(PlayerProfile.merge(local, cloud)["settings"]["sound"], "newer cloud settings win")
	local["nickname"] = "Ёжик"
	local["nicknameNormalized"] = "ежик"
	local["nicknameVerified"] = false
	check(PlayerProfile.merge(local, cloud)["nickname"] == "Ёжик", "pending local rename kept")
	var stale: Dictionary = PlayerProfile.empty()
	var merged_stale: Dictionary = PlayerProfile.merge(stale, cloud)
	check(
		(
			merged_stale["progression"]["unlocked"] == 4
			and merged_stale["progression"]["stars"]["1"] == 2
		),
		"stale local data never lowers cloud progress"
	)


func _test_onboarding_offline() -> void:
	_clean()
	var online: Node = root.get_node("Online")
	online.setup("", "", HttpTransport.new())
	await online.start()
	check(online.startup_done and not online.is_configured(), "offline start without firebase.cfg")
	check(online.sync_state() == "off" and online.account_type() == "local", "account: local only")
	check(Onboarding.route(PlayerProfile.local()) == Onboarding.Route.NICKNAME, "fresh -> nickname")
	var bad: Dictionary = await online.reserve_nickname("a")
	check(not bad["ok"] and bad["reason"] == "invalid", "invalid name refused")
	var r: Dictionary = await online.reserve_nickname("  Сэр   Ёжик ")
	check(r["ok"] and r["reason"] == "local", "name kept locally without Firebase")
	check(PlayerProfile.local()["nickname"] == "Сэр Ёжик", "cleaned name stored")
	check(
		Onboarding.route(PlayerProfile.local()) == Onboarding.Route.TUTORIAL, "nickname -> tutorial"
	)
	_restart_app()
	check(
		Onboarding.route(PlayerProfile.local()) == Onboarding.Route.TUTORIAL,
		"killed during the tutorial -> resumes the tutorial"
	)
	Onboarding.complete_tutorial()
	_restart_app()
	check(Onboarding.route(PlayerProfile.local()) == Onboarding.Route.MAP, "completed -> map")
	await online.start()
	check(Onboarding.route(PlayerProfile.local()) == Onboarding.Route.MAP, "start() is idempotent")


func _test_session_store() -> void:
	SessionStore.clear()
	check(SessionStore.load_session().is_empty(), "no session at first")
	check(SessionStore.save_session({"uid": "u1", "refresh_token": "SECRET-RT"}), "session saved")
	check(SessionStore.load_session()["refresh_token"] == "SECRET-RT", "session read back")
	var raw: String = FileAccess.get_file_as_bytes(SESSION).get_string_from_ascii()
	check(not "SECRET-RT" in raw and not "u1" in raw, "session file is not plain text")
	var f := FileAccess.open(SESSION, FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	check(SessionStore.load_session().get("unreadable", false), "foreign file -> unreadable")
	SessionStore.clear()


func _make_auth(transport: FakeTransport) -> AuthService:
	var auth := AuthService.new()
	auth.api_key = "test-key"
	auth.transport = transport
	auth.backoff_scale = 0.0
	return auth


func _test_auth() -> void:
	var t := FakeTransport.new()
	root.add_child(t)
	# Lambdas capture locals by value: the reply lives in an array changed in place.
	var refresh_reply: Array = [
		[200, {"id_token": "ID2", "refresh_token": "RT2", "user_id": "u1", "expires_in": "3600"}]
	]
	t.handler = func(_m: int, url: String, _b: String) -> Array:
		if "signUp" in url:
			return [
				200, {"idToken": "ID1", "refreshToken": "RT1", "localId": "u1", "expiresIn": "3600"}
			]
		return refresh_reply[0]
	SessionStore.clear()
	var auth := _make_auth(t)
	auth.restore("")
	var r: Dictionary = await auth.ensure_token(true)
	check(r["ok"] and r["created"] and auth.uid == "u1", "first launch: guest account")
	check(auth.account_type == AuthService.TYPE_GUEST, "account type guest")
	check(SessionStore.load_session()["refresh_token"] == "RT1", "refresh token stored encrypted")
	var again: Dictionary = await auth.ensure_token(true)
	check(again["ok"] and t.calls.size() == 1, "fresh token reused, no request")

	auth.invalidate_token()
	t.calls.clear()
	var results: Array = []
	var wait_one := func() -> void: results.append(await auth.ensure_token(true))
	wait_one.call()
	wait_one.call()
	wait_one.call()
	for i in 10:
		await process_frame
	check(results.size() == 3 and t.count("securetoken") == 1, "single-flight token refresh")
	check(results[0]["ok"] and results[2]["ok"] and auth.id_token() == "ID2", "all callers got it")

	# Offline: refresh unreachable -> keep the uid, never a new account.
	auth.invalidate_token()
	t.calls.clear()
	refresh_reply[0] = [0, null]
	r = await auth.ensure_token(true)
	check(not r["ok"] and r["error"] == "offline", "offline refresh -> error offline")
	check(t.count("signUp") == 0 and auth.uid == "u1", "offline never creates a new account")
	check(t.count("securetoken") == AuthService.MAX_ATTEMPTS, "bounded retries")

	refresh_reply[0] = [503, null]
	t.calls.clear()
	r = await auth.ensure_token(true)
	check(r["error"] == "server" and t.count("signUp") == 0, "server error -> no new account")

	var flaky: Array[int] = [503]
	t.handler = func(_m: int, url: String, _b: String) -> Array:
		if "securetoken" in url and not flaky.is_empty():
			return [flaky.pop_back(), null]
		return [
			200, {"id_token": "ID3", "refresh_token": "RT3", "user_id": "u1", "expires_in": "3600"}
		]
	t.calls.clear()
	r = await auth.ensure_token(true)
	check(r["ok"] and t.count("securetoken") == 2, "transient failure retried")

	t.handler = func(_m: int, url: String, _b: String) -> Array:
		if "securetoken" in url:
			return [400, {"error": {"code": 400, "message": "USER_DISABLED"}}]
		return [200, {"idToken": "X", "refreshToken": "Y", "localId": "u9", "expiresIn": "3600"}]
	auth.invalidate_token()
	r = await auth.ensure_token(true)
	check(r["error"] == "disabled" and auth.uid == "u1", "disabled account is not replaced")

	t.handler = func(_m: int, url: String, _b: String) -> Array:
		if "securetoken" in url:
			return [400, {"error": {"code": 400, "message": "INVALID_REFRESH_TOKEN"}}]
		return [200, {"idToken": "X", "refreshToken": "Y", "localId": "u9", "expiresIn": "3600"}]
	auth.invalidate_token()
	r = await auth.ensure_token(false)
	check(
		r["error"] == "session_lost" and auth.uid == "u1",
		"dead token without consent: no new guest"
	)
	auth.adopt_legacy("u1", "RT-old")
	auth.invalidate_token()
	r = await auth.ensure_token(true)
	check(
		r["ok"] and r["created"] and auth.uid == "u9" and auth.previous_uid == "u1",
		"dead guest token -> new guest, old uid remembered"
	)

	SessionStore.clear()
	var lost := _make_auth(t)
	lost.restore("u5")
	t.calls.clear()
	r = await lost.ensure_token(true)
	check(
		r["error"] == "session_lost" and t.calls.is_empty() and lost.is_session_lost(),
		"known uid without its token is never silently replaced"
	)

	t.handler = func(_m: int, url: String, _b: String) -> Array:
		if "accounts:update" in url:
			return [400, {"error": {"code": 400, "message": "EMAIL_EXISTS"}}]
		return [
			200, {"id_token": "ID4", "refresh_token": "RT4", "user_id": "u9", "expires_in": "3600"}
		]
	r = await auth.link_email("a@b.c", "secret1")
	check(not r["ok"] and r["error"] == "credential_in_use", "linking conflict reported")
	check(
		auth.uid == "u9" and auth.account_type == AuthService.TYPE_GUEST, "conflict keeps the guest"
	)
	r = await auth.link_with_idp("google.com", "token")
	check(not r["ok"] and r["error"] == "not_available", "IdP linking: honest not_available")
	t.queue_free()
	SessionStore.clear()


## Fake Firebase project: auth, users/{uid}, saves/{uid} and a generic document
## store for publicProfiles / nicknames / leaderboards. It mimics the rules that
## matter: creating an existing nickname document is refused (403), a taken name
## belongs to another uid.
class FakeFirebase:
	extends RefCounted
	var users_doc: Variant = null  # Dictionary of decoded fields or null
	var update_time: String = "2026-10-14T10:00:00.000001Z"
	var legacy_text: String = ""
	var fail_commits: int = 0
	var offline: bool = false
	var taken: Array[String] = []
	## users/{uid} commits only.
	var commits: Array[Dictionary] = []
	## Every commit body, in order.
	var all_commits: Array[Array] = []
	## Other documents by path ("publicProfiles/uid1" -> decoded fields).
	var docs: Dictionary = {}
	var auth_deleted: bool = false
	var auth_delete_error: String = ""
	var refuse_commits: int = 0

	func handle(method: int, url: String, body: String) -> Array:
		if offline:
			return [0, null]
		if "signUp" in url:
			return [
				200, {"idToken": "ID", "refreshToken": "RT", "localId": "uid1", "expiresIn": "3600"}
			]
		if "securetoken" in url:
			return [
				200,
				{"id_token": "ID", "refresh_token": "RT", "user_id": "uid1", "expires_in": "3600"}
			]
		if "accounts:delete" in url:
			if auth_delete_error != "":
				return [400, {"error": {"message": auth_delete_error}}]
			auth_deleted = true
			return [200, {}]
		if url.ends_with(":commit"):
			return commit(body)
		return document(method, url)

	func path_of(name: String) -> String:
		return name.get_slice("/documents/", 1)

	func exists(path: String) -> bool:
		if path.begins_with("nicknames/") and path.trim_prefix("nicknames/") in taken:
			return true
		return docs.has(path)

	func fields_of(path: String) -> Dictionary:
		if path.begins_with("nicknames/") and path.trim_prefix("nicknames/") in taken:
			return {"uid": "someone-else"}
		return docs.get(path, {})

	func commit(body: String) -> Array:
		var writes: Array = JSON.parse_string(body)["writes"]
		all_commits.append(writes)
		if refuse_commits > 0:
			refuse_commits -= 1
			return [403, {"error": {"status": "PERMISSION_DENIED"}}]
		var touches_users := false
		for write: Dictionary in writes:
			var name: String = str(write["update"]["name"] if write.has("update") else write["delete"])
			if path_of(name).begins_with("users/"):
				touches_users = true
		if touches_users and writes.size() == 1 and writes[0].has("update"):
			return commit_users(writes[0])
		# Generic documents: validate every write first (all or nothing).
		for write: Dictionary in writes:
			if write.has("update"):
				var path: String = path_of(write["update"]["name"])
				var precondition: Dictionary = write.get("currentDocument", {})
				if precondition.get("exists", true) == false and exists(path):
					return [403, {"error": {"status": "PERMISSION_DENIED"}}]
				if precondition.get("exists", false) == true and not exists(path):
					return [404, {"error": {"status": "NOT_FOUND"}}]
		for write: Dictionary in writes:
			if write.has("delete"):
				var gone: String = path_of(write["delete"])
				docs.erase(gone)
				if gone.begins_with("users/"):
					users_doc = null
			else:
				var path: String = path_of(write["update"]["name"])
				var fields: Dictionary = FirestoreClient.decode_fields(write["update"]["fields"])
				for transform: Dictionary in write.get("updateTransforms", []):
					fields[str(transform["fieldPath"])] = int(Time.get_unix_time_from_system())
				var merged: Dictionary = docs.get(path, {})
				merged.merge(fields, true)
				docs[path] = merged
		return [200, {"writeResults": [{}]}]

	func commit_users(write: Dictionary) -> Array:
		if fail_commits > 0:
			# Another device wrote first: the precondition fails.
			fail_commits -= 1
			users_doc = {"schemaVersion": 1, "progression": {"unlocked": 5, "stars": {"4": 3}}}
			update_time = "2026-10-14T11:00:00.000001Z"
			return [400, {"error": {"status": "FAILED_PRECONDITION"}}]
		commits.append(write)
		var fields: Dictionary = FirestoreClient.decode_fields(write["update"]["fields"])
		fields["updatedAt"] = 2000000000
		users_doc = fields
		return [200, {"writeResults": [{}]}]

	func document(method: int, url: String) -> Array:
		var missing := [404, {"error": {"status": "NOT_FOUND"}}]
		if "/users/" in url and method == HTTPClient.METHOD_GET:
			if users_doc == null:
				return missing
			return [
				200, {"fields": FirestoreClient.encode_fields(users_doc), "updateTime": update_time}
			]
		if "/saves/" in url and method == HTTPClient.METHOD_GET:
			if legacy_text == "":
				return missing
			return [200, {"fields": {"progress": {"stringValue": legacy_text}}}]
		if "/saves/" in url and method == HTTPClient.METHOD_DELETE:
			legacy_text = ""
			return [200, {}]
		var path: String = url.get_slice("/documents/", 1)
		if method == HTTPClient.METHOD_GET and exists(path):
			return [200, {"fields": FirestoreClient.encode_fields(fields_of(path))}]
		return missing


func _configured_online(fake: FakeFirebase) -> Node:
	var online: Node = root.get_node("Online")
	var t := FakeTransport.new()
	t.handler = fake.handle
	online.setup("test-key", "test-project", t)
	online.auth.backoff_scale = 0.0
	online.firestore.backoff_scale = 0.0
	return online


func _test_online_sync() -> void:
	_clean()
	# An old save with a plain-text session and a legacy cloud save.
	var cfg: ConfigFile = LevelCatalog.data()
	cfg.set_value("online", "uid", "uid1")
	cfg.set_value("online", "refresh_token", "OLD-PLAIN-RT")
	cfg.set_value("progress", "stars_1", 2)
	LevelCatalog.commit()
	var fake := FakeFirebase.new()
	var legacy := ConfigFile.new()
	legacy.set_value("progress", "stars_2", 3)
	legacy.set_value("progress", "unlocked", 3)
	fake.legacy_text = legacy.encode_to_text()
	var online: Node = _configured_online(fake)
	await online.start()
	var text: String = FileAccess.get_file_as_string(SAVE)
	check(
		not "OLD-PLAIN-RT" in text and not "[online]" in text,
		"plain-text token removed from the save"
	)
	check(
		SessionStore.load_session().get("uid", "") == "uid1",
		"old session moved to the encrypted store"
	)
	check(LevelCatalog.stars(2) == 3 and LevelCatalog.stars(1) == 2, "legacy cloud save merged")
	check(
		fake.commits.size() == 1 and fake.legacy_text == "", "profile written, legacy save deleted"
	)
	var write: Dictionary = fake.commits[0]
	check(write["currentDocument"] == {"exists": false}, "create is conditional (exists=false)")
	check(
		(
			write["updateMask"]["fieldPaths"].size() == PlayerProfile.SYNC_KEYS.size()
			and not "nickname" in write["update"]["fields"]
		),
		"client writes only its own fields"
	)
	check(online.sync_state() == "synced", "state: synced")
	var r: Dictionary = await online.sync_now()
	check(r["ok"] and fake.commits.size() == 1, "nothing changed -> no write")

	# Another device wrote in between: the conditional write fails, read again.
	LevelCatalog.complete(1, 3)
	check(online.sync_state() == "pending", "local change -> pending")
	fake.fail_commits = 1
	r = await online.sync_now()
	check(r["ok"] and fake.commits.size() == 2, "precondition failure -> merge again and write")
	check(
		LevelCatalog.stars(4) == 3 and LevelCatalog.unlocked() == 5, "other device's progress kept"
	)
	check(
		fake.commits[1]["currentDocument"].has("updateTime"), "update is conditional (updateTime)"
	)

	fake.offline = true
	LevelCatalog.complete(3, 3)
	r = await online.sync_now()
	check(not r["ok"] and online.sync_state() == "offline", "offline -> not synced, local kept")
	check(LevelCatalog.stars(3) == 3, "offline play stays local")
	fake.offline = false
	r = await online.sync_now()
	check(r["ok"] and online.sync_state() == "synced", "synced once back online")

	fake.users_doc = {"schemaVersion": 7}
	r = await online.sync_now()
	check(
		r["error"] == "newer" and online.sync_state() == "newer",
		"newer cloud schema not overwritten"
	)
	fake.users_doc = null


func _test_nickname_and_delete() -> void:
	_clean()
	var fake := FakeFirebase.new()
	fake.taken = ["бобр"]
	var online: Node = _configured_online(fake)
	await online.start()
	var concurrent: Array = []
	var go := func(name: String) -> void: concurrent.append(await online.reserve_nickname(name))
	go.call("Бобр")
	go.call("Бобр")
	for i in 20:
		await process_frame
	var reasons: Array = concurrent.map(func(x: Dictionary) -> String: return x["reason"])
	check("busy" in reasons and "taken" in reasons, "double submit blocked")
	check(PlayerProfile.local()["nickname"] == "", "taken name never stored silently")
	var r: Dictionary = await online.reserve_nickname("Ёжик")
	check(r["ok"] and r["reason"] == "reserved", "name reserved on the server")
	check(PlayerProfile.local()["nicknameVerified"], "reserved name is verified")
	# Reservation is one atomic commit: index document + public profile.
	check(fake.docs.has("publicProfiles/uid1"), "public profile written")
	check(fake.docs["nicknames/ежик"]["uid"] == "uid1", "index document owned by this uid")
	check(fake.docs["publicProfiles/uid1"]["nicknameNormalized"] == "ежик", "profile key")
	var first_commit: Array = fake.all_commits.filter(
		func(w: Array) -> bool: return w.size() == 2 and "nicknames/" in str(w[0])
	)[0]
	check(
		first_commit[0]["currentDocument"] == {"exists": false},
		"nickname index is create-only (exists=false)"
	)
	# A change inside 24 hours is refused locally, after 24 hours it moves the name.
	r = await online.reserve_nickname("Ёжик Новый")
	check(r["reason"] == "rate_limited" and not r["ok"], "second change within 24 hours refused")
	fake.docs["publicProfiles/uid1"]["nicknameChangedAt"] = 1000
	r = await online.reserve_nickname("Ёжик Новый")
	check(r["ok"] and r["reason"] == "reserved", "name changed after 24 hours")
	check(
		not fake.docs.has("nicknames/ежик") and fake.docs.has("nicknames/ежик_новый"),
		"old key released, new key created"
	)
	var change: Array = fake.all_commits[-1]
	check(
		change[0].has("delete") and change[1]["currentDocument"] == {"exists": false},
		"change = delete old + create new (one commit)"
	)
	# The rules refuse (403) a name that appeared in between: reported as taken.
	fake.taken.append("опоздавший")
	fake.docs["publicProfiles/uid1"]["nicknameChangedAt"] = 1000
	r = await online.reserve_nickname("Опоздавший")
	check(r["reason"] == "taken", "403 on a taken index document -> taken")
	fake.offline = true
	r = await online.reserve_nickname("Сова")
	check(r["reason"] == "offline" and r["saved_locally"], "offline: name kept on the device")
	check(
		(
			PlayerProfile.local()["nickname"] == "Сова"
			and not PlayerProfile.local()["nicknameVerified"]
		),
		"offline name is unverified"
	)
	fake.offline = false
	fake.taken = ["сова"]
	await online.sync_now()
	check(PlayerProfile.local()["nicknameConflict"], "taken at the next sync -> conflict flag")
	check(
		Onboarding.route(PlayerProfile.local()) == Onboarding.Route.NICKNAME,
		"conflict -> ask again"
	)

	# Deleting the account: documents first, then the Auth user, then local data.
	fake.docs["leaderboards/level_1/scores/uid1"] = {"name": "x", "wave": 3}
	fake.refuse_commits = 1
	r = await online.delete_account()
	check(not r["ok"] and not fake.auth_deleted, "documents refused -> Auth user kept, retry possible")
	fake.auth_delete_error = "CREDENTIAL_TOO_OLD_LOGIN_AGAIN"
	r = await online.delete_account()
	check(not r["ok"] and r["reason"] == "reauth_required", "old login -> reauth_required")
	check(FileAccess.file_exists(SAVE), "local data kept when the account was not deleted")
	fake.auth_delete_error = ""
	r = await online.delete_account()
	check(r["ok"] and r["scope"] == "cloud", "account deleted from the client")
	check(fake.auth_deleted, "Auth user deleted (accounts:delete)")
	var gone := true
	for path: String in ["publicProfiles/uid1", "leaderboards/level_1/scores/uid1"]:
		gone = gone and not fake.docs.has(path)
	for path: String in fake.docs:
		gone = gone and not path.begins_with("nicknames/")
	check(gone and fake.users_doc == null, "own documents, nickname index and records deleted")
	var last: Array = fake.all_commits[-1]
	var paths := last.map(func(w: Dictionary) -> String: return str(w.get("delete", "")))
	check(
		paths.any(func(x: String) -> bool: return x.ends_with("/users/uid1"))
		and last.size() >= 4,
		"deletion commit covers users, profile, nickname, saves, records"
	)
	check(
		not FileAccess.file_exists(SAVE) and not FileAccess.file_exists(SESSION), "local data wiped"
	)
	check(
		Onboarding.route(PlayerProfile.local()) == Onboarding.Route.NICKNAME,
		"after deletion: fresh start"
	)
	online.setup("", "", HttpTransport.new())
