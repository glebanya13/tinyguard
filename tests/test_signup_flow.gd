extends SceneTree
## Sign-up and "stay signed in" flow without network (fake Firebase, tests/fakes.gd):
## the welcome gate on a clean first launch, registration with errors, verification
## mail and status, automatic sign-in at the next launch (also offline) on the cached
## profile, token refresh, an expired session, guest -> account with progress moving to
## the cloud, signing in on a "second device", saving when the app goes to the
## background, a damaged save restored from its backup, debounced cloud sync, the soft
## reminder. Nothing here reaches a real Firebase project.
## godot --headless --path . --script res://tests/test_signup_flow.gd

const SAVE := "user://test_signup_flow.cfg"
const SESSION := "user://test_signup_flow_session.dat"
const Fakes := preload("res://tests/fakes.gd")

var fails := 0
var _expired: Array[int] = []


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
	await _test_welcome_gate()
	await _test_registration()
	await _test_next_launch()
	await _test_expired_session()
	await _test_guest_to_account()
	await _test_second_device()
	await _test_guest_options()
	_test_save_on_background()
	_test_damaged_saves()
	await _test_auto_sync()
	_test_reminder()
	_clean()
	root.get_node("Online").setup("", "", HttpTransport.new())
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


## A fresh "process": new services over the same fake server, the save re-read from disk.
func _launch(fake: Fakes.FakeFirebase) -> Node:
	var online: Node = root.get_node("Online")
	var t := Fakes.FakeTransport.new()
	t.handler = fake.handle
	online.setup("test-key", "test-project", t)
	online.auth.backoff_scale = 0.0
	online.firestore.backoff_scale = 0.0
	_reload_save()
	return online


## Forgets the cached save so the next read comes from the disk, like a new process.
func _reload_save() -> void:
	LevelCatalog.save_path = "user://other_signup.cfg"
	LevelCatalog.data()
	LevelCatalog.save_path = SAVE
	LevelCatalog.data()


func _count(online: Node, fragment: String) -> int:
	return online._transport.count(fragment)


func _test_welcome_gate() -> void:
	_clean()
	var fake := Fakes.FakeFirebase.new()
	var online: Node = _launch(fake)
	await online.start(false)
	check(online.needs_welcome(), "clean first launch: the welcome screen is needed")
	check(_count(online, "signUp") == 0, "no account is created before the player chooses")
	check(online.startup_done, "boot does not wait for anything")
	var profile: Dictionary = PlayerProfile.local()
	check(
		Onboarding.route(profile, online.needs_welcome()) == Onboarding.Route.WELCOME,
		"route: welcome first"
	)
	check(
		Onboarding.route(profile) == Onboarding.Route.NICKNAME, "route without the gate: nickname"
	)
	# Offline "play without an account": the choice is remembered, nothing is created yet.
	fake.offline = true
	await online.choose_guest()
	check(Onboarding.welcome_done() and not online.needs_welcome(), "guest choice is remembered")
	check(online.auth.uid == "", "offline: no guest account yet")
	online = _launch(fake)
	await online.start(false)
	check(not online.needs_welcome(), "the welcome screen is not shown again")
	fake.offline = false
	await online.sync_now()
	check(online.auth.uid == "uid1" and online.account_type() == "guest", "guest appears online")


