class_name AuthService
extends RefCounted
## Firebase Authentication over its REST APIs (Identity Toolkit + Secure Token),
## no SDK and no native plugin. Providers:
## - anonymous (guest): accounts:signUp, the default on first launch;
## - email/password registration on a clean first launch: accounts:signUp with the
##   email and password (instead of an anonymous account); a guest that already has
##   a uid is linked with accounts:update instead, so its uid and progress stay;
## - email verification mail: accounts:sendOobCode (VERIFY_EMAIL), status through
##   accounts:lookup; the game is never blocked by an unverified email;
## - email/password linking of a guest: accounts:update with the guest idToken
##   (keeps the uid, so the profile and progress stay);
## - email/password sign-in on another device: accounts:signInWithPassword
##   (switches to the uid of that account; merging the profiles is Online's job);
## - password reset mail: accounts:sendOobCode (PASSWORD_RESET), no session needed;
## - IdP linking (Google, Play Games...): accounts:signInWithIdp needs an id
##   token from a native sign-in, which CLAUDE.md forbids, so link_with_idp()
##   answers "not_available". Design in docs/ACCOUNTS.md.
##
## Rules this class keeps:
## - one token refresh / sign-up in flight; concurrent callers share its result;
## - transient failures (no reply, 429, 5xx) are retried a few times with
##   backoff, except sign-up (not idempotent: a retry could make two accounts);
## - a known uid whose refresh token is merely unreachable (offline, server
##   error, unreadable session file) is never replaced by a new guest account;
##   only a refresh token the server rejects for good on a guest account leads
##   to a new guest (and only when the caller allows creating one);
## - tokens, emails, passwords and raw replies are never printed; a password is
##   only a function argument here and is never stored (the session file holds
##   the uid and the refresh token).

## Emitted when the uid or the account type changes.
signal changed
## A token request finished (concurrent ensure_token() callers wait for this).
signal token_request_finished(result: Dictionary)

const SIGN_UP_URL := "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s"
const UPDATE_URL := "https://identitytoolkit.googleapis.com/v1/accounts:update?key=%s"
const SIGN_IN_URL := "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=%s"
const OOB_URL := "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=%s"
const LOOKUP_URL := "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=%s"
const DELETE_URL := "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=%s"
const REFRESH_URL := "https://securetoken.googleapis.com/v1/token?key=%s"
const TYPE_GUEST := "guest"
const TYPE_EMAIL := "email"
## Refresh this long before the id token expires (seconds).
const EXPIRY_MARGIN := 60.0
const MAX_ATTEMPTS := 3
const BACKOFF_SECONDS := 0.8
## Secure Token errors that mean the refresh token will never work again.
const DEAD_SESSION_ERRORS: Array[String] = [
	"TOKEN_EXPIRED",
	"INVALID_REFRESH_TOKEN",
	"USER_NOT_FOUND",
	"INVALID_GRANT_TYPE",
	"MISSING_REFRESH_TOKEN",
]
const LINK_ERRORS := {
	"EMAIL_EXISTS": "credential_in_use",
	"CREDENTIAL_ALREADY_IN_USE": "credential_in_use",
	"FEDERATED_USER_ID_ALREADY_LINKED": "credential_in_use",
	"INVALID_EMAIL": "invalid_email",
	"WEAK_PASSWORD": "weak_password",
	"CREDENTIAL_TOO_OLD_LOGIN_AGAIN": "reauth_required",
	"TOKEN_EXPIRED": "reauth_required",
	"INVALID_ID_TOKEN": "reauth_required",
	"TOO_MANY_ATTEMPTS_TRY_LATER": "too_many_attempts",
	"OPERATION_NOT_ALLOWED": "not_available",
	"USER_DISABLED": "disabled",
}
## Newer projects answer INVALID_LOGIN_CREDENTIALS for both an unknown email and a
## wrong password; the older codes are kept so the text never reveals which one.
const SIGN_IN_ERRORS := {
	"INVALID_LOGIN_CREDENTIALS": "invalid_credentials",
	"INVALID_PASSWORD": "invalid_credentials",
	"EMAIL_NOT_FOUND": "invalid_credentials",
	"MISSING_PASSWORD": "invalid_credentials",
	"INVALID_EMAIL": "invalid_email",
	"MISSING_EMAIL": "invalid_email",
	"USER_DISABLED": "disabled",
	"TOO_MANY_ATTEMPTS_TRY_LATER": "too_many_attempts",
	"OPERATION_NOT_ALLOWED": "not_available",
}
const VERIFY_ERRORS := {
	"INVALID_ID_TOKEN": "reauth_required",
	"TOKEN_EXPIRED": "reauth_required",
	"TOO_MANY_ATTEMPTS_TRY_LATER": "too_many_attempts",
	"OPERATION_NOT_ALLOWED": "not_available",
	"USER_DISABLED": "disabled",
}
const RESET_ERRORS := {
	"INVALID_EMAIL": "invalid_email",
	"MISSING_EMAIL": "invalid_email",
	"TOO_MANY_ATTEMPTS_TRY_LATER": "too_many_attempts",
	"OPERATION_NOT_ALLOWED": "not_available",
}

