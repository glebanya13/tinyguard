extends SceneTree
## Translations: every key has a non-empty ru and en text, English has no
## Cyrillic, format placeholders match between languages, every key used in code
## exists, and the locale choice (auto / ru / en) and the https-only link rule work.
## godot --headless --path . --script res://tests/test_i18n.gd

const CSV_PATH := "res://translations/strings.csv"
const SOURCE_DIRS: Array[String] = ["res://scripts", "res://scenes", "res://ui", "res://resources"]
const EXPECTED_LANGUAGES: Array[String] = [
	"ru", "en", "zh", "it", "es", "ko", "de", "pl", "pt", "tr", "fr", "ja"
]

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


## {key: {lang: text}} from the translations CSV (header: keys,ru,en,...).
func _read_csv() -> Dictionary:
	var out: Dictionary = {}
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	var header: PackedStringArray = file.get_csv_line()
	check(
		header.size() == 13 and header[0] == "keys", "csv header has 13 columns starting with keys"
	)
	for i in range(1, header.size()):
		check(
			header[i] == EXPECTED_LANGUAGES[i - 1],
			"header column %d is %s" % [i, EXPECTED_LANGUAGES[i - 1]]
		)
	while not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()
		if line.size() < 13:
			continue
		var row_dict: Dictionary = {}
		for i in range(1, header.size()):
			row_dict[header[i]] = line[i]
		out[line[0]] = row_dict
	return out


func _check_rows(rows: Dictionary) -> void:
	var cyrillic := RegEx.create_from_string("[А-Яа-яЁё]")
	var placeholder := RegEx.create_from_string("%[-+ 0#]*\\d*(?:\\.\\d+)?[sdfxXc%]")
	var bad_empty: Array[String] = []
	var bad_cyr: Array[String] = []
	var bad_fmt: Array[String] = []
	var bad_ru: Array[String] = []
	for key: String in rows:
		var row: Dictionary = rows[key]
		var en_phs: Array[String] = _placeholders(placeholder, row["en"])
		for lang: String in EXPECTED_LANGUAGES:
			var text: String = row[lang]
			if text.strip_edges() == "":
				bad_empty.append("%s (%s)" % [key, lang])
			if _placeholders(placeholder, text) != en_phs:
				bad_fmt.append("%s (%s)" % [key, lang])
		# Languages named in their own script are allowed ("Русский" in the picker).
		if key != "SET_LANG_RU" and cyrillic.search(row["en"]) != null:
			bad_cyr.append(key)
		if cyrillic.search(row["ru"]) == null and key not in _latin_ru_ok():
			bad_ru.append(key)
	check(bad_empty.is_empty(), "no empty translations %s" % [bad_empty])
	check(bad_cyr.is_empty(), "no Cyrillic in English %s" % [bad_cyr])
	check(bad_fmt.is_empty(), "format placeholders match across all languages %s" % [bad_fmt])
	check(bad_ru.is_empty(), "Russian texts are Russian %s" % [bad_ru])


## Russian rows that legitimately contain no Cyrillic (a number, a language name).
func _latin_ru_ok() -> Array[String]:
	return [
		"CARD_TOWER_TIP",
		"SET_LANG_EN",
		"SET_LANG_ZH",
		"SET_LANG_IT",
		"SET_LANG_ES",
		"SET_LANG_KO",
		"SET_LANG_DE",
		"SET_LANG_PL",
		"SET_LANG_PT",
		"SET_LANG_TR",
		"SET_LANG_FR",
		"SET_LANG_JA",
	]


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
	for lang: String in EXPECTED_LANGUAGES:
		TranslationServer.set_locale(lang)
		var all_ok := true
		for key: String in rows:
			if TranslationServer.translate(key) == key:
				all_ok = false
				print("  missing at run time in %s: " % lang, key)
		check(all_ok, "the registered translation resolves every key in %s" % lang)
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
	check(GameSettings.resolve_locale("auto", "de") == "de", "auto + de system = de")
	check(GameSettings.resolve_locale("auto", "zh") == "zh", "auto + zh system = zh")
	check(GameSettings.resolve_locale("auto", "en") == "en", "auto + en system = en")
	check(
		GameSettings.resolve_locale("auto", "klingon") == "en",
		"auto + unknown system = fallback en"
	)
	check(GameSettings.resolve_locale("en", "ru") == "en", "forced en")
	check(GameSettings.resolve_locale("ru", "de") == "ru", "forced ru")
	check(GameSettings.resolve_locale("ja", "en") == "ja", "forced ja")
	var old_path: String = GameSettings.config_path
	GameSettings.config_path = "user://test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.config_path))
	check(GameSettings.language() == "auto", "default language is auto")
	for lang: String in GameSettings.SUPPORTED_LOCALES:
		GameSettings.set_language(lang)
		check(GameSettings.language() == lang, "%s saved" % lang)
		check(TranslationServer.get_locale().begins_with(lang), "%s applied at once" % lang)
	GameSettings.set_language("klingon")
	check(GameSettings.language() == "ja", "unknown language ignored")
	GameSettings.set_language("ru")
	check(TranslationServer.get_locale().begins_with("ru"), "ru applied")
	GameSettings.reset_controls_cache()
	check(GameSettings.is_tap_to_move() == true, "default tap_to_move is true")
	GameSettings.set_tap_to_move(false)
	check(GameSettings.is_tap_to_move() == false, "tap_to_move set to false")
	GameSettings.set_tap_to_move(true)
	check(GameSettings.is_tap_to_move() == true, "tap_to_move set to true")
	check(GameSettings.is_auto_attack() == true, "default auto_attack is true")
	GameSettings.set_auto_attack(false)
	check(GameSettings.is_auto_attack() == false, "auto_attack set to false")
	GameSettings.set_auto_attack(true)
	check(GameSettings.is_auto_attack() == true, "auto_attack set to true")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.config_path))
	GameSettings.config_path = old_path
	GameSettings.reset_controls_cache()


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