func _test_registration() -> void:
	_clean()
	var fake := Fakes.FakeFirebase.new()
	fake.accounts["taken@example.com"] = {"password": "abcdef", "uid": "someone"}
	var online: Node = _launch(fake)
	await online.start(false)
	# Refused before any request.
	var r: Dictionary = await online.register_email("nope", "secret12", "Сова")
	check(r["error"] == "invalid_email", "register: bad email")
	r = await online.register_email("a@b.co", "123", "Сова")
	check(r["error"] == "weak_password", "register: short password")
	r = await online.register_email("a@b.co", "secret12", "x")
	check(
		r["error"] == "nickname_invalid" and str(r["message"]) != "", "register: nickname rule text"
	)
	check(_count(online, "signUp") == 0, "register: invalid input sends nothing")
	# Server answers.
	r = await online.register_email("taken@example.com", "secret12", "Сова")
	check(r["error"] == "credential_in_use", "register: EMAIL_EXISTS")
	fake.min_password = 8
	r = await online.register_email("ana@example.com", "abcdefg", "Сова")
	check(r["error"] == "weak_password", "register: server WEAK_PASSWORD")
	fake.min_password = 6
	fake.offline = true
	r = await online.register_email("ana@example.com", "hunter22", "Сова")
	check(r["error"] == "offline", "register offline: a clear error")
	check(online.auth.uid == "" and online.needs_welcome(), "failed registration changes nothing")
	fake.offline = false
	# Success.
	LevelCatalog.complete(1, 2)
	r = await online.register_email("  Ana@Example.com ", "hunter22", "Сова")
	check(r["ok"], "registered")
	check(online.auth.uid == "uid1" and online.account_type() == "email", "signed in as email")
	var sign_ups: Array = fake.email_requests.filter(
		func(q: Dictionary) -> bool: return "signUp" in q["url"]
	)
	var sent: Dictionary = sign_ups[-1]["body"]
	check(
		sent["email"] == "Ana@Example.com" and sent["password"] == "hunter22",
		"signUp carries the trimmed email and the password"
	)
	check(_count(online, "accounts:update") == 0, "a clean start signs up, it does not link")
	check(fake.verify_mails == ["ana@example.com"] and r["verification"], "verification mail sent")
	check(PlayerProfile.local()["nickname"] == "Сова", "nickname kept")
	check(r["nickname"] == "reserved", "nickname reserved")
	check(fake.docs.has("publicProfiles/uid1"), "nickname stored in the cloud")
	check(
		fake.users_doc != null and fake.users_doc["progression"]["stars"]["1"] == 2,
		"local progress went to the new account"
	)
	check(not online.needs_welcome() and Onboarding.welcome_done(), "welcome is done")
	var disk: String = (
		FileAccess.get_file_as_string(SAVE)
		+ JSON.stringify(SessionStore.load_session())
		+ FileAccess.get_file_as_bytes(SESSION).get_string_from_ascii()
	)
	check(not "hunter22" in disk and not "xample.com" in disk, "password and email never on disk")
	# Email status: unconfirmed, then confirmed after the click on the link.
	check(online.email_status() == "unverified", "status: not confirmed yet")
	check(online.masked_email() == "A***@Example.com", "masked address %s" % online.masked_email())
	var again: Dictionary = await online.send_verification()
	check(again["ok"] and fake.verify_mails.size() == 2, "the mail can be sent again")
	again = await online.send_verification()
	check(again["error"] == "cooldown", "but not twice within a minute")
	fake.verified.append("ana@example.com")
	await online.refresh_email_status()
	check(online.email_status() == "verified", "status: confirmed")
	check(SessionStore.load_session().get("email_verified", false) == true, "status is cached")
	check(online.masked_email() != "" and SessionStore.load_session().has("uid"), "session saved")
	# A game is never blocked by an unconfirmed email: nothing in the flow awaited it.
	check(Onboarding.route(PlayerProfile.local()) == Onboarding.Route.TUTORIAL, "game flow goes on")