var api_key: String = ""
var transport: HttpTransport = null
## Unix time source; tests replace it.
var clock: Callable = Time.get_unix_time_from_system
## 0 makes retries immediate (tests).
var backoff_scale: float = 1.0
var uid: String = ""
## TYPE_GUEST, TYPE_EMAIL or "" (no account yet).
var account_type: String = ""
## uid of a guest account that had to be replaced (its refresh token was dead).
var previous_uid: String = ""
## The email of the account is confirmed (cached from the last lookup, so it is known offline).
var email_verified: bool = false
## Email of the signed-in account, only in memory (never written to disk); "" until known.
var email: String = ""

var _id_token: String = ""
var _refresh_token: String = ""
var _expires_at: float = 0.0
var _in_flight: bool = false


## Loads the stored session. `known_uid` is the uid the progress file remembers:
## if the session file is gone or unreadable, that identity is "lost" and is
## not silently replaced (see ensure_token).
func restore(known_uid: String = "") -> void:
	var session: Dictionary = SessionStore.load_session()
	uid = str(session.get("uid", known_uid))
	_refresh_token = str(session.get("refresh_token", ""))
	account_type = str(session.get("account_type", TYPE_GUEST if uid != "" else ""))
	previous_uid = str(session.get("previous_uid", ""))
	email_verified = bool(session.get("email_verified", false))
	email = ""
	_id_token = ""
	_expires_at = 0.0


## Moves a session saved by older versions (plain text in progress.cfg) into
## the encrypted store.
func adopt_legacy(legacy_uid: String, refresh_token: String) -> void:
	if legacy_uid == "" or refresh_token == "" or _refresh_token != "":
		return
	uid = legacy_uid
	_refresh_token = refresh_token
	account_type = TYPE_GUEST
	_persist()


func is_configured() -> bool:
	return api_key != "" and transport != null


func has_session() -> bool:
	return uid != "" and _refresh_token != ""


## A uid is known but its refresh token is not (session file lost/unreadable).
func is_session_lost() -> bool:
	return uid != "" and _refresh_token == ""


func id_token() -> String:
	return _id_token


func is_token_fresh() -> bool:
	return _id_token != "" and clock.call() < _expires_at - EXPIRY_MARGIN


## Forces a refresh on the next ensure_token (e.g. after a 401).
func invalidate_token() -> void:
	_id_token = ""
	_expires_at = 0.0


## Makes sure a fresh id token is available. {"ok", "error", "created"}.
## Errors: not_configured, offline, server, session_lost, disabled, no_session.
func ensure_token(allow_create: bool = true) -> Dictionary:
	if is_token_fresh():
		return {"ok": true, "error": "", "created": false}
	if _in_flight:
		return await token_request_finished
	_in_flight = true
	var result: Dictionary = await _acquire(allow_create)
	_in_flight = false
	token_request_finished.emit(result)
	return result


## Explicit user choice (account panel): drop a lost identity, start a new guest.
func start_new_guest() -> Dictionary:
	if _in_flight:
		return {"ok": false, "error": "busy", "created": false}
	forget()
	return await ensure_token(true)


## Forgets the session on this device (after account deletion).
func forget() -> void:
	uid = ""
	account_type = ""
	previous_uid = ""
	email_verified = false
	email = ""
	_refresh_token = ""
	invalidate_token()
	SessionStore.clear()
	changed.emit()


