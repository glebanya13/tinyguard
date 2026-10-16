class_name GameSettings
extends RefCounted
## Device-local settings that are not part of the cloud profile: the interface
## language (auto / ru / en). Stored in user://settings.cfg and never synced.
## Sound lives in the profile (LevelCatalog.sound_on). Also the one place that
## opens web pages (https only).

const LANG_AUTO := "auto"
const LANGUAGES: Array[String] = ["auto", "ru", "en"]
## Visual effects (hit flashes, damage numbers, particles, screen shake): off /
## minimum / full. They never touch the battle simulation.
const FX_OFF := 0
const FX_MIN := 1
const FX_FULL := 2
const FX_NAMES: Array[String] = ["off", "min", "full"]
## Locale used when the system language has no translation.
const FALLBACK_LOCALE := "en"
const SUPPORTED_LOCALES: Array[String] = ["ru", "en"]

## Tests point this at a scratch file.
static var config_path: String = "user://settings.cfg"
## Cached effects level (FX_*); -1 = not read from the file yet.
static var _effects: int = -1
## Level forced by BIMBLEGUARD_FX (-1 = none); -2 = environment not read yet.
static var _forced: int = -2
## Ceiling set by the quality guard when the device cannot keep up (this session only,
## never saved: the player's own choice stays what the settings panel shows).
static var _cap: int = FX_FULL


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


## Effects level: FX_OFF / FX_MIN / FX_FULL. BIMBLEGUARD_FX=off|min|full overrides
## the saved choice (tests, screenshots).
static func effects() -> int:
	if _forced == -2:
		_forced = FX_NAMES.find(OS.get_environment("BIMBLEGUARD_FX"))
	if _forced >= 0:
		return _forced
	if _effects < 0:
		var cfg := ConfigFile.new()
		var name: String = "full"
		if cfg.load(config_path) == OK:
			name = str(cfg.get_value("ui", "effects", "full"))
		_effects = maxi(FX_NAMES.find(name), 0) if name in FX_NAMES else FX_FULL
	return _effects


static func set_effects(level: int) -> void:
	level = clampi(level, FX_OFF, FX_FULL)
	var cfg := ConfigFile.new()
	cfg.load(config_path)
	cfg.set_value("ui", "effects", FX_NAMES[level])
	cfg.save(config_path)
	_effects = level


## Effects level the battle really uses: the choice, lowered by the quality guard.
static func effects_now() -> int:
	return mini(effects(), _cap)


## The quality guard lowers the effects to at most `level` until the app is closed.
static func cap_effects(level: int) -> void:
	_cap = clampi(level, FX_OFF, FX_FULL)


static func effects_cap() -> int:
	return _cap


## Diagnostics overlay (FPS, memory, enemies): hidden until the version line in the
## settings is tapped five times.
static func diagnostics() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(config_path) == OK and bool(cfg.get_value("ui", "diagnostics", false))


static func set_diagnostics(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(config_path)
	cfg.set_value("ui", "diagnostics", on)
	cfg.save(config_path)


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
