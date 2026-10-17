extends SceneTree
## Email accounts without network: client-side input checks, the service-level
## calls (accounts:update, signInWithPassword, sendOobCode) and their error
## mapping, linking a guest, signing in on "another device" with the profile
## merge, password reset, sign-out, no secrets on disk or in logs, hidden
## buttons without firebase.cfg. A fake Firebase project answers (tests/fakes.gd).
## godot --headless --path . --script res://tests/test_email_accounts.gd

const SAVE := "user://test_email_accounts.cfg"
const SESSION := "user://test_email_accounts_session.dat"
const Fakes := preload("res://tests/fakes.gd")

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


func _run() -> void:
	_test_email_rules()
	await _test_email_auth_service()
	await _test_email_accounts()
	await _test_email_offline_and_ui()
	_test_no_secret_logging()
	_clean()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _make_auth(transport: Fakes.FakeTransport) -> AuthService:
	var auth := AuthService.new()
	auth.api_key = "test-key"
	auth.transport = transport
	auth.backoff_scale = 0.0
	return auth


func _configured_online(fake: Fakes.FakeFirebase) -> Node:
	var online: Node = root.get_node("Online")
	var t := Fakes.FakeTransport.new()
	t.handler = fake.handle
	online.setup("test-key", "test-project", t)
	online.auth.backoff_scale = 0.0
	online.firestore.backoff_scale = 0.0
	return online


func _test_email_rules() -> void:
	var good: Array[String] = ["a@b.co", "  first.last+tag@sub.example.com  ", "ё@пример.рф"]
	var bad: Array[String] = [
		"", "   ", "a@b", "a@@b.co", "a b@c.de", "@b.co", "a@.co", "a@b..co", "a@b.c o", "ab.co"
	]
	var wrong: Array[String] = []
	for text: String in good:
		if not EmailRules.check_email(text)["ok"]:
			wrong.append(text)
	for text: String in bad:
		if EmailRules.check_email(text)["ok"]:
			wrong.append(text)
	check(wrong.is_empty(), "email table (%d cases) %s" % [good.size() + bad.size(), wrong])
	check(EmailRules.check_email("  a@b.co ")["email"] == "a@b.co", "email is trimmed")
	check(EmailRules.check_email("")["error"] == "empty_email", "empty email has its own error")
	check(not EmailRules.check_email("a@b.co".rpad(300, "o"))["ok"], "too long email refused")
	check(EmailRules.check_new_password("")["error"] == "empty_password", "empty password")
	check(EmailRules.check_new_password("12345")["error"] == "weak_password", "5 chars is weak")
	check(EmailRules.check_new_password("123456")["ok"], "6 chars pass the client check")
	check(
		EmailRules.check_new_password(" 12345 ")["ok"], "spaces count, the password is not trimmed"
	)
	check(
		EmailRules.check_new_password("x".repeat(129))["error"] == "password_too_long",
		"password upper bound"
	)
	check(EmailRules.check_password("a")["ok"], "sign-in accepts any non-empty password")
	# Every error key the services can answer with has its own player text.
	var generic: String = EmailRules.message("no-such-key")
	var keys: Array = []
	for table: Dictionary in [
		AuthService.LINK_ERRORS, AuthService.SIGN_IN_ERRORS, AuthService.RESET_ERRORS
	]:
		keys.append_array(table.values())
	keys.append_array(
		["offline", "server", "other_account", "already_linked", "session_lost", "no_session"]
	)
	keys.append_array(["busy", "not_configured", "unsynced", "guest_cannot_sign_out"])
	var silent: Array = keys.filter(
		func(k: String) -> bool: return EmailRules.message(k) == generic
	)
	check(silent.is_empty(), "every error key has a message %s" % [silent])


