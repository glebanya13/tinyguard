class_name CrashReporter
extends RefCounted
## Thin, safe wrapper over Firebase Crashlytics (crash reports only: no Analytics, no ads).
## Crashlytics lives in the Gradle build (docs/ANDROID_BUILD.md); GDScript reaches it through
## JavaClassWrapper, so there is no plugin and no autoload. Everywhere else (desktop, tests,
## the plain APK without Gradle) every call is a no-op that only counts calls.
## Collection is off in the manifest and switched on here, and only when the player has not
## turned crash reports off in the settings (GameSettings.crash_reports). Breadcrumbs must
## never carry personal data: level numbers, modes, memory, quality notches and the like.

const CRASHLYTICS_CLASS := "com.google.firebase.crashlytics.FirebaseCrashlytics"
const EXCEPTION_CLASS := "java.lang.RuntimeException"
## Longest text sent in one breadcrumb or key value.
const MAX_TEXT := 400
## Breadcrumbs kept in memory for the diagnostics and the tests.
const KEEP_LINES := 30
## An opaque user id: only a short lower-case hex hash is accepted (never a uid or an email).
const USER_ID_PATTERN := "^[0-9a-f]{8,64}$"

## Replaces the Crashlytics object (tests pass a fake with the same method names).
static var backend: Object = null
## Whether reports may be sent right now.
static var enabled: bool = false
## Calls per method name (tests and the diagnostics).
static var calls: Dictionary = {}
## The last breadcrumbs, newest last.
static var lines: Array[String] = []
## Custom keys set so far.
static var keys: Dictionary = {}
static var user_id: String = ""

static var _client: Object = null
static var _looked_up: bool = false
static var _exception_class: Object = null


## Call once at the start (boot scene) with the player's choice.
static func init(on: bool) -> void:
	_count("init")
	enabled = on
	_apply_enabled()


## The player flipped the switch in the settings: takes effect at once, no restart.
static func set_enabled(on: bool) -> void:
	_count("set_enabled")
	enabled = on
	_apply_enabled()


## True when a real Crashlytics client is there (Android Gradle build).
static func is_available() -> bool:
	return _crashlytics() != null


## A breadcrumb: shows in the report of a later crash.
static func log_line(message: String) -> void:
	_count("log")
	var text: String = _clean(message)
	lines.append(text)
	if lines.size() > KEEP_LINES:
		lines.pop_front()
	var client: Object = _crashlytics()
	if client != null and enabled:
		client.call("log", text)


## A custom key of the report ("level" = 3).
static func set_key(key: String, value: Variant) -> void:
	_count("set_key")
	var text: String = _clean(str(value))
	keys[key] = text
	var client: Object = _crashlytics()
	if client != null and enabled:
		client.call("setCustomKey", _clean(key), text)


## A non-fatal error: arrives in Crashlytics as an exception (grouped by its stack, so tell
## the cases apart by the message and the keys).
static func record_error(message: String) -> void:
	_count("record_error")
	var text: String = _clean(message)
	var client: Object = _crashlytics()
	if client == null or not enabled:
		return
	var throwable: Variant = _make_throwable(text)
	if throwable != null:
		client.call("recordException", throwable)
	else:
		client.call("log", "error: " + text)


## Opaque identifier of this install (a hash, see hash_id). Anything else is refused.
static func set_user_id(opaque: String) -> bool:
	_count("set_user_id")
	var re := RegEx.new()
	re.compile(USER_ID_PATTERN)
	if re.search(opaque) == null:
		return false
	user_id = opaque
	var client: Object = _crashlytics()
	if client != null and enabled:
		client.call("setUserId", opaque)
	return true


## Anonymous 16-character hash of a source string (never the source itself).
static func hash_id(source: String) -> String:
	return ("bimbleguard:" + source).sha256_text().substr(0, 16)


## A battle starts: the facts that explain a later crash.
static func battle_started(
	level_id: int, mode: String, difficulty: int, daily_preset: String
) -> void:
	set_key("level", level_id)
	set_key("mode", mode)
	set_key("difficulty", difficulty)
	set_key("daily_preset", daily_preset)
	log_line("battle start: level %d mode %s difficulty %d" % [level_id, mode, difficulty])


## Test helper: forgets everything (also the fake backend).
static func reset() -> void:
	backend = null
	enabled = false
	calls = {}
	lines = []
	keys = {}
	user_id = ""
	_client = null
	_looked_up = false
	_exception_class = null


static func _count(name: String) -> void:
	calls[name] = int(calls.get(name, 0)) + 1


## One line, no control characters, shortened.
static func _clean(text: String) -> String:
	var out: String = text.replace("\n", " ").replace("\r", " ").strip_edges()
	return out.substr(0, MAX_TEXT)


static func _apply_enabled() -> void:
	var client: Object = _crashlytics()
	if client != null:
		client.call("setCrashlyticsCollectionEnabled", enabled)


## The Crashlytics object, or null when there is none (desktop, APK without Gradle).
static func _crashlytics() -> Object:
	if backend != null:
		return backend
	if _looked_up:
		return _client
	_looked_up = true
	if OS.get_name() != "Android":
		return null
	var wrapper: Object = JavaClassWrapper.wrap(CRASHLYTICS_CLASS)
	if wrapper == null or not wrapper.has_java_method("getInstance"):
		return null
	var instance: Variant = wrapper.call("getInstance")
	if instance is Object:
		_client = instance
	return _client


## A java.lang.RuntimeException(message), or null when the wrapper cannot build one.
static func _make_throwable(text: String) -> Variant:
	if backend != null:
		return text
	if _exception_class == null:
		_exception_class = JavaClassWrapper.wrap(EXCEPTION_CLASS)
	if _exception_class == null:
		return null
	for constructor: String in ["new", "<init>"]:
		if _exception_class.has_java_method(constructor):
			return _exception_class.call(constructor, text)
	return null
