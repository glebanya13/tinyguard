extends SceneTree
## Translations: every key has a non-empty ru and en text, English has no
## Cyrillic, format placeholders match between languages, every key used in code
## exists, and the locale choice (auto / ru / en) and the https-only link rule work.
## godot --headless --path . --script res://tests/test_i18n.gd

const CSV_PATH := "res://translations/strings.csv"
const SOURCE_DIRS: Array[String] = ["res://scripts", "res://scenes", "res://ui", "res://resources"]

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var rows: Dictionary = _read_csv()
	check(rows.size() > 100, "csv has %d keys" % rows.size())
	_check_rows(rows)
	_check_used_keys(rows)
	_check_runtime(rows)
	_check_locale_choice()
	_check_urls()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)


## {key: {"ru": text, "en": text}} from the translations CSV (header: keys,ru,en).
func _read_csv() -> Dictionary:
	var out: Dictionary = {}
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	var header: PackedStringArray = file.get_csv_line()
	check(header.size() == 3 and header[0] == "keys", "csv header is keys,ru,en")
	while not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()
		if line.size() < 3:
			continue
		out[line[0]] = {header[1]: line[1], header[2]: line[2]}
	return out


func _check_rows(rows: Dictionary) -> void:
	var cyrillic := RegEx.create_from_string("[А-Яа-яЁё]")
	var placeholder := RegEx.create_from_string("%[-+ 0#]*\\d*(?:\\.\\d+)?[sdfxXc%]")
	var bad_empty: Array[String] = []
	var bad_cyr: Array[String] = []
	var bad_fmt: Array[String] = []
	var bad_ru: Array[String] = []
	for key: String in rows:
		var ru: String = rows[key]["ru"]
		var en: String = rows[key]["en"]
		if ru.strip_edges() == "" or en.strip_edges() == "":
			bad_empty.append(key)
		# Languages named in their own script are allowed ("Русский" in the picker).
		if key != "SET_LANG_RU" and cyrillic.search(en) != null:
			bad_cyr.append(key)
		if _placeholders(placeholder, ru) != _placeholders(placeholder, en):
			bad_fmt.append(key)
		if cyrillic.search(ru) == null and key not in _latin_ru_ok():
			bad_ru.append(key)
	check(bad_empty.is_empty(), "no empty translations %s" % [bad_empty])
	check(bad_cyr.is_empty(), "no Cyrillic in English %s" % [bad_cyr])
	check(bad_fmt.is_empty(), "format placeholders match %s" % [bad_fmt])
	check(bad_ru.is_empty(), "Russian texts are Russian %s" % [bad_ru])


## Russian rows that legitimately contain no Cyrillic (a number, a language name).
func _latin_ru_ok() -> Array[String]:
	return ["CARD_TOWER_TIP", "SET_LANG_EN"]


## Placeholders in order, e.g. ["%s", "%d"] ("%%" counts as a literal percent).
func _placeholders(regex: RegEx, text: String) -> Array[String]:
	var out: Array[String] = []
	for m in regex.search_all(text):
		var token: String = m.get_string()
		if token != "%%":
			out.append(token)
	return out


## tr("KEY"), translate("KEY") and key-looking constants in the sources exist in the CSV.
func _check_used_keys(rows: Dictionary) -> void:
	var call_regex := RegEx.create_from_string('(?:\\btr|translate)\\(\\s*"([A-Z][A-Z0-9_]+)"')
	var key_regex := RegEx.create_from_string('"([A-Z]{2,}[A-Z0-9]*(?:_[A-Z0-9]+)+)"')
	var used: Dictionary = {}
	var maybe: Dictionary = {}
	for dir: String in SOURCE_DIRS:
		for path in _files(dir):
			var text: String = FileAccess.get_file_as_string(path)
			for m in call_regex.search_all(text):
				used[m.get_string(1)] = path
			for m in key_regex.search_all(text):
				maybe[m.get_string(1)] = path
	var missing: Array[String] = []
	for key: String in used:
		if not rows.has(key):
			missing.append("%s (%s)" % [key, used[key]])
	check(missing.is_empty(), "every tr() key exists %s" % [missing])
	# Constants that hold keys (MESSAGES tables, tower/perk/level data, ...).
	var missing_const: Array[String] = []
	for key: String in maybe:
		var prefix: String = key.split("_")[0]
		if key in ["EMAIL_EXISTS", "EMAIL_NOT_FOUND"]:  # Firebase error codes, not texts
			continue
		if (
			prefix
			in ["ERR", "NICK", "SYNC", "EMAIL", "TOWER", "ENEMY", "PERK", "LEVEL", "TIP", "TUT"]
		):
			if not rows.has(key):
				missing_const.append("%s (%s)" % [key, maybe[key]])
	check(missing_const.is_empty(), "every key-like constant exists %s" % [missing_const])
	var unused: Array[String] = []
	for key: String in rows:
		if not used.has(key) and not maybe.has(key) and not _is_dynamic(key):
			unused.append(key)
	print("  info unused keys (scene texts, dynamic): %d" % unused.size())


