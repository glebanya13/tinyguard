class_name NicknameRules
extends RefCounted
## Nickname policy. The server applies the same rules in
## firebase/functions/src/nickname.ts (both are checked against
## tests/nickname_cases.json); change them together.
##
## - Spaces at the ends are dropped and runs of whitespace become one space.
## - 3..16 characters after that.
## - Letters of the Latin alphabet (with accents: U+00C0..U+017F) and of the
##   Cyrillic one (U+0401..U+045F without U+040D), digits 0-9; a single space or
##   underscore only between two letters/digits. Nothing else: no control or
##   invisible characters, emoji, symbols or combining marks.
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
	"рыцарь",
	"админ",
	"администратор",
	"модератор",
	"поддержка",
]
const MESSAGES := {
	"too_short": "Минимум %d символа" % MIN_LENGTH,
	"too_long": "Не больше %d символов" % MAX_LENGTH,
	"bad_char": "Только буквы, цифры, пробел и _",
	"bad_separator": "Пробел и _ — только между буквами",
	"reserved": "Это имя занято королевством",
	"taken": "Это имя уже занято — попробуй другое",
	"rate_limited": "Имя можно менять не чаще раза в сутки",
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
	return str(MESSAGES.get(error, ""))


## Uniqueness key of a valid (cleaned) nickname.
static func normalize(name: String) -> String:
	return name.to_lower().replace("ё", "е").replace(" ", "_")


## Only ranges where Godot's String.to_lower() and JavaScript's toLowerCase()
## agree (checked code point by code point); wider ranges differ in Godot 4.3.
static func is_letter_or_digit(code: int) -> bool:
	return (
		(code >= 0x30 and code <= 0x39)
		or (code >= 0x41 and code <= 0x5A)
		or (code >= 0x61 and code <= 0x7A)
		or (code >= 0xC0 and code <= 0x17F and code != 0xD7 and code != 0xF7 and code != 0x130)
		or (code >= 0x401 and code <= 0x45F and code != 0x40D)
	)


static func _error_code(name: String) -> String:
	if name.length() < MIN_LENGTH:
		return "too_short"
	if name.length() > MAX_LENGTH:
		return "too_long"
	var bad_separator := false
	var previous_separator := true  # nothing before the first character
	for ch in name:
		var code: int = ch.unicode_at(0)
		var separator: bool = code == 32 or code == 0x5F
		if not separator and not is_letter_or_digit(code):
			return "bad_char"
		if separator and previous_separator:
			bad_separator = true
		previous_separator = separator
	if bad_separator or previous_separator:
		return "bad_separator"
	return ""
