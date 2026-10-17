class_name AuthErrors
extends RefCounted
## Firebase Auth error vocabulary: the REST error codes of each request kind mapped to
## the short keys the game shows (EmailRules.message). Pure data and string logic,
## split from AuthService (which does the requests and the token handling).

## Secure Token errors that mean the refresh token will never work again.
const DEAD_SESSION_ERRORS: Array[String] = [
	"TOKEN_EXPIRED",
	"INVALID_REFRESH_TOKEN",
	"USER_NOT_FOUND",
	"INVALID_GRANT_TYPE",
	"MISSING_REFRESH_TOKEN",
]
## Answers that mean the same whatever the request was: the project or the API key is set up
## so that the game cannot do this (the player cannot fix it, support can).
const COMMON_ERRORS := {
	"ADMIN_ONLY_OPERATION": "signup_closed",
	"PERMISSION_DENIED": "key_restricted",
	"API_KEY_SERVICE_BLOCKED": "key_restricted",
	"API_KEY_HTTP_REFERRER_BLOCKED": "key_restricted",
	"API_KEY_ANDROID_APP_BLOCKED": "key_restricted",
	"API_KEY_IOS_APP_BLOCKED": "key_restricted",
	"API_KEY_IP_ADDRESS_BLOCKED": "key_restricted",
	"API_KEY_INVALID": "key_restricted",
	"INVALID_API_KEY": "key_restricted",
	"CONFIGURATION_NOT_FOUND": "config_missing",
}
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
	"OPERATION_NOT_ALLOWED": "link_disabled",
	"USER_DISABLED": "disabled",
}
## Sign-up of a new account: the same answers, its own text for a disabled provider.
const SIGN_UP_ERRORS := {
	"EMAIL_EXISTS": "credential_in_use",
	"CREDENTIAL_ALREADY_IN_USE": "credential_in_use",
	"INVALID_EMAIL": "invalid_email",
	"WEAK_PASSWORD": "weak_password",
	"TOO_MANY_ATTEMPTS_TRY_LATER": "too_many_attempts",
	"OPERATION_NOT_ALLOWED": "signup_disabled",
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
	"OPERATION_NOT_ALLOWED": "signin_disabled",
}
const VERIFY_ERRORS := {
	"INVALID_ID_TOKEN": "reauth_required",
	"TOKEN_EXPIRED": "reauth_required",
	"TOO_MANY_ATTEMPTS_TRY_LATER": "too_many_attempts",
	"OPERATION_NOT_ALLOWED": "verify_disabled",
	"USER_DISABLED": "disabled",
}
const RESET_ERRORS := {
	"INVALID_EMAIL": "invalid_email",
	"MISSING_EMAIL": "invalid_email",
	"TOO_MANY_ATTEMPTS_TRY_LATER": "too_many_attempts",
	"OPERATION_NOT_ALLOWED": "reset_disabled",
}


## First word of a Firebase REST error message ("WEAK_PASSWORD : ..." -> WEAK_PASSWORD).
static func message(json: Variant) -> String:
	if not json is Dictionary:
		return ""
	var error: Variant = (json as Dictionary).get("error", {})
	if error is Dictionary:
		return str((error as Dictionary).get("message", "")).get_slice(" ", 0)
	return str(error).get_slice(" ", 0)  # Secure Token may answer {"error": "invalid_grant"}


## Every code the server put in the answer: the first word of error.message, error.status
## and the "reason" of error.errors[] / error.details[] (e.g. API_KEY_SERVICE_BLOCKED). Only
## words made of capitals, digits and "_" are taken, so nothing typed by the player (an
## address in a message) can pass through.
static func codes(json: Variant) -> Array[String]:
	var out: Array[String] = []
	if not json is Dictionary:
		return out
	var error: Variant = (json as Dictionary).get("error", {})
	if not error is Dictionary:
		var plain: String = message(json)
		if _is_code(plain):
			out.append(plain)
		return out
	var data: Dictionary = error
	var found: Array = [message(json), str(data.get("status", ""))]
	for list_key: String in ["errors", "details"]:
		var list: Variant = data.get(list_key, [])
		if list is Array:
			for item: Variant in list:
				if item is Dictionary:
					found.append(str((item as Dictionary).get("reason", "")))
					if list_key == "errors":
						found.append(str((item as Dictionary).get("message", "")).get_slice(" ", 0))
	for word: Variant in found:
		if _is_code(str(word)) and not out.has(str(word)):
			out.append(str(word))
	return out


## What to show next to the message and to put into a report: "HTTP 400 OPERATION_NOT_ALLOWED",
## "HTTP 403 PERMISSION_DENIED API_KEY_SERVICE_BLOCKED", "HTTP 400 (no body)", "no reply
## (offline or timeout)". No address, password or token can be in it (see codes()).
static func detail(reply: Dictionary) -> String:
	if bool(reply.get("network", false)):
		return "no reply (offline or timeout)"
	var code: int = int(reply.get("code", 0))
	var words: Array[String] = codes(reply.get("json"))
	var text: String = "HTTP %d" % code if code > 0 else "no reply"
	if words.is_empty():
		return text + " (no body)" if reply.get("json") == null else text + " (unknown body)"
	return text + " " + " ".join(words)


## Reply of a failed request -> short error key ("offline", "server" or from `table`;
## codes missing there are looked up in COMMON_ERRORS).
static func key(reply: Dictionary, table: Dictionary) -> String:
	if int(reply.get("code", 0)) == 429:
		return "too_many_attempts"
	if HttpTransport.is_transient(reply):
		return "offline" if reply["network"] else "server"
	var words: Array[String] = codes(reply.get("json"))
	for word: String in words:
		if table.has(word):
			return str(table[word])
	for word: String in words:
		if COMMON_ERRORS.has(word):
			return str(COMMON_ERRORS[word])
	return "server"


## {"ok": false, "error", "detail"} for a failed reply; remembers the detail for the
## diagnostics (CrashTrace) under `op` ("link", "signup", "signin", "reset", "verify", ...).
static func failure(reply: Dictionary, table: Dictionary, op: String) -> Dictionary:
	var text: String = detail(reply)
	CrashTrace.note_auth_error(op, text)
	return {"ok": false, "error": key(reply, table), "detail": text}


static func _is_code(word: String) -> bool:
	if word.length() < 3 or word.length() > 64:
		return false
	for i in word.length():
		var c: int = word.unicode_at(i)
		var upper: bool = c >= 65 and c <= 90
		var digit: bool = c >= 48 and c <= 57
		if not (upper or digit or c == 95):
			return false
	return true