func _test_next_launch() -> void:
	var fake := Fakes.FakeFirebase.new()
	fake.users_doc = null
	# Rebuild the state of a registered player on the server for a clean run.
	_clean()
	var seed_online: Node = _launch(fake)
	await seed_online.start(false)
	await seed_online.register_email("bob@example.com", "hunter22", "Бобр")
	LevelCatalog.complete(1, 3)
	LevelCatalog.complete(2, 1)
	Onboarding.complete_tutorial()
	await seed_online.sync_now()
	# Next launch, no network at all.
	fake.offline = true
	var online: Node = _launch(fake)
	online.start(false)  # not awaited, as the boot scene does
	check(not online.needs_welcome(), "returning player: no welcome")
	check(online.auth.uid == "uid1" and online.account_type() == "email", "signed in at once")
	var p: Dictionary = PlayerProfile.local()
	check(
		p["nickname"] == "Бобр" and p["progression"]["stars"]["1"] == 3,
		"the cached profile is there before any network answer"
	)
	check(
		Onboarding.route(p, online.needs_welcome()) == Onboarding.Route.MAP,
		"straight to the map, no screens"
	)
	await online.sync_finished
	check(online.sync_state() == "offline", "offline launch: state offline")
	check(
		online.state_text("offline") == TranslationServer.translate("SYNC_OFFLINE"),
		"the profile says it will sync later"
	)
	check(SessionStore.load_session()["uid"] == "uid1", "the session survived the failed refresh")
	# Network is back: the refresh token is used, no sign-in with a password.
	fake.offline = false
	online = _launch(fake)
	await online.start(false)
	check(online.sync_state() == "synced", "online launch syncs in the background")
	check(
		_count(online, "securetoken") >= 1 and _count(online, "signInWithPassword") == 0,
		"token refreshed from the stored refresh token"
	)
	check(_count(online, "signUp") == 0, "no new account")
	check(online.auth.is_token_fresh(), "a fresh id token")
	# The id token expires: the next call refreshes it quietly.
	online.auth.clock = func() -> float: return Time.get_unix_time_from_system() + 4000.0
	check(not online.auth.is_token_fresh(), "token expired by the clock")
	var before: int = _count(online, "securetoken")
	check((await online.auth.ensure_token(false))["ok"], "ensure_token refreshes")
	check(_count(online, "securetoken") == before + 1, "exactly one refresh request")
	online.auth.clock = Time.get_unix_time_from_system


func _test_expired_session() -> void:
	var fake := Fakes.FakeFirebase.new()
	_clean()
	var online: Node = _launch(fake)
	await online.start(false)
	await online.register_email("eve@example.com", "hunter22", "Ева")
	LevelCatalog.complete(1, 3)
	Onboarding.complete_tutorial()
	await online.sync_now()
	_expired.clear()
	online = _launch(fake)
	online.session_expired.connect(func() -> void: _expired.append(1))
	fake.forced["securetoken"] = "TOKEN_EXPIRED"
	await online.start(false)
	check(online.sync_state() == "session_lost", "refresh token rejected: session lost")
	check(_expired == [1], "the expiry is announced once")
	check(online.account_type() == "email", "still the same email account")
	check(PlayerProfile.local()["progression"]["stars"]["1"] == 3, "local progress kept")
	check(PlayerProfile.local()["nickname"] == "Ева", "nickname kept")
	check(
		Onboarding.route(PlayerProfile.local(), online.needs_welcome()) == Onboarding.Route.MAP,
		"no welcome loop"
	)
	await online.sync_now()
	check(_expired == [1], "not announced again")
	# Signing in again restores sync without losing anything.
	fake.forced.clear()
	var r: Dictionary = await online.sign_in_email("eve@example.com", "hunter22")
	check(r["ok"] and not r["switched"], "signed in again to the same account")
	check(online.sync_state() == "synced", "syncing again")
	check(PlayerProfile.local()["progression"]["stars"]["1"] == 3, "progress intact after re-login")


func _test_guest_to_account() -> void:
	var fake := Fakes.FakeFirebase.new()
	_clean()
	var online: Node = _launch(fake)
	await online.start(false)
	await online.choose_guest()
	check(online.account_type() == "guest" and online.auth.uid == "uid1", "guest")
	await online.reserve_nickname("Гость")
	LevelCatalog.complete(1, 3)
	LevelCatalog.complete(2, 2)
	Onboarding.complete_tutorial()
	var before: int = _count(online, "signUp")
	var r: Dictionary = await online.register_email("gus@example.com", "hunter22")
	check(r["ok"], "guest registered")
	check(online.auth.uid == "uid1", "the uid stays")
	check(_count(online, "accounts:update") == 1, "the guest is linked (accounts:update)")
	check(_count(online, "signUp") == before, "no second account is created")
	check(
		(
			fake.users_doc["progression"]["stars"]["1"] == 3
			and fake.users_doc["progression"]["stars"]["2"] == 2
		),
		"the guest's progress is in the cloud of the same uid"
	)
	check(PlayerProfile.local()["nickname"] == "Гость", "the guest's nickname stays")
	check(fake.verify_mails == ["gus@example.com"], "verification mail requested")
	check(not online.account_reminder_due(), "no reminder for an account")


