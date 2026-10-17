# gdlint:disable=max-public-methods
extends Node
## Optional online features over Firebase REST APIs (no SDK, no native
## plugins). Autoload "Online": the only autoload and a thin FACADE with the public
## API of the game; the work is done by plain services that share an OnlineContext:
##   OnlineSession   boot, welcome choice, account type, wiping this device
##   OnlineSync      profile sync (read-merge-write), sync state, auto-sync
##   OnlineNicknames nickname reservation and its 24 hour clock
##   OnlineAccounts  email sign-up / link / sign-in / sign-out, deletion
##   OnlineRecords   endless records, retry queue, level leaderboards
##   OnlineDaily     daily challenge result queue and board
##   OnlineCoop      Realtime Database transport and room cleanup
## Over them sit AuthService, FirestoreClient and RtdbClient (REST). Signals of the
## services come up through the context and are re-emitted here under the old names.
## Without res://firebase.cfg (docs/FIREBASE.md) everything online is disabled and the
## game, the local profile and the onboarding work offline.
## Sent: the anonymous uid, the reserved nickname, progression and settings,
## endless records. An email and password go only to Firebase Auth, only when
## the player links or signs in, and are never stored on the device.
## Never logged: tokens, emails, passwords, raw replies, profile contents.

signal leaderboard_loaded(level_id: int, entries: Array)
signal status_changed(text: String)
## The board of a daily challenge day arrived (best first; empty when offline).
signal daily_loaded(day: String, entries: Array)
signal cloud_loaded(ok: bool)
## See sync_state().
signal sync_state_changed(state: String)
## The signed-in account (uid or type) changed.
signal account_changed
## A sync_now() finished (concurrent callers wait for this).
signal sync_finished(result: Dictionary)
## The saved login stopped working for good (refresh token rejected): the game keeps
## running on the local cache and the map softly offers to sign in again.
signal session_expired

const CONFIG_PATH := "res://firebase.cfg"
const LEADERBOARD_SIZE := OnlineRecords.LEADERBOARD_SIZE
const NAME_MAX := OnlineRecords.NAME_MAX
const ANONYMOUS_NAME := OnlineRecords.ANONYMOUS_NAME
const RECORD_SECTION := OnlineRecords.RECORD_SECTION
const DAILY_SECTION := OnlineDaily.DAILY_SECTION
const STATE_TEXT := OnlineSync.STATE_TEXT

var api_key: String:
	get:
		return _ctx.api_key
	set(value):
		_ctx.api_key = value
var project_id: String:
	get:
		return _ctx.project_id
	set(value):
		_ctx.project_id = value
var auth: AuthService:
	get:
		return _ctx.auth
	set(value):
		_ctx.auth = value
var firestore: FirestoreClient:
	get:
		return _ctx.firestore
	set(value):
		_ctx.firestore = value
## Realtime Database URL for co-op (firebase.cfg "database_url"); "" = co-op off.
var database_url: String:
	get:
		return _ctx.database_url
	set(value):
		_ctx.database_url = value
## Transport of the co-op layer (CoopLobby / CoopSession); null without database_url.
var rtdb: RtdbClient:
	get:
		return _ctx.rtdb
	set(value):
		_ctx.rtdb = value
## The first start() finished (signed in and synced, or failed offline).
var startup_done: bool:
	get:
		return _ctx.startup_done
	set(value):
		_ctx.startup_done = value
## First retry delay of an unsent record, seconds (tests shorten it).
var retry_base: float:
	get:
		return _ctx.retry_base
	set(value):
		_ctx.retry_base = value
## Syncs the profile by itself a few seconds after local progress changed (tests of
## other features keep it off; _ready switches it on).
var auto_sync: bool:
	get:
		return _ctx.auto_sync
	set(value):
		_ctx.auto_sync = value
var sync_debounce: float:
	get:
		return _ctx.sync_debounce
	set(value):
		_ctx.sync_debounce = value
var sync_min_gap: float:
	get:
		return _ctx.sync_min_gap
	set(value):
		_ctx.sync_min_gap = value

var _ctx := OnlineContext.new()
var _transport: HttpTransport = null


func _init() -> void:
	_ctx.host = self
	_ctx.session = OnlineSession.new(_ctx)
	_ctx.sync = OnlineSync.new(_ctx)
	_ctx.nicknames = OnlineNicknames.new(_ctx)
	_ctx.accounts = OnlineAccounts.new(_ctx)
	_ctx.records = OnlineRecords.new(_ctx)
	_ctx.daily = OnlineDaily.new(_ctx)
	_ctx.coop = OnlineCoop.new(_ctx)
	# Signals go up: the services emit on the context, the facade re-emits them.
	_ctx.leaderboard_loaded.connect(leaderboard_loaded.emit)
	_ctx.status_changed.connect(status_changed.emit)
	_ctx.daily_loaded.connect(daily_loaded.emit)
	_ctx.cloud_loaded.connect(cloud_loaded.emit)
	_ctx.sync_state_changed.connect(sync_state_changed.emit)
	_ctx.account_changed.connect(account_changed.emit)
	_ctx.sync_finished.connect(sync_finished.emit)
	_ctx.session_expired.connect(session_expired.emit)