## Links an email/password credential to the current (guest) account; the uid
## and everything stored under it stay. {"ok", "error"}: credential_in_use
## (the email belongs to another account: sign in there instead, nothing is
## merged automatically), invalid_email, weak_password, reauth_required,
## not_available (provider disabled in the console), too_many_attempts,
## already_linked, offline, server. The password is never stored or logged.
func link_email(email_arg: String, password: String) -> Dictionary:
	if account_type == TYPE_EMAIL:
		return {"ok": false, "error": "already_linked"}
	var auth: Dictionary = await ensure_token(false)
	if not auth["ok"]:
		return {"ok": false, "error": auth["error"]}
	var body := {
		"idToken": _id_token, "email": email_arg, "password": password, "returnSecureToken": true
	}
	var reply: Dictionary = await _post_json(UPDATE_URL % api_key, body, false)
	if not reply["ok"]:
		return {"ok": false, "error": _link_error(reply)}
	_take_tokens(reply["json"], "idToken", "refreshToken", "localId", "expiresIn")
	account_type = TYPE_EMAIL
	email = email_arg
	email_verified = false
	_persist()
	changed.emit()
	return {"ok": true, "error": ""}


## Signs in with email and password (accounts:signInWithPassword), e.g. on a new
## device. Never retried (a wrong password must not be tried three times). A
## device already signed in to an email account may only sign in to that same
## account again (fresh login for sensitive actions): another one is refused
## with other_account before any token is taken. On success the session is the
## account's; a guest uid that is left behind is remembered in previous_uid.
## {"ok", "error", "switched" (the uid changed)}: invalid_credentials,
## invalid_email, too_many_attempts, disabled, not_available, other_account,
## not_configured, offline, server.
func sign_in_email(email_arg: String, password: String) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "not_configured", "switched": false}
	var body := {"email": email_arg, "password": password, "returnSecureToken": true}
	var reply: Dictionary = await _post_json(SIGN_IN_URL % api_key, body, false)
	if not reply["ok"]:
		return {"ok": false, "error": _error_key(reply, SIGN_IN_ERRORS), "switched": false}
	var json: Dictionary = reply["json"] if reply["json"] is Dictionary else {}
	var new_uid: String = str(json.get("localId", ""))
	if new_uid == "" or str(json.get("idToken", "")) == "":
		return {"ok": false, "error": "server", "switched": false}
	if account_type == TYPE_EMAIL and uid != "" and new_uid != uid:
		return {"ok": false, "error": "other_account", "switched": false}
	var switched: bool = new_uid != uid
	if switched and uid != "" and account_type == TYPE_GUEST:
		previous_uid = uid
	_take_tokens(json, "idToken", "refreshToken", "localId", "expiresIn")
	account_type = TYPE_EMAIL
	email = email_arg
	if switched:
		email_verified = false  # unknown until the next lookup
	_persist()
	changed.emit()
	return {"ok": true, "error": "", "switched": switched}


## Registers a new email account on a clean first launch (accounts:signUp with email
## and password): no guest existed, so there is no uid to keep. A device that already
## has a uid links the email instead (link_email). Never retried: a second request
## could create a second account. {"ok", "error"}: credential_in_use (email taken),
## invalid_email, weak_password, too_many_attempts, not_available, already_linked,
## not_configured, offline, server. The password is never stored or logged.
func sign_up_email(email_arg: String, password: String) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "not_configured"}
	if uid != "" or _refresh_token != "":
		return {"ok": false, "error": "already_linked"}
	var body := {"email": email_arg, "password": password, "returnSecureToken": true}
	var reply: Dictionary = await _post_json(SIGN_UP_URL % api_key, body, false)
	if not reply["ok"]:
		return {"ok": false, "error": _link_error(reply)}
	_take_tokens(reply["json"], "idToken", "refreshToken", "localId", "expiresIn")
	if uid == "" or _id_token == "":
		return {"ok": false, "error": "server"}
	account_type = TYPE_EMAIL
	email = email_arg
	email_verified = false
	_persist()
	changed.emit()
	return {"ok": true, "error": ""}


## Asks Firebase to mail the confirmation link (accounts:sendOobCode, VERIFY_EMAIL).
## Not retried; the caller rate-limits the button. {"ok", "error"}: reauth_required,
## too_many_attempts, not_available, offline, server, no_session.
func send_verification() -> Dictionary:
	var auth: Dictionary = await ensure_token(false)
	if not auth["ok"]:
		return {"ok": false, "error": auth["error"]}
	var body := {"requestType": "VERIFY_EMAIL", "idToken": _id_token}
	var reply: Dictionary = await _post_json(OOB_URL % api_key, body, false)
	if reply["ok"]:
		return {"ok": true, "error": ""}
	return {"ok": false, "error": _error_key(reply, VERIFY_ERRORS)}


