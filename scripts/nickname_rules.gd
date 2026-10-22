class_name NicknameRules
extends RefCounted
## Nickname policy. firestore.rules apply the same policy (the server side;
## both are checked against
## tests/nickname_cases.json and firebase/rules-tests); change them together.
##
## - Spaces at the ends are dropped and runs of whitespace become one space.
## - 3..16 characters after that.
## - Letters of the Latin alphabet (with accents: U+00C0..U+017E) and of the
##   Cyrillic one (U+0401..U+045F without U+040D), digits 0-9; a single space or
##   underscore only between two letters/digits. Nothing else: no control or
##   invisible characters, emoji, symbols or combining marks.
## - One alphabet per name: Latin and Cyrillic letters may not be mixed ("Аdmin" with
##   a Cyrillic "А" would imitate a reserved name). Digits, space and _ are neutral.
## - Key for uniqueness (normalize): lower case, "ё" -> "е", space -> "_".
##   "Сэр Ёжик" and "сэр_ежик" are the same name.
## - A few reserved names (RESERVED, compared normalized).

const MIN_LENGTH := 3
const MAX_LENGTH := 16
## Normalized names nobody may take ("рыцарь" is the anonymous leaderboard name).
const RESERVED: Array[String] = [
	"admin",
	"administrator",
	"moderator",
	"support",
	"system",
	"tinyguard",
	"bimbleguard",
	"рыцарь",  # i18n:keep
	"админ",  # i18n:keep
	"администратор",  # i18n:keep
	"модератор",  # i18n:keep
	"поддержка",  # i18n:keep
]
const MESSAGES := {
	"too_short": "NICK_TOO_SHORT",
	"too_long": "NICK_TOO_LONG",
	"bad_char": "NICK_BAD_CHAR",
	"mixed_script": "NICK_MIXED_SCRIPT",
	"bad_separator": "NICK_BAD_SEPARATOR",
	"reserved": "NICK_RESERVED",
	"taken": "NICK_TAKEN",
	"rate_limited": "NICK_RATE_LIMITED",
}


## Trimmed, with every run of whitespace replaced by a single space.
static func clean(raw: String) -> String:
	var out := ""
	var gap := false
	for ch in raw.strip_edges():
		var code: int = ch.unicode_at(0)
		if code == 32 or code == 9 or code == 10 or code == 13 or code == 0xA0:
			gap = true
			continue
		if gap and out != "":
			out += " "
		gap = false
		out += ch
	return out


## {"ok", "nickname" (cleaned), "normalized", "error" (code or ""), "message"}.
static func validate(raw: String) -> Dictionary:
	var name: String = clean(raw)
	var error: String = _error_code(name)
	var normalized: String = normalize(name) if error == "" else ""
	if error == "" and RESERVED.has(normalized):
		error = "reserved"
	return {
		"ok": error == "",
		"nickname": name,
		"normalized": normalized if error == "" else "",
		"error": error,
		"message": message(error),
	}


static func message(error: String) -> String:
	if not MESSAGES.has(error):
		return ""
	var text: String = TranslationServer.translate(str(MESSAGES[error]))
	match error:
		"too_short":
			return text % MIN_LENGTH
		"too_long":
			return text % MAX_LENGTH
	return text


## Uniqueness key of a valid (cleaned) nickname.
static func normalize(name: String) -> String:
	return name.to_lower().replace("ё", "е").replace(" ", "_")  # i18n:keep


## Only ranges where Godot's String.to_lower() and JavaScript's toLowerCase()
## agree (checked code point by code point); wider ranges differ in Godot 4.3.
static func is_letter_or_digit(code: int) -> bool:
	return (
		(code >= 0x30 and code <= 0x39)
		or (code >= 0x41 and code <= 0x5A)
		or (code >= 0x61 and code <= 0x7A)
		or (code >= 0xC0 and code <= 0x17E and code != 0xD7 and code != 0xF7 and code != 0x130)
		or (code >= 0x401 and code <= 0x45F and code != 0x40D)
	)


static func _error_code(name: String) -> String:
	if name.length() < MIN_LENGTH:
		return "too_short"
	if name.length() > MAX_LENGTH:
		return "too_long"
	var bad_separator := false
	var has_latin := false
	var has_cyrillic := false
	var previous_separator := true  # nothing before the first character
	for ch in name:
		var code: int = ch.unicode_at(0)
		var separator: bool = code == 32 or code == 0x5F
		if not separator and not is_letter_or_digit(code):
			return "bad_char"
		if code >= 0x401:
			has_cyrillic = true
		elif code >= 0x41 and not separator:
			has_latin = true
		if separator and previous_separator:
			bad_separator = true
		previous_separator = separator
	if bad_separator or previous_separator:
		return "bad_separator"
	if has_latin and has_cyrillic:
		return "mixed_script"
	return ""


## Generates a valid fantasy name for quick guest onboarding.
static func generate_random_name() -> String:
	var is_ru: bool = TranslationServer.get_locale().begins_with("ru")
	var ru_names: Array[String] = [
		"ХрабрыйСтраж", "Витязь", "БыстрыйКлинок", "Сокол", "ЛеснойСтраж", "Воин", "Барон", "ТихийДозор"  # i18n:keep
	]
	var en_names: Array[String] = [
		"BraveKnight", "IronGuard", "SwiftBlade", "ShadowFox", "DawnShield", "StarOak", "StormRider"
	]
	var base: String = ru_names.pick_random() if is_ru else en_names.pick_random()
	var num: int = randi_range(10, 99)
	return "%s_%d" % [base, num]

