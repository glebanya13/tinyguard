class_name OnlineAccounts
extends RefCounted
## Accounts of Online: email sign-up, linking, sign-in, sign-out, verification mails,
## password reset and the deletion of the account from the client (Spark plan, no
## Cloud Functions). Passwords live only inside the call that sends them.

## Pause between two verification mails requested from the profile (seconds).
const VERIFY_COOLDOWN := 60.0

var _ctx: OnlineContext
var _verify_ready_msec: int = 0


func _init(context: OnlineContext) -> void:
	_ctx = context


## Links an email and password to the current guest account (accounts:update):
## the uid, the profile and the progress stay, the account can then be opened on
## another device. {"ok", "error"}; error is an EmailRules message key. The
## password lives only in this call (never stored, never logged).
func link_email(email: String, password: String) -> Dictionary:
	var check: Dictionary = _check_credentials(email, password, true)
	if not check["ok"]:
		return check
	if _ctx.auth.uid == "":
		return await register_email(email, password)  # no guest yet: a clean sign-up
	if _ctx.email_busy:
		return {"ok": false, "error": "busy"}
	_ctx.email_busy = true
	var result: Dictionary = await _ctx.auth.link_email(check["email"], password)
	if result["ok"]:
		Onboarding.mark_welcome_done()
		_ctx.expired_announced = false
		var mail: Dictionary = await _ctx.auth.send_verification()  # the game never waits for it
		result["verification"] = mail["ok"]
		_ctx.auth.changed.emit()
	_ctx.email_busy = false
	if result["ok"]:
		await _ctx.sync.sync_now()  # the progress of the guest goes to the account at once
	return result


## Signs in with email and password. On another device this switches to that
## account: its cloud profile is merged with the local one (progress only grows:
## best stars and records, most open levels; the account's nickname wins, the
## nickname of the abandoned guest is dropped). Signing in again to the account
## that is already open only refreshes the login (needed before deleting it).
## {"ok", "error", "switched", "synced" (the merge reached the cloud)}.
func sign_in_email(email: String, password: String) -> Dictionary:
	var check: Dictionary = _check_credentials(email, password, false)
	if not check["ok"]:
		return {"ok": false, "error": check["error"], "switched": false, "synced": false}
	if _ctx.email_busy:
		return {"ok": false, "error": "busy", "switched": false, "synced": false}
	_ctx.email_busy = true
	if _ctx.sync_busy:
		await _ctx.sync_finished  # a sync of the old account must not meet the new session
	_ctx.switching = true
	var reply: Dictionary = await _ctx.auth.sign_in_email(check["email"], password)
	var result := {"ok": false, "error": str(reply["error"]), "switched": false, "synced": false}
	if reply["ok"]:
		if reply["switched"]:
			_forget_nickname_of_old_account()
		_ctx.last_error = ""
		_ctx.expired_announced = false
		Onboarding.mark_welcome_done()
		result.merge({"ok": true, "error": "", "switched": reply["switched"]}, true)
	_ctx.switching = false
	if reply["ok"]:
		var synced: Dictionary = await _ctx.sync.sync_now()
		result["synced"] = synced["ok"]
		_ctx.startup_done = true
		refresh_email_status()
	_ctx.email_busy = false
	return result


## Registers an email account (email + password, optionally the nickname). On a clean
## first launch it is accounts:signUp; a guest that already has a uid is linked
## instead (accounts:update), so its uid and all its progress stay. A verification
## mail is requested right away; the game is never blocked by an unverified email.
## The nickname is reserved after the account exists; a taken one sends the player to
## the nickname screen. {"ok", "error", "message" (nickname text, optional),
## "nickname" (reserve_nickname reason or ""), "verification" (mail requested),
## "synced"}. The password lives only in this call.
func register_email(email: String, password: String, nickname: String = "") -> Dictionary:
	var check: Dictionary = _check_credentials(email, password, true)
	if not check["ok"]:
		return check
	var nick: Dictionary = {}
	if nickname.strip_edges() != "":
		nick = NicknameRules.validate(nickname)
		if not nick["ok"]:
			return {"ok": false, "error": "nickname_invalid", "message": str(nick["message"])}
	if _ctx.email_busy:
		return {"ok": false, "error": "busy"}
	_ctx.email_busy = true
	_ctx.switching = true
	if _ctx.sync_busy:
		await _ctx.sync_finished
	var reply: Dictionary = {}
	if _ctx.auth.uid == "":
		reply = await _ctx.auth.sign_up_email(check["email"], password)
	else:
		reply = await _ctx.auth.link_email(check["email"], password)
	_ctx.switching = false
	if not reply["ok"]:
		_ctx.email_busy = false
		return {"ok": false, "error": str(reply["error"])}
	Onboarding.mark_welcome_done()
	_ctx.last_error = ""
	_ctx.expired_announced = false
	var out := {"ok": true, "error": "", "nickname": "", "verification": false, "synced": false}
	var mail: Dictionary = await _ctx.auth.send_verification()
	out["verification"] = mail["ok"]
	_ctx.email_busy = false
	if not nick.is_empty():
		var reserved: Dictionary = await _ctx.nicknames.reserve_nickname(nickname)
		out["nickname"] = str(reserved["reason"])
		if reserved["reason"] in ["taken", "invalid", "rate_limited"]:
			Onboarding.set_local_nickname(nick["nickname"], nick["normalized"], false)
			Onboarding.flag_nickname_conflict()
	var synced: Dictionary = await _ctx.sync.sync_now()
	out["synced"] = synced["ok"]
	_ctx.startup_done = true
	_ctx.sync_state_changed.emit(_ctx.sync.sync_state())
	return out