## Reads the account data (accounts:lookup) and updates email_verified / email.
## {"ok", "error", "verified"}. Offline keeps the cached value.
func refresh_account_info() -> Dictionary:
	var auth: Dictionary = await ensure_token(false)
	if not auth["ok"]:
		return {"ok": false, "error": auth["error"], "verified": email_verified}
	var reply: Dictionary = await _post_json(LOOKUP_URL % api_key, {"idToken": _id_token}, false)
	if not reply["ok"]:
		return {"ok": false, "error": _error_key(reply, VERIFY_ERRORS), "verified": email_verified}
	var json: Variant = reply["json"]
	var users: Variant = (json as Dictionary).get("users", []) if json is Dictionary else []
	if not users is Array or (users as Array).is_empty() or not users[0] is Dictionary:
		return {"ok": false, "error": "server", "verified": email_verified}
	var info: Dictionary = users[0]
	var verified: bool = bool(info.get("emailVerified", false))
	email = str(info.get("email", email))
	if verified != email_verified:
		email_verified = verified
		_persist()
		changed.emit()
	return {"ok": true, "error": "", "verified": email_verified}


## Sends the password reset mail (accounts:sendOobCode, PASSWORD_RESET). Needs no
## session. An unknown address is reported as success on purpose: the answer must
## not tell whether an email is registered (projects with enumeration protection
## answer the same way). {"ok", "error"}: invalid_email, too_many_attempts,
## not_available, not_configured, offline, server.
func send_password_reset(email_arg: String) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "not_configured"}
	var body := {"requestType": "PASSWORD_RESET", "email": email_arg}
	var reply: Dictionary = await _post_json(OOB_URL % api_key, body, false)
	if reply["ok"]:
		return {"ok": true, "error": ""}
	if not HttpTransport.is_transient(reply) and error_message(reply["json"]) == "EMAIL_NOT_FOUND":
		return {"ok": true, "error": ""}
	return {"ok": false, "error": _error_key(reply, RESET_ERRORS)}


## Deletes the Firebase Auth user of this device (accounts:delete with the
## idToken; no Cloud Function needed) and forgets the session. The caller
## deletes the Firestore documents first. {"ok", "error"}: reauth_required (an
## old email sign-in must be repeated), offline, server. An already deleted
## user counts as success.
func delete_account() -> Dictionary:
	var auth: Dictionary = await ensure_token(false)
	if not auth["ok"]:
		return {"ok": false, "error": auth["error"]}
	var reply: Dictionary = await _post_json(DELETE_URL % api_key, {"idToken": _id_token}, true)
	if not reply["ok"]:
		var message: String = error_message(reply["json"])
		if message == "USER_NOT_FOUND":
			forget()
			return {"ok": true, "error": ""}
		if HttpTransport.is_transient(reply):
			return {"ok": false, "error": "offline" if reply["network"] else "server"}
		if message.begins_with("CREDENTIAL_TOO_OLD"):
			return {"ok": false, "error": "reauth_required"}
		return {"ok": false, "error": "server"}
	forget()
	return {"ok": true, "error": ""}


## Linking through an identity provider (accounts:signInWithIdp with the guest
## idToken) needs a provider id token from a native SDK; not available without
## native plugins. Never pretends to succeed.
func link_with_idp(_provider_id: String, _provider_token: String) -> Dictionary:
	return {"ok": false, "error": "not_available"}


## First word of a Firebase REST error message ("WEAK_PASSWORD : ..." -> WEAK_PASSWORD).
static func error_message(json: Variant) -> String:
	if not json is Dictionary:
		return ""
	var error: Variant = (json as Dictionary).get("error", {})
	if error is Dictionary:
		return str((error as Dictionary).get("message", "")).get_slice(" ", 0)
	return str(error).get_slice(" ", 0)  # Secure Token may answer {"error": "invalid_grant"}