func _test_second_device() -> void:
	var fake := Fakes.FakeFirebase.new()
	_clean()
	var online: Node = _launch(fake)
	await online.start(false)
	await online.register_email("dan@example.com", "hunter22", "Дан")
	LevelCatalog.complete(1, 3)
	LevelCatalog.complete(3, 2)
	Onboarding.complete_tutorial()
	await online.sync_now()
	# Sign out (progress is in the cloud), local data gone.
	var out: Dictionary = await online.sign_out()
	check(out["ok"], "signed out")
	check(PlayerProfile.local()["progression"]["stars"].is_empty(), "this device is clean")
	check(not Onboarding.welcome_done() and online.needs_welcome(), "welcome again after sign-out")
	# "Second device": sign in from the welcome screen.
	online = _launch(fake)
	await online.start(false)
	check(online.needs_welcome(), "second device: welcome")
	var wrong: Dictionary = await online.sign_in_email("dan@example.com", "WRONG")
	check(wrong["error"] == "invalid_credentials", "wrong password")
	var r: Dictionary = await online.sign_in_email("dan@example.com", "hunter22")
	check(r["ok"] and r["synced"], "signed in and synced")
	var p: Dictionary = PlayerProfile.local()
	check(
		p["progression"]["stars"]["1"] == 3 and p["progression"]["stars"]["3"] == 2,
		"the cloud profile came down"
	)
	check(p["nickname"] == "Дан", "nickname came from the account")
	check(not online.needs_welcome(), "no welcome after sign-in")
	check(
		Onboarding.route(p, online.needs_welcome()) == Onboarding.Route.MAP,
		"existing account skips the nickname and the tutorial"
	)


func _test_guest_options() -> void:
	var fake := Fakes.FakeFirebase.new()
	_clean()
	var online: Node = _launch(fake)
	await online.start(false)
	await online.choose_guest()
	LevelCatalog.complete(1, 3)
	check(online.account_reminder_due(), "a guest with a win gets the reminder")
	check(
		(await online.sign_out())["error"] == "guest_cannot_sign_out",
		"a guest cannot sign out and lose progress"
	)
	check(LevelCatalog.stars(1) == 3, "guest progress untouched")
	# Offline guest keeps playing: wins are saved locally.
	fake.offline = true
	LevelCatalog.complete(2, 2)
	check(LevelCatalog.stars(2) == 2, "offline progress saved locally")
	check(PlayerProfile.is_pending(), "and waits for the network")


func _test_save_on_background() -> void:
	_clean()
	var online: Node = root.get_node("Online")
	online.setup("", "", HttpTransport.new())
	var cfg: ConfigFile = LevelCatalog.data()
	cfg.set_value("progress", "unlocked", 4)  # changed in memory, not committed
	check(ConfigFile.new().load(SAVE) != OK, "nothing on disk yet")
	online.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	var disk := ConfigFile.new()
	check(
		disk.load(SAVE) == OK and int(disk.get_value("progress", "unlocked", 0)) == 4,
		"paused: the save is flushed"
	)
	cfg.set_value("progress", "unlocked", 5)
	online.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(
		disk.load(SAVE) == OK and int(disk.get_value("progress", "unlocked", 0)) == 5,
		"close request: flushed"
	)
	cfg.set_value("progress", "unlocked", 6)
	online.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(
		disk.load(SAVE) == OK and int(disk.get_value("progress", "unlocked", 0)) == 6,
		"focus out: flushed"
	)
	check(not FileAccess.file_exists(SAVE + ".tmp"), "no temp file left behind")