## Keys built at run time or used by scene texts.
func _is_dynamic(key: String) -> bool:
	return key.ends_with("_PLACEHOLDER")


func _files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for name in d.get_files():
		if name.get_extension() in ["gd", "tscn", "tres", "json"]:
			out.append(dir.path_join(name))
	for sub in d.get_directories():
		out.append_array(_files(dir.path_join(sub)))
	return out


func _check_runtime(rows: Dictionary) -> void:
	TranslationServer.set_locale("ru")
	check(TranslationServer.translate("HUD_PAUSE") == "Пауза", "ru: HUD_PAUSE")
	TranslationServer.set_locale("en")
	check(TranslationServer.translate("HUD_PAUSE") == "Paused", "en: HUD_PAUSE")
	var all_ok := true
	for key: String in rows:
		if TranslationServer.translate(key) == key:
			all_ok = false
			print("  missing at run time: ", key)
	check(all_ok, "the registered translation resolves every key in en")
	TranslationServer.set_locale("ru")
	all_ok = true
	for key: String in rows:
		if TranslationServer.translate(key) == key:
			all_ok = false
	check(all_ok, "the registered translation resolves every key in ru")
	# Game data points at keys.
	for level: Dictionary in LevelCatalog.levels():
		check(rows.has(str(level["name"])) and rows.has(str(level["subtitle"])), "level text keys")
	TranslationServer.set_locale("en")
	check(
		EmailRules.message("offline") == "No connection. Try again when you are online",
		"en: email error"
	)
	check(NicknameRules.message("too_short") == "At least 3 characters", "en: nickname too_short")
	TranslationServer.set_locale("ru")
	check(NicknameRules.message("too_short") == "Минимум 3 символа", "ru: nickname too_short")


func _check_locale_choice() -> void:
	check(GameSettings.resolve_locale("auto", "ru") == "ru", "auto + ru system = ru")
	check(GameSettings.resolve_locale("auto", "de") == "en", "auto + other system = en")
	check(GameSettings.resolve_locale("auto", "en") == "en", "auto + en system = en")
	check(GameSettings.resolve_locale("en", "ru") == "en", "forced en")
	check(GameSettings.resolve_locale("ru", "de") == "ru", "forced ru")
	var old_path: String = GameSettings.config_path
	GameSettings.config_path = "user://test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.config_path))
	check(GameSettings.language() == "auto", "default language is auto")
	GameSettings.set_language("en")
	check(GameSettings.language() == "en", "language saved")
	check(TranslationServer.get_locale().begins_with("en"), "language applied at once")
	GameSettings.set_language("klingon")
	check(GameSettings.language() == "en", "unknown language ignored")
	GameSettings.set_language("ru")
	check(TranslationServer.get_locale().begins_with("ru"), "ru applied")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.config_path))
	GameSettings.config_path = old_path


func _check_urls() -> void:
	check(GameSettings.is_safe_url("https://example.com/privacy"), "https link is safe")
	check(not GameSettings.is_safe_url("http://example.com"), "http is refused")
	check(not GameSettings.is_safe_url("file:///etc/passwd"), "file is refused")
	check(not GameSettings.is_safe_url("intent://x#Intent;end"), "intent is refused")
	check(not GameSettings.is_safe_url("javascript:alert(1)"), "javascript is refused")
	check(not GameSettings.is_safe_url("https://"), "empty host is refused")
	check(not GameSettings.is_safe_url("https://a.com/ b"), "space is refused")
	check(not GameSettings.is_safe_url(""), "empty is refused")
	check(not GameSettings.open_url("http://example.com"), "open_url refuses http")
