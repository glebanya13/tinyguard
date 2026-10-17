class_name OnlineSession
extends RefCounted
## Session of Online: boot (restores the saved login, migrates old saves, signs in as
## a guest and syncs), the welcome decision of a clean first launch, the account type,
## the remembered uid in the local profile and the wiping of this device's data.

var _ctx: OnlineContext


func _init(context: OnlineContext) -> void:
	_ctx = context


## Boot: restores the session, migrates old saves, signs in as a guest if
## needed and syncs the profile. Idempotent; never blocks the offline game: the
## local profile is read straight from the save, the cloud catches up in the
## background. `allow_new_account` false (the boot scene) stops before creating any
## account on a clean first launch: the player picks "create account", "sign in" or
## "play as guest" on the welcome screen first (needs_welcome()).
func start(allow_new_account: bool = true) -> void:
	if _ctx.started:
		return
	_ctx.started = true
	var cfg: ConfigFile = LevelCatalog.data()
	_ctx.auth.restore(str(cfg.get_value(PlayerProfile.SECTION, "account_uid", "")))
	_ctx.auth.adopt_legacy(
		str(cfg.get_value("online", "uid", "")), str(cfg.get_value("online", "refresh_token", ""))
	)
	PlayerProfile.touch_local()  # migrates a schema-0 save (reads [online] name)
	if cfg.has_section("online"):
		cfg.erase_section("online")  # the refresh token must not stay in plain text
		LevelCatalog.commit()
	remember_uid()
	if not allow_new_account and needs_welcome():
		_ctx.startup_done = true
		_ctx.sync_state_changed.emit(_ctx.sync.sync_state())
		return
	await first_sync()


## Clean first launch with Firebase: no account, no saved session, and the player has
## not yet chosen how to play (Onboarding.welcome_done()).
func needs_welcome() -> bool:
	return (
		_ctx.is_configured()
		and not _ctx.auth.has_session()
		and not _ctx.auth.is_session_lost()
		and not Onboarding.welcome_done()
	)


## "Play without an account" on the welcome screen: remembers the choice (also
## offline) and starts as a guest. The guest account is created in the background.
func choose_guest() -> void:
	Onboarding.mark_welcome_done()
	await first_sync()


func first_sync() -> void:
	if _ctx.is_configured():
		await _ctx.sync.sync_now()
		_ctx.records.flush_records()
		_ctx.daily.flush_daily()
		_ctx.accounts.refresh_email_status()
	_ctx.startup_done = true
	_ctx.sync_state_changed.emit(_ctx.sync.sync_state())


## "local" (no Firebase), "guest", "email" or "none" (not signed in yet).
func account_type() -> String:
	if not _ctx.is_configured():
		return "local"
	return _ctx.auth.account_type if _ctx.auth.uid != "" else "none"


## Explicit choice when the old session cannot be restored: new guest account.
func start_new_guest() -> Dictionary:
	var result: Dictionary = await _ctx.auth.start_new_guest()
	if result["ok"]:
		var p: Dictionary = PlayerProfile.local()
		p["nicknameVerified"] = false
		PlayerProfile.save_local(p)
		_ctx.last_error = ""
		_ctx.sync.sync_now()
	return result


## Erases this device's data (profile, progress, session) and starts over.
func wipe_local() -> void:
	_ctx.auth.forget()
	LevelCatalog.erase_all()
	LevelCatalog.tutorial = false
	_ctx.started = false
	_ctx.startup_done = false
	_ctx.last_error = ""
	_ctx.expired_announced = false
	_ctx.sync.forget_failures()
	_ctx.sync_state_changed.emit(_ctx.sync.sync_state())


func remember_uid() -> void:
	var cfg: ConfigFile = LevelCatalog.data()
	if str(cfg.get_value(PlayerProfile.SECTION, "account_uid", "")) != _ctx.auth.uid:
		cfg.set_value(PlayerProfile.SECTION, "account_uid", _ctx.auth.uid)
		LevelCatalog.commit()


func on_auth_changed() -> void:
	remember_uid()
	_ctx.account_changed.emit()