func _test_damaged_saves() -> void:
	_clean()
	var real: String = ProjectSettings.globalize_path(SAVE)
	LevelCatalog.complete(1, 2)
	LevelCatalog.complete(2, 3)  # the previous good file becomes .bak
	check(ConfigFile.new().load(SAVE + ".bak") == OK, "a backup of the previous good state exists")
	var f := FileAccess.open(real, FileAccess.WRITE)
	f.store_string("[progress\nunlocked = = =")
	f.close()
	_reload_save()
	check(LevelCatalog.stars(1) == 2, "damaged save: restored from the backup")
	LevelCatalog.complete(3, 1)
	check(
		ConfigFile.new().load(SAVE) == OK and LevelCatalog.stars(3) == 1,
		"and the next write repairs the main file"
	)
	check(ConfigFile.new().load(SAVE + ".bak") == OK, "the backup is never the damaged file")
	# Both files damaged: kept aside, progress from now on is saved.
	for suffix in ["", ".bak"]:
		f = FileAccess.open(real + suffix, FileAccess.WRITE)
		f.store_string("[progress\nunlocked = = =")
		f.close()
	_reload_save()
	LevelCatalog.complete(1, 3)
	check(LevelCatalog.stars(1) == 3 and ConfigFile.new().load(SAVE) == OK, "fresh save is written")
	check(FileAccess.file_exists(SAVE + ".corrupt"), "the unreadable file is kept as .corrupt")
	# The session file has a backup as well.
	_clean()
	check(SessionStore.save_session({"uid": "u1", "refresh_token": "R1"}), "session saved")
	check(SessionStore.save_session({"uid": "u1", "refresh_token": "R2"}), "session saved again")
	f = FileAccess.open(ProjectSettings.globalize_path(SESSION), FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	var session: Dictionary = SessionStore.load_session()
	check(session.get("refresh_token", "") == "R1", "damaged session: previous good one is used")
	_clean()


func _test_auto_sync() -> void:
	var fake := Fakes.FakeFirebase.new()
	_clean()
	var online: Node = _launch(fake)
	await online.start(false)
	await online.register_email("kim@example.com", "hunter22", "Ким")
	Onboarding.complete_tutorial()
	await online.sync_now()
	online.auto_sync = true
	online.sync_debounce = 0.05
	online.sync_min_gap = 0.0
	var before: int = fake.commits.size()
	LevelCatalog.complete(1, 3)
	LevelCatalog.complete(2, 2)
	LevelCatalog.save_endless(1, 7)
	check(fake.commits.size() == before, "the sync waits for the pause (debounce)")
	await create_timer(0.6).timeout
	check(fake.commits.size() == before + 1, "a burst of changes becomes one write")
	check(
		(
			fake.users_doc["progression"]["stars"]["2"] == 2
			and fake.users_doc["progression"]["endless"]["1"] == 7
		),
		"the cloud has the new progress"
	)
	check(not PlayerProfile.is_pending(), "nothing pending afterwards")
	# Offline: it keeps trying with a back-off, but the game is not affected.
	fake.offline = true
	LevelCatalog.complete(3, 1)
	await create_timer(0.3).timeout
	check(PlayerProfile.is_pending() and LevelCatalog.stars(3) == 1, "offline: pending, saved")
	fake.offline = false
	online.auto_sync = false


func _test_reminder() -> void:
	_clean()
	var profile: Dictionary = PlayerProfile.local()
	check(not Onboarding.reminder_due(profile), "no reminder without a win")
	LevelCatalog.complete(1, 1)
	profile = PlayerProfile.local()
	check(Onboarding.reminder_due(profile), "reminder after the first win")
	Onboarding.dismiss_reminder()
	check(not Onboarding.reminder_due(PlayerProfile.local()), "'later' hides it")
	var cfg: ConfigFile = LevelCatalog.data()
	cfg.set_value(
		PlayerProfile.SECTION,
		"reminder_at",
		int(Time.get_unix_time_from_system()) - Onboarding.REMIND_EVERY - 5
	)
	check(Onboarding.reminder_due(PlayerProfile.local()), "it comes back after a few days")
