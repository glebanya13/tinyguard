class_name EmailRules
extends RefCounted
## Client-side checks of the email and password typed in the account dialog, and
## the player-facing text for every error the email flows can answer with.
## The server decides in the end (Firebase has its own rules); these checks only
## save a round trip and give a clear hint. Nothing here stores or logs the input.

## Firebase's lower bound; the console can raise it, then the server answers
## WEAK_PASSWORD and the same message is shown.
const PASSWORD_MIN := 6
const PASSWORD_MAX := 128
const EMAIL_MAX := 254

const MESSAGES := {
	"empty_email": "ERR_EMAIL_EMPTY",
	"invalid_email": "ERR_EMAIL_INVALID",
	"empty_password": "ERR_PASSWORD_EMPTY",
	"weak_password": "ERR_PASSWORD_WEAK",
	"password_too_long": "ERR_PASSWORD_LONG",
	"invalid_credentials": "ERR_INVALID_CREDENTIALS",
	"too_many_attempts": "ERR_TOO_MANY_ATTEMPTS",
	"reauth_required": "ERR_REAUTH_REQUIRED",
	"already_linked": "ERR_ALREADY_LINKED",
	"disabled": "ERR_DISABLED",
	"not_available": "ERR_NOT_AVAILABLE",
	"link_disabled": "ERR_LINK_DISABLED",
	"signup_disabled": "ERR_SIGNUP_DISABLED",
	"signin_disabled": "ERR_SIGNIN_DISABLED",
	"reset_disabled": "ERR_RESET_DISABLED",
	"verify_disabled": "ERR_VERIFY_DISABLED",
	"signup_closed": "ERR_SIGNUP_CLOSED",
	"key_restricted": "ERR_KEY_RESTRICTED",
	"config_missing": "ERR_CONFIG_MISSING",
	"offline": "ERR_OFFLINE",
	"server": "ERR_SERVER",
	"other_account": "ERR_OTHER_ACCOUNT",
	"session_lost": "ERR_SESSION_LOST",
	"no_session": "ERR_SESSION_LOST",
	"not_configured": "ERR_NOT_CONFIGURED",
	"busy": "ERR_BUSY",
	"guest_cannot_sign_out": "ERR_GUEST_CANNOT_SIGN_OUT",
	"unsynced": "ERR_UNSYNCED",
	"credential_in_use": "ERR_CREDENTIAL_IN_USE",
}


## Trims and checks an email. {"ok", "error", "email"}; error is a MESSAGES key.
static func check_email(raw: String) -> Dictionary:
	var email: String = raw.strip_edges()
	if email == "":
		return {"ok": false, "error": "empty_email", "email": ""}
	if email.length() > EMAIL_MAX or not _email_regex().search(email):
		return {"ok": false, "error": "invalid_email", "email": email}
	return {"ok": true, "error": "", "email": email}


## Checks a new password (linking). The text is used exactly as typed: spaces count.
static func check_new_password(password: String) -> Dictionary:
	if password == "":
		return {"ok": false, "error": "empty_password"}
	if password.length() < PASSWORD_MIN:
		return {"ok": false, "error": "weak_password"}
	if password.length() > PASSWORD_MAX:
		return {"ok": false, "error": "password_too_long"}
	return {"ok": true, "error": ""}


## Signing in only needs a non-empty password (the account may be older than any rule).
static func check_password(password: String) -> Dictionary:
	if password == "":
		return {"ok": false, "error": "empty_password"}
	if password.length() > PASSWORD_MAX:
		return {"ok": false, "error": "invalid_credentials"}
	return {"ok": true, "error": ""}


## Player-facing text of an error key; a generic line for unknown keys.
static func message(error: String) -> String:
	return TranslationServer.translate(str(MESSAGES.get(error, "ERR_GENERIC")))


static func _email_regex() -> RegEx:
	var regex := RegEx.new()
	# One "@", no spaces, a dot in the domain, no empty labels around it.
	regex.compile("^[^@\\s]+@[^@\\s.]+(\\.[^@\\s.]+)+$")
	return regex