func _acquire(allow_create: bool) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": "not_configured", "created": false}
	if _refresh_token != "":
		var refreshed: Dictionary = await _refresh()
		if refreshed["ok"] or refreshed["error"] != "dead":
			return refreshed
		# The server rejected the refresh token for good.
		if account_type != TYPE_GUEST or not allow_create:
			_refresh_token = ""
			_persist()
			return {"ok": false, "error": "session_lost", "created": false}
		previous_uid = uid
		uid = ""
		_refresh_token = ""
	elif uid != "":
		return {"ok": false, "error": "session_lost", "created": false}
	if not allow_create:
		return {"ok": false, "error": "no_session", "created": false}
	return await _sign_up()


func _refresh() -> Dictionary:
	var form := "grant_type=refresh_token&refresh_token=" + _refresh_token.uri_encode()
	var reply: Dictionary = await _send_with_retry(
		HTTPClient.METHOD_POST,
		REFRESH_URL % api_key,
		PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]),
		form,
		true
	)
	if reply["ok"]:
		var before: String = uid
		_take_tokens(reply["json"], "id_token", "refresh_token", "user_id", "expires_in")
		_persist()
		if uid != before:
			changed.emit()
		return {
			"ok": _id_token != "", "error": "" if _id_token != "" else "server", "created": false
		}
	if HttpTransport.is_transient(reply):
		return {"ok": false, "error": "offline" if reply["network"] else "server", "created": false}
	var message: String = error_message(reply["json"])
	if message == "USER_DISABLED":
		return {"ok": false, "error": "disabled", "created": false}
	if DEAD_SESSION_ERRORS.has(message) or message == "invalid_grant":
		return {"ok": false, "error": "dead", "created": false}
	return {"ok": false, "error": "server", "created": false}


func _sign_up() -> Dictionary:
	var reply: Dictionary = await _post_json(
		SIGN_UP_URL % api_key, {"returnSecureToken": true}, false
	)
	if not reply["ok"]:
		var network: bool = reply["network"]
		return {"ok": false, "error": "offline" if network else "server", "created": false}
	_take_tokens(reply["json"], "idToken", "refreshToken", "localId", "expiresIn")
	account_type = TYPE_GUEST
	_persist()
	changed.emit()
	return {"ok": uid != "", "error": "" if uid != "" else "server", "created": true}


func _take_tokens(
	json: Variant, id_key: String, refresh_key: String, uid_key: String, ttl_key: String
) -> void:
	var data: Dictionary = json if json is Dictionary else {}
	_id_token = str(data.get(id_key, ""))
	_refresh_token = str(data.get(refresh_key, _refresh_token))
	uid = str(data.get(uid_key, uid))
	_expires_at = float(clock.call()) + float(str(data.get(ttl_key, "3600")))


func _persist() -> void:
	if uid == "" and _refresh_token == "":
		SessionStore.clear()
		return
	(
		SessionStore
		. save_session(
			{
				"uid": uid,
				"refresh_token": _refresh_token,
				"account_type": account_type,
				"previous_uid": previous_uid,
				"email_verified": email_verified,
			}
		)
	)


func _link_error(reply: Dictionary) -> String:
	return _error_key(reply, LINK_ERRORS)


## Reply of a failed request -> short error key ("offline", "server" or from `table`).
static func _error_key(reply: Dictionary, table: Dictionary) -> String:
	if int(reply.get("code", 0)) == 429:
		return "too_many_attempts"
	if HttpTransport.is_transient(reply):
		return "offline" if reply["network"] else "server"
	return str(table.get(error_message(reply["json"]), "server"))


func _post_json(url: String, body: Dictionary, retry: bool) -> Dictionary:
	return await _send_with_retry(
		HTTPClient.METHOD_POST,
		url,
		PackedStringArray(["Content-Type: application/json"]),
		JSON.stringify(body),
		retry
	)


func _send_with_retry(
	method: int, url: String, headers: PackedStringArray, body: String, retry: bool
) -> Dictionary:
	var reply: Dictionary = {}
	var attempts: int = MAX_ATTEMPTS if retry else 1
	for attempt in attempts:
		if attempt > 0 and backoff_scale > 0.0:
			var delay: float = BACKOFF_SECONDS * pow(2.0, attempt - 1) * randf_range(0.8, 1.2)
			await transport.get_tree().create_timer(delay * backoff_scale).timeout
		reply = await transport.send(method, url, headers, body)
		if not HttpTransport.is_transient(reply):
			break
	return reply
