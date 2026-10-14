class_name GameSettings
extends RefCounted
## Device-local settings that are not part of the cloud profile: the interface
## language (auto / ru / en). Stored in user://settings.cfg and never synced.
## Sound lives in the profile (LevelCatalog.sound_on). Also the one place that
## opens web pages (https only).

const LANG_AUTO := "auto"
const LANGUAGES: Array[String] = ["auto", "ru", "en"]
## Locale used when the system language has no translation.
const FALLBACK_LOCALE := "en"
const SUPPORTED_LOCALES: Array[String] = ["ru", "en"]

## Tests point this at a scratch file.
static var config_path: String = "user://settings.cfg"


## Saved choice: "auto", "ru" or "en".
static func language() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return LANG_AUTO
	var code: String = str(cfg.get_value("ui", "language", LANG_AUTO))
	return code if code in LANGUAGES else LANG_AUTO


## Saves the choice and applies it right away.
static func set_language(code: String) -> void:
	if not code in LANGUAGES:
		return
	var cfg := ConfigFile.new()
	cfg.load(config_path)  # keep other keys; a missing file is fine
	cfg.set_value("ui", "language", code)
	cfg.save(config_path)
	apply_language()


## The locale for a choice: "ru"/"en" as is; "auto" follows the system language
## (Russian for ru, English for everything else).
static func resolve_locale(code: String, system_language: String) -> String:
	if code in SUPPORTED_LOCALES:
		return code
	return system_language if system_language in SUPPORTED_LOCALES else FALLBACK_LOCALE


## Sets TranslationServer's locale from the saved choice.
static func apply_language() -> void:
	TranslationServer.set_locale(resolve_locale(language(), OS.get_locale_language()))


## Only plain https:// links are opened (no http, file, intent or other schemes).
static func is_safe_url(url: String) -> bool:
	if not url.begins_with("https://") or url.length() <= "https://".length():
		return false
	for i in url.length():
		var code: int = url.unicode_at(i)
		if code <= 32 or code == 127:
			return false
	return true


## Opens `url` in the system browser when it is an https link; false otherwise.
static func open_url(url: String) -> bool:
	if not is_safe_url(url):
		return false
	return OS.shell_open(url) == OK


## The game version from project.godot.
static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))