## The service-level email calls against a scripted transport.
func _test_email_auth_service() -> void:
	var t := Fakes.FakeTransport.new()
	root.add_child(t)
	var answer: Array = [[200, {}]]
	t.handler = func(_m: int, url: String, _b: String) -> Array:
		if "signUp" in url:
			return [
				200, {"idToken": "ID1", "refreshToken": "RT1", "localId": "u1", "expiresIn": "3600"}
			]
		return answer[0]
	SessionStore.clear()
	var auth := _make_auth(t)
	auth.restore("")
	await auth.ensure_token(true)

	var link_cases := {
		"EMAIL_EXISTS": "credential_in_use",
		"WEAK_PASSWORD : Password should be at least 6 characters": "weak_password",
		"INVALID_EMAIL": "invalid_email",
		"CREDENTIAL_TOO_OLD_LOGIN_AGAIN": "reauth_required",
		"TOO_MANY_ATTEMPTS_TRY_LATER : blocked": "too_many_attempts",
		"OPERATION_NOT_ALLOWED": "link_disabled",
		"ADMIN_ONLY_OPERATION": "signup_closed",
		"SOMETHING_NEW": "server",
	}
	var wrong: Array[String] = []
	for message: String in link_cases:
		answer[0] = [400, {"error": {"code": 400, "message": message}}]
		var r: Dictionary = await auth.link_email("a@b.co", "secret12")
		if r["ok"] or r["error"] != link_cases[message]:
			wrong.append("%s -> %s" % [message, r["error"]])
	check(wrong.is_empty(), "link errors mapped %s" % [wrong])
	check(auth.account_type == AuthService.TYPE_GUEST, "failed linking keeps the guest")
	t.calls.clear()
	answer[0] = [503, null]
	var down: Dictionary = await auth.link_email("a@b.co", "secret12")
	check(down["error"] == "server" and t.count("accounts:update") == 1, "link is not retried")
	answer[0] = [0, null]
	down = await auth.link_email("a@b.co", "secret12")
	check(down["error"] == "offline", "link offline")
	answer[0] = [429, null]
	down = await auth.link_email("a@b.co", "secret12")
	check(down["error"] == "too_many_attempts", "HTTP 429 -> too_many_attempts")

	var sign_cases := {
		"INVALID_LOGIN_CREDENTIALS": "invalid_credentials",
		"INVALID_PASSWORD": "invalid_credentials",
		"EMAIL_NOT_FOUND": "invalid_credentials",
		"USER_DISABLED": "disabled",
		"TOO_MANY_ATTEMPTS_TRY_LATER : Access temporarily disabled": "too_many_attempts",
		"INVALID_EMAIL": "invalid_email",
		"OPERATION_NOT_ALLOWED": "signin_disabled",
	}
	wrong.clear()
	for message: String in sign_cases:
		answer[0] = [400, {"error": {"code": 400, "message": message}}]
		var r: Dictionary = await auth.sign_in_email("a@b.co", "secret12")
		if r["ok"] or r["error"] != sign_cases[message]:
			wrong.append("%s -> %s" % [message, r["error"]])
	check(wrong.is_empty(), "sign-in errors mapped %s" % [wrong])
	check(
		auth.uid == "u1" and auth.account_type == AuthService.TYPE_GUEST,
		"failed sign-in: no change"
	)
	t.calls.clear()
	answer[0] = [400, {"error": {"message": "INVALID_LOGIN_CREDENTIALS"}}]
	await auth.sign_in_email("a@b.co", "secret12")
	check(t.calls.size() == 1, "a wrong password is not retried")

	# Password reset: no session needed, unknown address looks like success.
	var bare := _make_auth(t)
	t.calls.clear()
	answer[0] = [200, {"email": "a@b.co"}]
	var sent: Dictionary = await bare.send_password_reset("a@b.co")
	var body: Variant = JSON.parse_string(t.calls[0]["body"])
	check(
		sent["ok"] and body == {"requestType": "PASSWORD_RESET", "email": "a@b.co"},
		"reset: PASSWORD_RESET request without a session"
	)
	answer[0] = [400, {"error": {"message": "EMAIL_NOT_FOUND"}}]
	sent = await bare.send_password_reset("who@b.co")
	check(sent["ok"], "reset: unknown email is not revealed")
	for message: String in [
		"INVALID_EMAIL", "TOO_MANY_ATTEMPTS_TRY_LATER", "OPERATION_NOT_ALLOWED"
	]:
		answer[0] = [400, {"error": {"message": message}}]
		sent = await bare.send_password_reset("a@b.co")
		check(
			not sent["ok"] and sent["error"] == AuthService.RESET_ERRORS[message],
			"reset error " + message
		)
	answer[0] = [0, null]
	check((await bare.send_password_reset("a@b.co"))["error"] == "offline", "reset offline")
	var unconfigured := AuthService.new()
	check(
		(await unconfigured.sign_in_email("a@b.co", "x"))["error"] == "not_configured",
		"no key: nothing is sent"
	)
	t.queue_free()
	SessionStore.clear()