func _ready() -> void:
	var cfg := ConfigFile.new()
	var key := ""
	var project := ""
	var db_url := ""
	# BIMBLEGUARD_OFFLINE=1 (tests/run_all.sh) ignores firebase.cfg: tests never touch a real project.
	var offline: bool = OS.get_environment("BIMBLEGUARD_OFFLINE") == "1"
	if not offline and cfg.load(CONFIG_PATH) == OK:
		key = str(cfg.get_value("firebase", "api_key", ""))
		project = str(cfg.get_value("firebase", "project_id", ""))
		db_url = str(cfg.get_value("firebase", "database_url", ""))
	database_url = db_url
	setup(key, project, HttpTransport.new())
	auto_sync = true
	LevelCatalog.on_committed = _ctx.sync.on_local_committed


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Phone call, home button, task switcher: the process may be killed any moment.
			LevelCatalog.flush()
			_ctx.sync.schedule_auto_sync(0.0)
		NOTIFICATION_WM_GO_BACK_REQUEST:
			LevelCatalog.flush()
		NOTIFICATION_WM_CLOSE_REQUEST:
			LevelCatalog.flush()  # the tree quits by itself right after this
		NOTIFICATION_APPLICATION_RESUMED:
			_ctx.sync.schedule_auto_sync(0.0)


## Parsing helpers of the leaderboard replies (see OnlineRecords).
static func parse_leaderboard(json: Variant) -> Array:
	return OnlineRecords.parse_leaderboard(json)


static func parse_save(json: Variant) -> String:
	return OnlineRecords.parse_save(json)


static func clean_name(value: String) -> String:
	return OnlineRecords.clean_name(value)


static func state_text(state: String) -> String:
	return OnlineSync.state_text(state)


## (Re)wires the services. Tests pass a fake transport and a made-up project.
func setup(key: String, project: String, transport: HttpTransport) -> void:
	if _transport != null and _transport != transport:
		_transport.queue_free()
	_transport = transport
	if transport.get_parent() == null:
		add_child(transport)
	_ctx.api_key = key
	_ctx.project_id = project
	_ctx.auth = AuthService.new()
	_ctx.auth.api_key = key
	_ctx.auth.transport = transport
	_ctx.auth.changed.connect(_ctx.session.on_auth_changed)
	_ctx.firestore = FirestoreClient.new()
	_ctx.firestore.project_id = project
	_ctx.firestore.transport = transport
	_ctx.firestore.auth = _ctx.auth
	_ctx.coop.configure(key)
	_ctx.started = false
	_ctx.startup_done = false
	_ctx.last_error = ""
	_ctx.auto_sync = false
	_ctx.sync_busy = false
	_ctx.email_busy = false
	_ctx.switching = false
	_ctx.sync.reset()


func is_configured() -> bool:
	return _ctx.is_configured()


# --- session ---


func start(allow_new_account: bool = true) -> void:
	await _ctx.session.start(allow_new_account)


func needs_welcome() -> bool:
	return _ctx.session.needs_welcome()


func choose_guest() -> void:
	await _ctx.session.choose_guest()


## "local" (no Firebase), "guest", "email" or "none" (not signed in yet).
func account_type() -> String:
	return _ctx.session.account_type()


func start_new_guest() -> Dictionary:
	return await _ctx.session.start_new_guest()


## Erases only this device's data (profile, progress, session).
func erase_local_data() -> void:
	_ctx.session.wipe_local()


# --- sync ---


func sync_state() -> String:
	return _ctx.sync.sync_state()


func sync_now() -> Dictionary:
	return await _ctx.sync.sync_now()


func cloud_save() -> void:
	await _ctx.sync.cloud_save()


func cloud_load() -> void:
	await _ctx.sync.cloud_load()


# --- nicknames ---


func player_name() -> String:
	return _ctx.nicknames.player_name()


func set_player_name(value: String) -> void:
	_ctx.nicknames.set_player_name(value)


func reserve_nickname(raw: String) -> Dictionary:
	return await _ctx.nicknames.reserve_nickname(raw)


# --- accounts ---


func link_email(email: String, password: String) -> Dictionary:
	return await _ctx.accounts.link_email(email, password)


func sign_in_email(email: String, password: String) -> Dictionary:
	return await _ctx.accounts.sign_in_email(email, password)


func register_email(email: String, password: String, nickname: String = "") -> Dictionary:
	return await _ctx.accounts.register_email(email, password, nickname)


func send_verification() -> Dictionary:
	return await _ctx.accounts.send_verification()


func refresh_email_status() -> void:
	await _ctx.accounts.refresh_email_status()


func email_status() -> String:
	return _ctx.accounts.email_status()


func masked_email() -> String:
	return _ctx.accounts.masked_email()


func account_reminder_due() -> bool:
	return _ctx.accounts.account_reminder_due()


func send_password_reset(email: String) -> Dictionary:
	return await _ctx.accounts.send_password_reset(email)


func sign_out() -> Dictionary:
	return await _ctx.accounts.sign_out()


func delete_account() -> Dictionary:
	return await _ctx.accounts.delete_account()


# --- records and boards ---


func start_run(level_id: int) -> bool:
	return await _ctx.records.start_run(level_id)


func submit_record(level_id: int, wave: int) -> void:
	await _ctx.records.submit_record(level_id, wave)


func has_pending_record() -> bool:
	return _ctx.records.has_pending_record()


func flush_records() -> void:
	await _ctx.records.flush_records()


func fetch_leaderboard(level_id: int) -> void:
	await _ctx.records.fetch_leaderboard(level_id)


func submit_daily(day: String, wave: int) -> void:
	await _ctx.daily.submit_daily(day, wave)


func has_pending_daily() -> bool:
	return _ctx.daily.has_pending_daily()


func flush_daily() -> void:
	await _ctx.daily.flush_daily()


func fetch_daily(day: String) -> void:
	await _ctx.daily.fetch_daily(day)