## Mails the confirmation link again (the profile's button; at most once a minute).
## {"ok", "error"}: cooldown, not_configured (no email account), plus the AuthService errors.
func send_verification() -> Dictionary:
	if not _ctx.is_configured() or _ctx.auth.account_type != AuthService.TYPE_EMAIL:
		return {"ok": false, "error": "not_configured"}
	if Time.get_ticks_msec() < _verify_ready_msec:
		return {"ok": false, "error": "cooldown"}
	_verify_ready_msec = Time.get_ticks_msec() + int(VERIFY_COOLDOWN * 1000.0)
	var result: Dictionary = await _ctx.auth.send_verification()
	if not result["ok"]:
		_verify_ready_msec = 0
	return result


## Reads whether the account's email is confirmed (cached on the device, so the
## profile shows the last known state offline). Background; failures keep the cache.
func refresh_email_status() -> void:
	if not _ctx.is_configured() or _ctx.auth.account_type != AuthService.TYPE_EMAIL:
		return
	if not _ctx.auth.has_session():
		return
	await _ctx.auth.refresh_account_info()
	_ctx.account_changed.emit()


## "" | "verified" | "unverified": the email state of an email account (cached).
func email_status() -> String:
	if not _ctx.is_configured() or _ctx.auth.account_type != AuthService.TYPE_EMAIL:
		return ""
	return "verified" if _ctx.auth.email_verified else "unverified"


## "a***@gmail.com" when the address is known in this run, else "". Never stored.
func masked_email() -> String:
	var mail: String = _ctx.auth.email
	var at: int = mail.find("@")
	if at < 1:
		return ""
	return mail.substr(0, 1) + "***" + mail.substr(at)


## True when the soft "create an account so you do not lose progress" reminder is due:
## a guest (or a player who skipped the choice) with at least one win.
func account_reminder_due() -> bool:
	if not _ctx.is_configured() or _ctx.auth.account_type == AuthService.TYPE_EMAIL:
		return false
	return Onboarding.reminder_due(PlayerProfile.local())


## Sends the password reset mail. Unknown addresses look like success on purpose.
## {"ok", "error"}.
func send_password_reset(email: String) -> Dictionary:
	if not _ctx.is_configured():
		return {"ok": false, "error": "not_configured"}
	var check: Dictionary = EmailRules.check_email(email)
	if not check["ok"]:
		return {"ok": false, "error": check["error"]}
	return await _ctx.auth.send_password_reset(check["email"])


## Signs out of an email account: unsaved progress is pushed first (without a
## connection the sign-out is refused so nothing is lost), then this device
## forgets the session and its local data; the progress stays in the cloud under
## the email. A guest cannot sign out (its only copy would be lost).
## {"ok", "error"}.
func sign_out() -> Dictionary:
	if not _ctx.is_configured() or _ctx.auth.account_type != AuthService.TYPE_EMAIL:
		return {"ok": false, "error": "guest_cannot_sign_out"}
	if _ctx.email_busy:
		return {"ok": false, "error": "busy"}
	_ctx.email_busy = true
	var synced: Dictionary = await _ctx.sync.sync_now()
	if not synced["ok"] and PlayerProfile.is_pending():
		_ctx.email_busy = false
		return {"ok": false, "error": "unsynced"}
	_ctx.session.wipe_local()
	_ctx.email_busy = false
	return {"ok": true, "error": ""}


## Deletes the account from the client (Spark plan, no Cloud Functions): the
## player's own Firestore documents (profile, nickname and its index entry,
## records, legacy save), then the Firebase Auth user (accounts:delete), then
## the local data. Safe to repeat after a partial failure. Without Firebase or
## an account only the local data is erased.
## {"ok", "reason", "scope" ("cloud" | "local")}.
func delete_account() -> Dictionary:
	if not _ctx.is_configured() or _ctx.auth.uid == "":
		_ctx.session.wipe_local()
		return {"ok": true, "reason": "", "scope": "local"}
	var signed: Dictionary = await _ctx.auth.ensure_token(false)
	if not signed["ok"]:
		return {"ok": false, "reason": signed["error"], "scope": ""}
	var cleared: Dictionary = await _delete_cloud_data()
	if not cleared["ok"]:
		return {"ok": false, "reason": cleared["reason"], "scope": ""}
	var removed: Dictionary = await _ctx.auth.delete_account()
	if not removed["ok"]:
		return {"ok": false, "reason": removed["error"], "scope": ""}
	_ctx.session.wipe_local()
	return {"ok": true, "reason": "", "scope": "cloud"}


