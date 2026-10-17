extends SceneTree
## What the player and the tester see when the Firebase answers an email request with
## an error: every server answer has its own message key, the raw server code
## ("detail") travels up to the dialog, contains no address, password or token, and a guest
## is never damaged by a refused linking. Fake server only (tests/fakes.gd).
## godot --headless --path . --script res://tests/test_email_errors.gd

const SAVE := "user://test_email_errors.cfg"
const SESSION := "user://test_email_errors_session.dat"
const Fakes := preload("res://tests/fakes.gd")
const MAIL := "ana@example.com"
const WORD := "hunter22-secret"
## EmailAuthDialog.Mode (the class is loaded at run time: it needs the Online autoload).
const MODE_LINK := 0
const MODE_SIGN_IN := 1

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
	_test_codes()
	await _test_link_modes()
	await _test_other_requests()
	await _test_dialog()
	_clean()
	root.get_node("Online").setup("", "", HttpTransport.new())
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _online(fake: Fakes.FakeFirebase) -> Node:
	var online: Node = root.get_node("Online")
	var t := Fakes.FakeTransport.new()
	t.handler = fake.handle
	online.setup("test-key", "test-project", t)
	online.auth.backoff_scale = 0.0
	online.firestore.backoff_scale = 0.0
	return online


func _clean_detail(detail: String, where: String) -> void:
	var bad: bool = (
		detail == ""
		or detail.contains("@")
		or detail.contains(WORD)
		or detail.contains("ID:")
		or detail.contains("RT:")
		or detail.contains("example")
	)
	check(not bad, "%s: detail is there and carries no secrets (%s)" % [where, detail])


func _test_codes() -> void:
	var blocked: Array = Fakes.FakeFirebase.err_key_blocked()
	var reply := {"ok": false, "code": blocked[0], "json": blocked[1], "network": false}
	check(
		AuthErrors.detail(reply) == "HTTP 403 PERMISSION_DENIED API_KEY_SERVICE_BLOCKED",
		"status and reason are read: " + AuthErrors.detail(reply)
	)
	check(
		AuthErrors.key(reply, AuthErrors.LINK_ERRORS) == "key_restricted", "403 -> key_restricted"
	)
	# Text typed by the player (an address) is never taken from a message.
	var hostile := {
		"ok": false,
		"code": 400,
		"json": {"error": {"message": MAIL + " is bad", "status": "token abc"}},
		"network": false,
	}
	check(not AuthErrors.detail(hostile).contains("@"), "an address in a message is dropped")
	check(AuthErrors.detail(hostile) == "HTTP 400 (unknown body)", "unknown body noted")
	var nobody := {"ok": false, "code": 400, "json": null, "network": false}
	check(AuthErrors.detail(nobody) == "HTTP 400 (no body)", "400 without a body")
	var timeout := {"ok": false, "code": 0, "json": null, "network": true}
	check(AuthErrors.detail(timeout).begins_with("no reply"), "a timeout is named")
	check(AuthErrors.key(timeout, AuthErrors.LINK_ERRORS) == "offline", "timeout -> offline")
	for key: String in [
		"link_disabled",
		"signup_disabled",
		"signin_disabled",
		"reset_disabled",
		"verify_disabled",
		"signup_closed",
		"key_restricted",
		"config_missing",
	]:
		check(EmailRules.MESSAGES.has(key), "message exists: " + key)
		check(
			(
				EmailRules.message(key) != EmailRules.message("nonsense")
				and EmailRules.message(key) != ""
			),
			"text is not generic: " + key
		)
	check(
		EmailRules.message("link_disabled") != EmailRules.message("signin_disabled"),
		"link and sign-in texts differ"
	)


