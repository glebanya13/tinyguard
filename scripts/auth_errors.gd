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


## First word of a Firebase REST error message ("WEAK_PASSWORD : ..." -> WEAK_PASSWORD).
static func message(json: Variant) -> String:
	if not json is Dictionary:
		return ""
	var error: Variant = (json as Dictionary).get("error", {})
	if error is Dictionary:
		return str((error as Dictionary).get("message", "")).get_slice(" ", 0)
	return str(error).get_slice(" ", 0)  # Secure Token may answer {"error": "invalid_grant"}


## Reply of a failed request -> short error key ("offline", "server" or from `table`).
static func key(reply: Dictionary, table: Dictionary) -> String:
	if int(reply.get("code", 0)) == 429:
		return "too_many_attempts"
	if HttpTransport.is_transient(reply):
		return "offline" if reply["network"] else "server"
	return str(table.get(message(reply["json"]), "server"))