func _bodies(fake: Fakes.FakeFirebase, fragment: String) -> Array:
	return fake.email_requests.filter(func(r: Dictionary) -> bool: return fragment in r["url"])


func _test_email_accounts() -> void:
	_clean()
	var fake := Fakes.FakeFirebase.new()
	var online: Node = _configured_online(fake)
	await online.start()
	# --- device 1: a guest with a nickname and progress ---
	check(online.auth.uid == "uid1", "device 1: guest uid1")
	var r: Dictionary = await online.reserve_nickname("Ёжик")
	LevelCatalog.complete(1, 3)
	Onboarding.complete_tutorial()
	await online.sync_now()
	check((await online.sign_out())["error"] == "guest_cannot_sign_out", "a guest cannot sign out")
	# Invalid input never reaches the network.
	var refused: Array = [
		["nope", "secret12", "invalid_email"],
		["", "x", "empty_email"],
		["a@b.co", "123", "weak_password"],
		["a@b.co", "", "empty_password"],
	]
	for row: Array in refused:
		r = await online.link_email(row[0], row[1])
		check(not r["ok"] and r["error"] == row[2], "link refused locally: " + row[2])
	check(fake.email_requests.is_empty(), "no request for invalid input")
	fake.min_password = 8
	r = await online.link_email("ana@example.com", "abcdefg")
	check(
		r["error"] == "weak_password" and online.account_type() == "guest", "server WEAK_PASSWORD"
	)
	fake.min_password = 6
	fake.forced["accounts:update"] = "CREDENTIAL_TOO_OLD_LOGIN_AGAIN"
	r = await online.link_email("ana@example.com", "hunter22")
	check(r["error"] == "reauth_required", "link: CREDENTIAL_TOO_OLD_LOGIN_AGAIN")
	fake.forced.clear()
	fake.offline = true
	r = await online.link_email("ana@example.com", "hunter22")
	check(r["error"] == "offline" and online.account_type() == "guest", "link offline: still guest")
	fake.offline = false

	r = await online.link_email("  Ana@Example.com ", "hunter22")
	check(r["ok"], "email linked")
	var sent: Dictionary = _bodies(fake, "accounts:update")[-1]["body"]
	check(
		(
			sent["email"] == "Ana@Example.com"
			and sent["password"] == "hunter22"
			and sent["returnSecureToken"] == true
			and sent["idToken"] == "ID:uid1"
		),
		"accounts:update carries idToken, trimmed email, password, returnSecureToken"
	)
	check(
		online.auth.uid == "uid1" and online.account_type() == "email",
		"linking keeps the uid and makes it an email account"
	)
	check(fake.accounts["ana@example.com"]["uid"] == "uid1", "the email belongs to the same uid")
	check(fake.users_doc["progression"]["stars"]["1"] == 3, "progress stays under the same uid")
	check(
		(await online.link_email("other@example.com", "hunter22"))["error"] == "already_linked",
		"cannot link twice"
	)
	# Nothing secret on disk: neither the password nor the email (the session file holds
	# only the uid, the refresh token and the account type).
	var disk: String = (
		FileAccess.get_file_as_string(SAVE)
		+ JSON.stringify(SessionStore.load_session())
		+ FileAccess.get_file_as_bytes(SESSION).get_string_from_ascii()
	)
	check(not "hunter22" in disk and not "xample.com" in disk, "password and email are not stored")
	var allowed: Array[String] = [
		"uid", "refresh_token", "account_type", "previous_uid", "email_verified"
	]
	var extra: Array = SessionStore.load_session().keys().filter(
		func(k: String) -> bool: return not k in allowed
	)
	check(extra.is_empty(), "session file keeps only uid, tokens and type")

	# --- device 2: another guest with its own progress and nickname ---
	_clean()
	fake.guest_uid = "uid2"
	online = _configured_online(fake)
	await online.start()
	await online.reserve_nickname("Сова")
	LevelCatalog.complete(2, 2)
	await online.sync_now()
	check(online.auth.uid == "uid2" and fake.other_users.has("uid2"), "device 2: its own guest")
	r = await online.link_email("ana@example.com", "another99")
	check(r["error"] == "credential_in_use" and online.account_type() == "guest", "EMAIL_EXISTS")
	r = await online.sign_in_email("ana@example.com", "wrong-password")
	check(r["error"] == "invalid_credentials" and not r["switched"], "wrong password")
	check(
		online.auth.uid == "uid2" and SessionStore.load_session()["uid"] == "uid2",
		"a failed sign-in changes nothing"
	)
	check(PlayerProfile.local()["nickname"] == "Сова", "failed sign-in keeps the local profile")
	fake.forced["signInWithPassword"] = "TOO_MANY_ATTEMPTS_TRY_LATER : later"
	r = await online.sign_in_email("ana@example.com", "hunter22")
	check(r["error"] == "too_many_attempts", "TOO_MANY_ATTEMPTS_TRY_LATER")
	fake.forced["signInWithPassword"] = "USER_DISABLED"
	r = await online.sign_in_email("ana@example.com", "hunter22")
	check(r["error"] == "disabled", "USER_DISABLED")
	fake.forced.clear()
	fake.offline = true
	r = await online.sign_in_email("ana@example.com", "hunter22")
	check(r["error"] == "offline" and online.auth.uid == "uid2", "sign-in offline")
	fake.offline = false
	# Double submit: one request at a time.
	var concurrent: Array = []
	var go := func() -> void: concurrent.append(await online.sign_in_email("ana@example.com", "no"))
	go.call()
	go.call()
	for i in 20:
		await process_frame
	var reasons: Array = concurrent.map(func(x: Dictionary) -> String: return x["error"])
	check("busy" in reasons and "invalid_credentials" in reasons, "double submit blocked")

	# Sign in on the other device: the profiles merge, the account's nickname wins.
	r = await online.sign_in_email(" ANA@example.com ", "hunter22")
	check(r["ok"] and r["switched"] and r["synced"], "signed in, merged and synced")
	check(online.auth.uid == "uid1" and online.account_type() == "email", "now the email account")
	check(
		LevelCatalog.stars(1) == 3 and LevelCatalog.stars(2) == 2,
		"stars: the account's and this device's"
	)
	var merged: Dictionary = PlayerProfile.local()
	check(
		merged["nickname"] == "Ёжик" and merged["nicknameVerified"],
		"the account's nickname wins over the abandoned guest's"
	)
	check(
		fake.users_doc["progression"]["stars"] == {"1": 3, "2": 2},
		"merged progress written to the account"
	)
	check(
		(
			fake.docs["publicProfiles/uid1"]["nicknameNormalized"] == "ежик"
			and not fake.docs.has("nicknames/сова_2")
		),
		"no new nickname was reserved for the account"
	)
	check(
		(
			SessionStore.load_session()["uid"] == "uid1"
			and SessionStore.load_session()["account_type"] == AuthService.TYPE_EMAIL
			and online.auth.previous_uid == "uid2"
		),
		"session switched, the old guest uid is remembered"
	)
	check(
		LevelCatalog.data().get_value(PlayerProfile.SECTION, "account_uid", "") == "uid1",
		"local profile now belongs to the account"
	)
	check(online.sync_state() == "synced", "state synced after sign-in")
	check(
		fake.docs.has("publicProfiles/uid2"),
		"the abandoned guest's documents are left alone (documented)"
	)

	# Already in an email account: another account is refused, the same one re-logs in.
	fake.accounts["bob@example.com"] = {"password": "bobpass1", "uid": "uid9"}
	r = await online.sign_in_email("bob@example.com", "bobpass1")
	check(
		r["error"] == "other_account" and online.auth.uid == "uid1", "no switching between emails"
	)
	check(SessionStore.load_session()["uid"] == "uid1", "refused sign-in keeps the session")
	var stars_before: Dictionary = PlayerProfile.local()["progression"]["stars"].duplicate()
	r = await online.sign_in_email("ana@example.com", "hunter22")
	check(r["ok"] and not r["switched"], "signing in to the same account again is a re-login")
	check(
		PlayerProfile.local()["progression"]["stars"] == stars_before, "re-login keeps the profile"
	)

	# Sign out: without a connection unsaved progress is not thrown away.
	LevelCatalog.complete(3, 1)
	fake.offline = true
	r = await online.sign_out()
	check(r["error"] == "unsynced" and FileAccess.file_exists(SAVE), "offline sign-out refused")
	check(online.auth.uid == "uid1", "still signed in after the refused sign-out")
	fake.offline = false
	r = await online.sign_out()
	check(r["ok"], "signed out")
	check(fake.users_doc["progression"]["stars"].has("3"), "progress was saved before the exit")
	check(
		not FileAccess.file_exists(SAVE) and not FileAccess.file_exists(SESSION),
		"local data and session are gone"
	)
	check(online.auth.uid == "" and online.account_type() == "none", "no account after sign-out")
	check(
		Onboarding.route(PlayerProfile.local()) == Onboarding.Route.NICKNAME, "back to first launch"
	)
	# Signing in without any session (fresh install, nickname screen).
	r = await online.sign_in_email("ana@example.com", "hunter22")
	check(r["ok"] and r["switched"] and online.auth.uid == "uid1", "sign-in on a clean device")
	check(
		LevelCatalog.stars(1) == 3 and LevelCatalog.stars(3) == 1 and LevelCatalog.stars(2) == 2,
		"the whole progress is back"
	)
	check(
		(
			PlayerProfile.local()["nickname"] == "Ёжик"
			and Onboarding.route(PlayerProfile.local()) == Onboarding.Route.MAP
		),
		"nickname and onboarding come from the account: straight to the map"
	)

	# Password reset.
	var before: int = fake.oob.size()
	r = await online.send_password_reset("not an email")
	check(
		r["error"] == "invalid_email" and fake.oob.size() == before, "reset: bad email, no request"
	)
	r = await online.send_password_reset(" Ana@Example.com ")
	check(
		r["ok"] and fake.oob[-1] == {"requestType": "PASSWORD_RESET", "email": "Ana@Example.com"},
		"reset mail requested (PASSWORD_RESET)"
	)
	r = await online.send_password_reset("nobody@example.com")
	check(r["ok"], "reset for an unknown email looks the same")
	fake.forced["sendOobCode"] = "TOO_MANY_ATTEMPTS_TRY_LATER"
	r = await online.send_password_reset("ana@example.com")
	check(r["error"] == "too_many_attempts", "reset: too many attempts")
	fake.forced.clear()
	fake.offline = true
	r = await online.send_password_reset("ana@example.com")
	check(r["error"] == "offline", "reset offline")
	fake.offline = false

	# Deleting an email account that needs a fresh login: re-login, then it works.
	fake.auth_delete_error = "CREDENTIAL_TOO_OLD_LOGIN_AGAIN"
	r = await online.delete_account()
	check(r["reason"] == "reauth_required", "delete: old login")
	fake.auth_delete_error = ""
	await online.sign_in_email("ana@example.com", "hunter22")
	r = await online.delete_account()
	check(r["ok"] and fake.auth_deleted, "delete works after a fresh sign-in")
	online.setup("", "", HttpTransport.new())