## accounts:update (linking a guest) with every kind of failure: the guest stays intact.
func _test_link_modes() -> void:
	_clean()
	var fake := Fakes.FakeFirebase.new()
	var online: Node = _online(fake)
	await online.start()
	LevelCatalog.complete(1, 3)
	await online.sync_now()
	var cases: Array = [
		[Fakes.FakeFirebase.err_operation_not_allowed(), "link_disabled", "OPERATION_NOT_ALLOWED"],
		[Fakes.FakeFirebase.err_admin_only(), "signup_closed", "ADMIN_ONLY_OPERATION"],
		[Fakes.FakeFirebase.err_key_blocked(), "key_restricted", "API_KEY_SERVICE_BLOCKED"],
		[Fakes.FakeFirebase.err_no_body(), "server", "no body"],
		[Fakes.FakeFirebase.err_timeout(), "offline", "no reply"],
		[
			[400, {"error": {"message": "CONFIGURATION_NOT_FOUND"}}],
			"config_missing",
			"CONFIGURATION_NOT_FOUND"
		],
		[
			[400, {"error": {"message": "CREDENTIAL_TOO_OLD_LOGIN_AGAIN"}}],
			"reauth_required",
			"CREDENTIAL_TOO_OLD_LOGIN_AGAIN"
		],
		[[400, {"error": {"message": "EMAIL_EXISTS"}}], "credential_in_use", "EMAIL_EXISTS"],
	]
	for row: Array in cases:
		fake.forced_raw["accounts:update"] = row[0]
		var r: Dictionary = await online.link_email(MAIL, WORD)
		check(not r["ok"] and r["error"] == row[1], "link %s -> %s" % [row[2], r["error"]])
		check(str(r.get("detail", "")).contains(row[2]), "link detail has " + row[2])
		_clean_detail(str(r.get("detail", "")), "link " + row[2])
		var session: Dictionary = SessionStore.load_session()
		check(
			(
				online.account_type() == "guest"
				and online.uid() == "uid1"
				and session["uid"] == "uid1"
				and session["account_type"] == "guest"
				and LevelCatalog.stars(1) == 3
				and not fake.accounts.has(MAIL)
			),
			"guest and progress untouched after " + row[2]
		)
	fake.forced_raw.clear()
	var ok: Dictionary = await online.link_email(MAIL, WORD)
	check(ok["ok"] and online.account_type() == "email", "after the failures linking still works")
	var note: String = CrashTrace.last_auth_text()
	check(note.begins_with("last auth error: link "), "the last failure is in the diagnostics")
	check(not note.contains("@") and not note.contains(WORD), "the diagnostics note has no secrets")


## Sign-up, sign-in, reset, verification, lookup with a failing server.
func _test_other_requests() -> void:
	_clean()
	var fake := Fakes.FakeFirebase.new()
	var online: Node = _online(fake)
	var auth: AuthService = online.auth
	auth.restore("")
	# Clean first launch: a refused sign-up leaves no session behind.
	fake.forced_raw["signUp"] = Fakes.FakeFirebase.err_operation_not_allowed()
	var r: Dictionary = await auth.sign_up_email(MAIL, WORD)
	check(r["error"] == "signup_disabled" and "OPERATION_NOT_ALLOWED" in r["detail"], "sign-up")
	_clean_detail(r["detail"], "sign-up")
	check(auth.uid == "" and not auth.has_session(), "no broken session after a refused sign-up")
	check(SessionStore.load_session().is_empty(), "nothing saved after a refused sign-up")
	fake.forced_raw["signUp"] = Fakes.FakeFirebase.err_admin_only()
	r = await auth.sign_up_email(MAIL, WORD)
	check(r["error"] == "signup_closed" and "ADMIN_ONLY_OPERATION" in r["detail"], "admin only")
	fake.forced_raw.clear()
	# Sign-in.
	fake.forced_raw["signInWithPassword"] = Fakes.FakeFirebase.err_operation_not_allowed()
	r = await auth.sign_in_email(MAIL, WORD)
	check(r["error"] == "signin_disabled" and "OPERATION_NOT_ALLOWED" in r["detail"], "sign-in")
	_clean_detail(r["detail"], "sign-in")
	fake.forced_raw["signInWithPassword"] = Fakes.FakeFirebase.err_key_blocked()
	r = await auth.sign_in_email(MAIL, WORD)
	check(r["error"] == "key_restricted" and "API_KEY_SERVICE_BLOCKED" in r["detail"], "key")
	fake.forced_raw.clear()
	r = await auth.sign_in_email(MAIL, WORD)
	check(
		r["error"] == "invalid_credentials" and "INVALID_LOGIN_CREDENTIALS" in r["detail"],
		"a wrong password keeps its code in the detail"
	)
	# Reset.
	fake.forced_raw["sendOobCode"] = Fakes.FakeFirebase.err_operation_not_allowed()
	r = await auth.send_password_reset(MAIL)
	check(r["error"] == "reset_disabled" and "OPERATION_NOT_ALLOWED" in r["detail"], "reset")
	_clean_detail(r["detail"], "reset")
	fake.forced_raw["sendOobCode"] = Fakes.FakeFirebase.err_timeout()
	r = await auth.send_password_reset(MAIL)
	check(r["error"] == "offline", "reset timeout")
	fake.forced_raw.clear()
	# A guest session: verification and lookup failures.
	var guest: Dictionary = await auth.ensure_token(true)
	check(guest["ok"] and auth.account_type == "guest", "a guest to test with")
	fake.forced_raw["sendOobCode"] = Fakes.FakeFirebase.err_key_blocked()
	r = await auth.send_verification()
	check(r["error"] == "key_restricted" and "PERMISSION_DENIED" in r["detail"], "verify")
	fake.forced_raw.clear()
	fake.forced_raw["accounts:lookup"] = Fakes.FakeFirebase.err_no_body()
	r = await auth.refresh_account_info()
	check(not r["ok"] and r["error"] == "server" and "no body" in r["detail"], "lookup")
	fake.forced_raw.clear()
	check(auth.uid == "uid1" and auth.has_session(), "the guest session survived all of it")
	# The refresh token endpoint: the detail of a failed refresh is kept for the overlay.
	fake.forced_raw["securetoken"] = Fakes.FakeFirebase.err_timeout()
	auth.invalidate_token()
	var token: Dictionary = await auth.ensure_token(false)
	check(token["error"] == "offline" and str(token.get("detail", "")) != "", "refresh detail")
	fake.forced_raw.clear()


