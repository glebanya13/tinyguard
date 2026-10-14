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
	"empty_email": "Введи почту",
	"invalid_email": "Проверь почту: нужен адрес вида name@example.com",
	"empty_password": "Введи пароль",
	"weak_password": "Пароль слишком простой: минимум 6 символов, лучше с цифрами",
	"password_too_long": "Пароль слишком длинный: не больше 128 символов",
	"credential_in_use":
	"Эта почта уже занята. Если аккаунт твой — нажми «Войти по почте» вместо привязки",
	"invalid_credentials": "Неверная почта или пароль",
	"too_many_attempts": "Слишком много попыток. Подожди немного и попробуй снова",
	"reauth_required": "Нужен свежий вход: войди по почте и повтори действие",
	"already_linked": "К этому аккаунту почта уже привязана",
	"disabled": "Этот аккаунт заблокирован",
	"not_available": "Вход по почте сейчас недоступен",
	"offline": "Нет связи. Попробуй, когда появится интернет",
	"server": "Сервер не отвечает. Попробуй позже",
	"other_account": "Ты уже вошёл в другой аккаунт. Сначала выйди из него в Профиле",
	"session_lost": "Вход на устройстве потерян. Войди по почте, если она уже привязана",
	"no_session": "Вход на устройстве потерян. Войди по почте, если она уже привязана",
	"not_configured": "Онлайн недоступен в этой сборке",
	"busy": "Подожди, предыдущий запрос ещё выполняется",
	"guest_cannot_sign_out": "Гость не может выйти: прогресс пропадёт. Сначала привяжи почту",
	"unsynced": "Нужен интернет, чтобы сохранить прогресс в облаке перед выходом",
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
	return str(MESSAGES.get(error, "Не получилось. Попробуй ещё раз"))


static func _email_regex() -> RegEx:
	var regex := RegEx.new()
	# One "@", no spaces, a dot in the domain, no empty labels around it.
	regex.compile("^[^@\\s]+@[^@\\s.]+(\\.[^@\\s.]+)+$")
	return regex