## The player's co-op rooms and Firestore documents. {"ok", "reason"}.
func _delete_cloud_data() -> Dictionary:
	# Co-op rooms (uid, nickname, commands) first: the rules need the signed-in user.
	if not await _ctx.coop.purge_rooms():
		return {"ok": false, "reason": "offline"}
	var plan: Dictionary = await _deletion_writes(_ctx.auth.uid)
	if not plan["ok"]:
		return {"ok": false, "reason": plan["reason"]}
	var writes: Array = plan["writes"]
	var deleted: Dictionary = await _ctx.firestore.commit(writes)
	if not deleted["ok"] and int(deleted.get("code", 0)) == 403 and plan["trace_included"]:
		# The server thinks the nickname trace is younger than 24 hours (clock skew):
		# delete everything else; the trace is inert once the Auth user is gone.
		writes = writes.filter(func(w: Dictionary) -> bool: return not _is_trace_delete(w))
		deleted = await _ctx.firestore.commit(writes)
	if not deleted["ok"]:
		return {"ok": false, "reason": OnlineContext.reply_error(deleted)}
	return {"ok": true, "reason": ""}


## The deletes that remove everything stored under `uid`. The rules only let
## the owner delete an existing nickname index document, so it is looked up first.
## nicknameTrace/{uid} (the 24 hour nickname clock) may only be deleted once 24 hours
## have passed since the last change, so it is included only then.
## {"ok", "reason", "writes", "trace_included"}.
func _deletion_writes(uid: String) -> Dictionary:
	var firestore: FirestoreClient = _ctx.firestore
	var writes: Array = []
	var trace_included := false
	var profile_path: String = "publicProfiles/" + uid
	var public_doc: Dictionary = await firestore.get_doc(profile_path)
	if not public_doc["ok"] and not public_doc["missing"]:
		return {
			"ok": false,
			"reason": OnlineContext.reply_error(public_doc),
			"writes": writes,
			"trace_included": false
		}
	if public_doc["ok"]:
		var key: String = str(public_doc["fields"].get("nicknameNormalized", ""))
		var name_doc: Dictionary = await firestore.get_doc("nicknames/" + key)
		if not name_doc["ok"] and not name_doc["missing"]:
			return {
				"ok": false,
				"reason": OnlineContext.reply_error(name_doc),
				"writes": writes,
				"trace_included": false
			}
		if name_doc["ok"] and str(name_doc["fields"].get("uid", "")) == uid:
			writes.append(firestore.write_delete("nicknames/" + key))
		writes.append(firestore.write_delete(profile_path))
	var trace: Dictionary = await firestore.get_doc("nicknameTrace/" + uid)
	if not trace["ok"] and not trace["missing"]:
		return {
			"ok": false,
			"reason": OnlineContext.reply_error(trace),
			"writes": writes,
			"trace_included": false
		}
	if trace["ok"] and OnlineNicknames.clock_expired(int(trace["fields"].get("changedAt", 0))):
		writes.append(firestore.write_delete("nicknameTrace/" + uid))
		trace_included = true
	writes.append(firestore.write_delete("runs/" + uid))
	writes.append(firestore.write_delete("users/" + uid))
	writes.append(firestore.write_delete("saves/" + uid))
	for level: Dictionary in LevelCatalog.levels():
		var scores: String = "leaderboards/level_%d/scores/%s" % [int(level["id"]), uid]
		writes.append(firestore.write_delete(scores))
	# The daily board only takes today's (or, just after midnight, yesterday's) result.
	var today: String = Daily.today_key()
	for day: String in [today, Daily.yesterday_key(today)]:
		writes.append(firestore.write_delete("daily/%s/scores/%s" % [day, uid]))
	return {"ok": true, "reason": "", "writes": writes, "trace_included": trace_included}


func _is_trace_delete(write: Dictionary) -> bool:
	return str(write.get("delete", "")).contains("/nicknameTrace/")


## {"ok", "error", "email"}: client-side checks before any request is sent.
func _check_credentials(email: String, password: String, new_password: bool) -> Dictionary:
	if not _ctx.is_configured():
		return {"ok": false, "error": "not_configured"}
	var mail: Dictionary = EmailRules.check_email(email)
	if not mail["ok"]:
		return mail
	var word: Dictionary = (
		EmailRules.check_new_password(password)
		if new_password
		else EmailRules.check_password(password)
	)
	if not word["ok"]:
		return word
	return mail


## After switching to another account the nickname of the old guest (reserved
## under its uid) is not ours any more: the account's own nickname comes with the
## next sync, and an account without one is asked for a name.
func _forget_nickname_of_old_account() -> void:
	var p: Dictionary = PlayerProfile.local()
	p["nickname"] = ""
	p["nicknameNormalized"] = ""
	p["nicknameVerified"] = false
	p["nicknameConflict"] = false
	PlayerProfile.save_local(p)