func _test_dialog() -> void:
	_clean()
	var fake := Fakes.FakeFirebase.new()
	var online: Node = _online(fake)
	await online.start()
	var dialog_script: GDScript = load("res://scripts/email_auth_dialog.gd")
	var dialog = dialog_script.new()  # gdlint:disable=untyped
	root.add_child(dialog)
	await process_frame
	dialog.open(MODE_LINK)
	check(dialog.password_hidden(), "the password is hidden by default")
	dialog.set_fields(MAIL, WORD)
	fake.forced_raw["accounts:update"] = Fakes.FakeFirebase.err_operation_not_allowed()
	await dialog.submit()
	check(dialog.status_text() == EmailRules.message("link_disabled"), "message of the dialog")
	check(
		dialog.detail_text().contains("OPERATION_NOT_ALLOWED") and dialog.report_visible(),
		"the code and the report button are shown: " + dialog.detail_text()
	)
	var report: String = dialog.report_text()
	check(
		report.contains("OPERATION_NOT_ALLOWED") and report.contains("uid1"),
		"the report has the code and the player ID: " + report
	)
	check(not report.contains(WORD) and not report.contains("@"), "the report has no secrets")
	dialog.send_report()
	check(online.account_type() == "guest", "still a guest")
	# A taken address leads to the sign-in.
	fake.forced_raw.clear()
	fake.accounts[MAIL] = {"password": "x", "uid": "other"}
	dialog.set_fields(MAIL, WORD)
	await dialog.submit()
	check(dialog.alt_mode() == MODE_SIGN_IN, "EMAIL_EXISTS offers to sign in with this address")
	dialog.take_alt()
	check(
		dialog.mode() == MODE_SIGN_IN and not dialog.report_visible(),
		"the button opens the sign-in form"
	)
	# The old login is too old: sign in again.
	dialog.open(MODE_LINK)
	fake.forced_raw["accounts:update"] = [
		400, {"error": {"message": "CREDENTIAL_TOO_OLD_LOGIN_AGAIN"}}
	]
	dialog.set_fields("new@example.com", WORD)
	await dialog.submit()
	check(dialog.alt_mode() == MODE_SIGN_IN, "reauth offers signing in again")
	# Success clears the fields and the password is hidden again.
	fake.forced_raw.clear()
	dialog.open(MODE_LINK)
	dialog.set_fields("fresh@example.com", WORD)
	await dialog.submit()
	check(online.account_type() == "email" and not dialog.visible, "linked, dialog closed")
	dialog.open(MODE_LINK)
	check(dialog.status_text() == "" and dialog.detail_text() == "", "a reopened dialog is clean")
	check(not dialog.report_visible() and dialog.password_hidden(), "and the password hidden")
	dialog.queue_free()
