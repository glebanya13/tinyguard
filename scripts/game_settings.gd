class_name GameSettings
extends RefCounted
## Device-local settings that are not part of the cloud profile: the interface
## language (auto / ru / en). Stored in user://settings.cfg and never synced.
## Sound lives in the profile (LevelCatalog.sound_on). Also the one place that
## opens web pages (https only).

const LANG_AUTO := "auto"
const LANGUAGES: Array[String] = [
	"auto", "ru", "en", "zh", "it", "es", "ko", "de", "pl", "pt", "tr", "fr", "ja"
]
## Visual effects (hit flashes, damage numbers, particles, screen shake): off /
## minimum / full. They never touch the battle simulation.
const FX_OFF := 0
const FX_MIN := 1
const FX_FULL := 2
const FX_NAMES: Array[String] = ["off", "min", "full"]
## Thumb controls (index settings, saved in settings.cfg, device-local): joystick size
## 0 small / 1 medium / 2 large, position 0 lower / 1 standard / 2 higher, side 0 left /
## 1 right; road compass size 0..2 and mode 0 show / 1 hide / 2 at the start of a wave.
const LAYOUT_DEFAULTS := {
	"joystick_size": 1,
	"joystick_pos": 1,
	"joystick_side": 0,
	"minimap_size": 1,
	"minimap_mode": 2,
}
## Graphics quality choice (auto / low / medium / high) and the tier it resolves to. Purely
## visual (shadows, MSAA, effects): never touches the simulation. "auto" looks at the phone.
const GFX_AUTO := 0
const GFX_LOW := 1
const GFX_MEDIUM := 2
const GFX_HIGH := 3
const GFX_NAMES: Array[String] = ["auto", "low", "medium", "high"]
## Phones with less physical RAM than this (MB) start on the low tier. A "3 GB" phone reports
## about 2.7-2.9 GB, a "4 GB" one about 3.6-3.9 GB (the kernel keeps a part). 4 GB and less is
## low: Android keeps a quarter of it for itself and kills a game that asks for more.
const LOW_RAM_MB := 4400
## Phones with less than this (a "2-3 GB" phone) start one notch lower still.
const VERY_LOW_RAM_MB := 3300
## Phones with at least this much RAM (MB) and no weak GPU start on the high tier.
const HIGH_RAM_MB := 5400
## GPU names (lower case) of entry-level chips: old Mali-4xx/T, G31/G51/G52/G71, Adreno 3xx-5xx
## and 610-613/619 (Redmi Note 12 4G / 5G), PowerVR. A heuristic: the player can always
## pick the tier by hand.
const WEAK_GPU_PATTERN := (
	"mali-(4\\d\\d|t\\d+|g31|g51|g52|g71)" + "|adreno \\(tm\\) ?([345]\\d\\d|61[01239])\\b|powervr"
)
## Locale used when the system language has no translation.
const FALLBACK_LOCALE := "en"
const SUPPORTED_LOCALES: Array[String] = [
	"ru", "en", "zh", "it", "es", "ko", "de", "pl", "pt", "tr", "fr", "ja"
]

## Tests point this at a scratch file.
static var config_path: String = "user://settings.cfg"
## Tier found on this device (GFX_LOW..GFX_HIGH); 0 = not detected yet.
static var _detected: int = 0
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


## Saved graphics choice: GFX_AUTO .. GFX_HIGH.
static func graphics() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return GFX_AUTO
	var name: String = str(cfg.get_value("ui", "graphics", "auto"))
	return maxi(GFX_NAMES.find(name), 0)


static func set_graphics(choice: int) -> void:
	choice = clampi(choice, GFX_AUTO, GFX_HIGH)
	var cfg := ConfigFile.new()
	cfg.load(config_path)
	cfg.set_value("ui", "graphics", GFX_NAMES[choice])
	cfg.save(config_path)


## The tier a phone gets from its memory and GPU (pure: tests feed it numbers). Desktop
## builds always get the high tier; unknown memory (<= 0) does not lower anything.
static func classify_device(ram_mb: int, adapter: String, mobile: bool) -> int:
	if not mobile:
		return GFX_HIGH
	var gpu_name: String = adapter.to_lower()
	var weak_gpu: bool = false
	if gpu_name != "":
		var re := RegEx.new()
		re.compile(WEAK_GPU_PATTERN)
		weak_gpu = re.search(gpu_name) != null
	if weak_gpu or (ram_mb > 0 and ram_mb < LOW_RAM_MB):
		return GFX_LOW
	if ram_mb >= HIGH_RAM_MB:
		return GFX_HIGH
	return GFX_MEDIUM


## Tier of this device (found once per run).
static func detected_tier() -> int:
	if _detected == 0:
		var physical: int = int(OS.get_memory_info().get("physical", -1))
		_detected = classify_device(
			physical / 1048576 if physical > 0 else -1,
			RenderingServer.get_video_adapter_name(),
			OS.has_feature("mobile")
		)
	return _detected


## The tier a battle starts on: the choice, or the detected one for "auto".
static func graphics_tier() -> int:
	var choice: int = graphics()
	return detected_tier() if choice == GFX_AUTO else choice


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


## Crash reports (Firebase Crashlytics, Gradle builds only): on unless the player turned them
## off in the settings. Device-local, never synced. See CrashReporter, docs/PRIVACY.md.
static func crash_reports() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return true
	return bool(cfg.get_value("privacy", "crash_reports", true))


static func set_crash_reports(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(config_path)
	cfg.set_value("privacy", "crash_reports", on)
	cfg.save(config_path)


static func layout_value(key: String) -> int:
	var cfg := ConfigFile.new()
	var fallback: int = LAYOUT_DEFAULTS[key]
	if cfg.load(config_path) != OK:
		return fallback
	var max_value: int = 1 if key == "joystick_side" else 2
	return clampi(int(cfg.get_value("layout", key, fallback)), 0, max_value)


static func set_layout_value(key: String, value: int) -> void:
	if not LAYOUT_DEFAULTS.has(key):
		return
	var cfg := ConfigFile.new()
	cfg.load(config_path)
	cfg.set_value("layout", key, value)
	cfg.save(config_path)


static func joystick_size() -> int:
	return layout_value("joystick_size")


static func joystick_position() -> int:
	return layout_value("joystick_pos")


static func joystick_side() -> int:
	return layout_value("joystick_side")


static func minimap_size() -> int:
	return layout_value("minimap_size")


static func minimap_mode() -> int:
	return layout_value("minimap_mode")


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