func _test_email_offline_and_ui() -> void:
	# Without firebase.cfg: no email calls, no buttons, the game stays local.
	_clean()
	var online: Node = root.get_node("Online")
	online.setup("", "", HttpTransport.new())
	await online.start()
	check(
		(await online.link_email("a@b.co", "secret12"))["error"] == "not_configured",
		"offline build: link unavailable"
	)
	check(
		(await online.sign_in_email("a@b.co", "secret12"))["error"] == "not_configured",
		"offline build: sign-in unavailable"
	)
	check(
		(await online.send_password_reset("a@b.co"))["error"] == "not_configured",
		"offline build: reset unavailable"
	)
	check(not (await online.sign_out())["ok"], "offline build: nothing to sign out of")
	# Loaded at run time: the scripts name the Online autoload, which a --script test
	# cannot resolve while compiling itself.
	var panel_script: GDScript = load("res://scripts/account_panel.gd")
	var dialog_script: GDScript = load("res://scripts/email_auth_dialog.gd")
	var panel: Control = panel_script.new()
	root.add_child(panel)
	panel.open()
	check(not panel.email_controls_visible(), "offline build: email buttons hidden")
	panel.queue_free()

	# With Firebase: a guest sees the buttons; the dialog validates before sending.
	_clean()
	var fake := Fakes.FakeFirebase.new()
	online = _configured_online(fake)
	await online.start()
	panel = panel_script.new()
	root.add_child(panel)
	panel.open()
	check(panel.email_controls_visible(), "configured build: email buttons shown")
	var dialog: Control = dialog_script.new()
	root.add_child(dialog)
	var modes: Dictionary = dialog_script.Mode
	dialog.open(modes["LINK"])
	dialog.set_fields("not-an-email", "secret12")
	await dialog.submit()
	check(
		dialog.status_text() == EmailRules.message("invalid_email") and dialog.visible,
		"dialog: clear message, stays open"
	)
	check(fake.email_requests.is_empty(), "dialog: nothing sent for a bad email")
	var done: Array = []
	dialog.succeeded.connect(func(kind: String, _r: Dictionary) -> void: done.append(kind))
	dialog.set_fields("zed@example.com", "secret12")
	await dialog.submit()
	check(done == ["link"] and not dialog.visible, "dialog: linked and closed")
	check(dialog._password.text == "" and dialog._email.text == "", "dialog: fields wiped")
	check(online.account_type() == "email", "dialog result reached the account")
	panel.refresh()
	check(panel.email_controls_visible(), "email account keeps its controls (sign out / re-login)")
	dialog.open(modes["SIGN_IN"])
	dialog.set_fields("zed@example.com", "secret12")
	dialog.close()
	check(dialog._password.text == "" and not dialog.visible, "dialog: closing wipes the password")
	dialog.queue_free()
	panel.queue_free()
	online.setup("", "", HttpTransport.new())


## The account code never prints (tokens, emails and passwords pass through it).
func _test_no_secret_logging() -> void:
	var banned := RegEx.new()
	(
		banned
		. compile(
			"(^|[^A-Za-z_.])(print|print_rich|print_debug|printerr|prints|printt|push_error|push_warning)\\("
		)
	)
	var leaks: Array[String] = []
	var files: Array[String] = [
		"auth_service",
		"online",
		"email_auth_dialog",
		"email_rules",
		"account_panel",
		"session_store",
		"firestore_client",
		"http_transport",
	]
	for file: String in files:
		var text: String = FileAccess.get_file_as_string("res://scripts/%s.gd" % file)
		if banned.search(text) != null:
			leaks.append(file)
	check(leaks.is_empty(), "no print/push_error in the account code %s" % [leaks])
