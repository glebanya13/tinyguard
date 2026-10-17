class_name ExitReasons
extends RefCounted
## Why did the previous run of the game end? Android 11+ remembers it
## (ActivityManager.getHistoricalProcessExitReasons -> ApplicationExitInfo), including the kills
## Crashlytics never sees: the system killing the process for memory (SIGKILL, no signal handler
## runs). Read through JavaClassWrapper at the start, without a plugin. A run killed for memory,
## by a crash or by an ANR while the player was playing counts against the device: the next battles
## start with a lower visual quality (see QualityGuard.setup) until a run lives long enough.
## Everything else here is pure functions (tests/test_exit_reasons.gd); on desktop and on
## Android older than 11 the reading is a no-op. See docs/DEBUG_ANDROID.md.

const REASON_UNKNOWN := 0
const REASON_EXIT_SELF := 1
const REASON_SIGNALED := 2
const REASON_LOW_MEMORY := 3
const REASON_CRASH := 4
const REASON_CRASH_NATIVE := 5
const REASON_ANR := 6
const REASON_INITIALIZATION_FAILURE := 7
const REASON_PERMISSION_CHANGE := 8
const REASON_EXCESSIVE_RESOURCE_USAGE := 9
const REASON_USER_REQUESTED := 10
const REASON_USER_STOPPED := 11
const REASON_DEPENDENCY_DIED := 12
const REASON_OTHER := 13
const REASON_FREEZER := 14
const REASON_PACKAGE_STATE_CHANGE := 15
const REASON_PACKAGE_UPDATED := 16

## ApplicationExitInfo.REASON_* codes.
const REASON_NAMES: Dictionary = {
	0: "UNKNOWN",
	1: "EXIT_SELF",
	2: "SIGNALED",
	3: "LOW_MEMORY",
	4: "CRASH",
	5: "CRASH_NATIVE",
	6: "ANR",
	7: "INITIALIZATION_FAILURE",
	8: "PERMISSION_CHANGE",
	9: "EXCESSIVE_RESOURCE_USAGE",
	10: "USER_REQUESTED",
	11: "USER_STOPPED",
	12: "DEPENDENCY_DIED",
	13: "OTHER",
	14: "FREEZER",
	15: "PACKAGE_STATE_CHANGE",
	16: "PACKAGE_UPDATED",
}
## ActivityManager.RunningAppProcessInfo.IMPORTANCE_* codes.
const IMPORTANCE_NAMES: Dictionary = {
	100: "FOREGROUND",
	125: "FOREGROUND_SERVICE",
	150: "TOP_SLEEPING",
	200: "VISIBLE",
	230: "PERCEPTIBLE",
	300: "SERVICE",
	325: "CANT_SAVE_STATE",
	350: "CANT_SAVE_STATE",
	400: "CACHED",
	1000: "GONE",
}
## The process was in front of the player or still noticeable (up to PERCEPTIBLE).
const IMPORTANCE_PLAYING_MAX := 230
const SIGKILL := 9

const KIND_OK := "ok"
const KIND_LOW_MEMORY := "low_memory"
const KIND_PROBABLE_LOW_MEMORY := "probable_low_memory"
const KIND_CRASH := "crash"
const KIND_NATIVE_CRASH := "native_crash"
const KIND_ANR := "anr"
const KIND_KILLED := "killed"
const KIND_OTHER := "other"
## Kinds that say "the game did not fit this phone".
const BAD_KINDS: Array[String] = [
	KIND_LOW_MEMORY, KIND_PROBABLE_LOW_MEMORY, KIND_CRASH, KIND_NATIVE_CRASH, KIND_ANR
]

const MAX_RECORDS := 5
## A run that lived this long (seconds) clears the streak of bad exits.
const SURVIVED_SECONDS := 600.0
## Longest description text kept from the system.
const DESCRIPTION_MAX := 160

## Tests point this at a scratch file.
static var state_path: String = "user://exit_reasons.cfg"
## Bad runs in a row (0 = the previous run was fine or lived long enough).
static var streak: int = 0
## Text for the diagnostics overlay; "" when there is nothing to say.
static var last_text: String = ""
## Parsed records of this start (newest first), for the diagnostics and the tests.
static var last_records: Array[Dictionary] = []

static var _loaded: bool = false
static var _last_timestamp: int = 0
static var _run_started: float = 0.0

# --- Pure functions ---


static func reason_name(code: int) -> String:
	return str(REASON_NAMES.get(code, "UNKNOWN_%d" % code))


static func importance_name(code: int) -> String:
	return str(IMPORTANCE_NAMES.get(code, "IMPORTANCE_%d" % code))


## What an exit means. `low_memory_report`: the system tells about memory kills (API 34+,
## ActivityManager.isLowMemoryKillReportSupported). Without it a bare SIGKILL is, most often,
## the low-memory killer, so it is a probable memory kill; with it, it is some other kill.
static func classify(reason: int, status: int, low_memory_report: bool) -> String:
	match reason:
		REASON_LOW_MEMORY:
			return KIND_LOW_MEMORY
		REASON_CRASH, REASON_INITIALIZATION_FAILURE:
			return KIND_CRASH
		REASON_CRASH_NATIVE:
			return KIND_NATIVE_CRASH
		REASON_ANR:
			return KIND_ANR
		REASON_SIGNALED:
			if status == SIGKILL:
				return KIND_KILLED if low_memory_report else KIND_PROBABLE_LOW_MEMORY
			return KIND_CRASH if status in [4, 6, 7, 8, 11] else KIND_KILLED  # ILL ABRT BUS FPE SEGV
		REASON_EXIT_SELF, REASON_USER_REQUESTED, REASON_USER_STOPPED:
			return KIND_OK
		REASON_PACKAGE_UPDATED, REASON_PACKAGE_STATE_CHANGE, REASON_PERMISSION_CHANGE:
			return KIND_OK
		REASON_EXCESSIVE_RESOURCE_USAGE, REASON_FREEZER:
			return KIND_KILLED
	return KIND_OTHER


## Raw record {reason, status, importance, pss_kb, rss_kb, timestamp, description, pid}
## to a record with the names and the kind.
static func parse(raw: Dictionary, low_memory_report: bool) -> Dictionary:
	var reason: int = int(raw.get("reason", REASON_UNKNOWN))
	var status: int = int(raw.get("status", 0))
	var importance: int = int(raw.get("importance", 0))
	return {
		"reason": reason,
		"reason_name": reason_name(reason),
		"status": status,
		"importance": importance,
		"importance_name": importance_name(importance),
		"kind": classify(reason, status, low_memory_report),
		"pss_mb": int(raw.get("pss_kb", 0)) / 1024,
		"rss_mb": int(raw.get("rss_kb", 0)) / 1024,
		"timestamp": int(raw.get("timestamp", 0)),
		"description": str(raw.get("description", "")).substr(0, DESCRIPTION_MAX),
	}


## Records (any order) newer than `last_timestamp`, newest first.
static func newer_than(records: Array, last_timestamp: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for record: Variant in records:
		if (
			record is Dictionary
			and int((record as Dictionary).get("timestamp", 0)) > last_timestamp
		):
			out.append(record)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["timestamp"] > b["timestamp"]
	)
	return out


## The exit hurt the player: a bad kind while the game was in front (or the old note says it
## was in a battle). A cached process killed in the background is the system doing its job.
static func counts_against_quality(record: Dictionary, note_state: String = "") -> bool:
	if not str(record.get("kind", "")) in BAD_KINDS:
		return false
	return int(record.get("importance", 0)) <= IMPORTANCE_PLAYING_MAX or note_state == "battle"


## The streak after the newest exit: one more when it counts, zero otherwise.
static func next_streak(current: int, newest: Dictionary, note_state: String = "") -> int:
	return current + 1 if counts_against_quality(newest, note_state) else 0


## Quality notches (QualityGuard) a battle starts lowered by for a streak: 0, then 2, 3, 4.
static func notch_for_streak(bad_runs: int) -> int:
	return 0 if bad_runs <= 0 else mini(bad_runs + 1, 4)


## "prev exit: LOW_MEMORY rss=612 MB importance FOREGROUND (low_memory)".
static func summary(record: Dictionary) -> String:
	var text: String = (
		"prev exit: %s%s rss=%d MB pss=%d MB %s (%s)"
		% [
			record["reason_name"],
			"/%d" % int(record["status"]) if int(record["reason"]) == REASON_SIGNALED else "",
			int(record["rss_mb"]),
			int(record["pss_mb"]),
			record["importance_name"],
			record["kind"],
		]
	)
	if str(record.get("description", "")) != "":
		text += " " + str(record["description"])
	return text


# --- State ---


## Notches a battle starts lowered by because of bad runs in a row (0 on desktop).
static func start_notch() -> int:
	_load_state()
	return notch_for_streak(streak)


## Call now and then (a battle trace): a run that lived long enough clears the streak.
static func tick() -> void:
	_load_state()
	if streak > 0 and Time.get_unix_time_from_system() - _run_started >= SURVIVED_SECONDS:
		streak = 0
		_save_state()


## At the start of the game. `send`: the player allows reports (see GameSettings.crash_reports).
static func run_startup(send: bool = true) -> void:
	var android: Dictionary = read_android(MAX_RECORDS)
	startup_with(
		android.get("records", []),
		bool(android.get("low_memory_report", false)),
		str(CrashTrace.read_previous().get("state", "")),
		send
	)


## The part of run_startup that does not need Android (tests feed records).
static func startup_with(
	raw_records: Array, low_memory_report: bool, note_state: String, send: bool
) -> void:
	_load_state()
	var parsed: Array = []
	for raw: Variant in raw_records:
		if raw is Dictionary:
			parsed.append(parse(raw, low_memory_report))
	last_records = newer_than(parsed, _last_timestamp)
	last_text = ""
	if not last_records.is_empty():
		var newest: Dictionary = last_records[0]
		streak = next_streak(streak, newest, note_state)
		last_text = summary(newest)
		_last_timestamp = int(newest["timestamp"])
		if send:
			CrashReporter.log_line(last_text)
			_report(last_records)
	_run_started = Time.get_unix_time_from_system()
	_save_state()


## Sends the bad exits as non-fatal errors with keys (the newest wins the keys).
static func _report(records: Array[Dictionary]) -> void:
	var newest: Dictionary = records[0]
	CrashReporter.set_key("prev_exit_reason", newest["reason_name"])
	CrashReporter.set_key("prev_exit_kind", newest["kind"])
	CrashReporter.set_key("prev_exit_importance", newest["importance_name"])
	CrashReporter.set_key("prev_exit_rss_mb", newest["rss_mb"])
	CrashReporter.set_key("prev_exit_pss_mb", newest["pss_mb"])
	CrashReporter.set_key("prev_exit_streak", streak)
	for record: Dictionary in records:
		if str(record["kind"]) in BAD_KINDS or str(record["kind"]) == KIND_KILLED:
			CrashReporter.record_error(summary(record))


static func _load_state() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(state_path) != OK:
		return
	streak = clampi(int(cfg.get_value("exit", "streak", 0)), 0, 99)
	_last_timestamp = int(cfg.get_value("exit", "last_timestamp", 0))
	_run_started = float(cfg.get_value("exit", "run_started", 0.0))


static func _save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("exit", "streak", streak)
	cfg.set_value("exit", "last_timestamp", _last_timestamp)
	cfg.set_value("exit", "run_started", _run_started)
	cfg.save(state_path)


## Test helper: forget the loaded state (the file stays).
static func reset() -> void:
	streak = 0
	last_text = ""
	last_records = []
	_loaded = false
	_last_timestamp = 0
	_run_started = 0.0


# --- Android ---


## {records: Array of raw dictionaries (newest first), low_memory_report: bool}; empty when
## this is not Android 11+ or the system object cannot be reached.
static func read_android(max_count: int) -> Dictionary:
	var empty: Dictionary = {"records": [], "low_memory_report": false}
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return empty
	var runtime: Object = Engine.get_singleton("AndroidRuntime")
	var activity: Variant = runtime.call("getActivity")
	var manager_class: Object = JavaClassWrapper.wrap("android.app.ActivityManager")
	if not activity is Object or manager_class == null:
		return empty
	if not manager_class.has_java_method("getHistoricalProcessExitReasons"):
		return empty  # Android older than 11
	var manager: Variant = (activity as Object).call("getSystemService", "activity")
	if not manager is Object:
		return empty
	var package_name: String = str((activity as Object).call("getPackageName"))
	var list: Variant = (manager as Object).call(
		"getHistoricalProcessExitReasons", package_name, 0, max_count
	)
	var supported: bool = false
	if manager_class.has_java_method("isLowMemoryKillReportSupported"):
		supported = bool(manager_class.call("isLowMemoryKillReportSupported"))
	var records: Array = []
	if list is Object:
		var size: int = int((list as Object).call("size"))
		for i in mini(size, max_count):
			var info: Variant = (list as Object).call("get", i)
			if info is Object:
				records.append(_raw_from_java(info as Object))
	return {"records": records, "low_memory_report": supported}


static func _raw_from_java(info: Object) -> Dictionary:
	var description: Variant = info.call("getDescription")
	return {
		"reason": int(info.call("getReason")),
		"status": int(info.call("getStatus")),
		"importance": int(info.call("getImportance")),
		"pss_kb": int(info.call("getPss")),
		"rss_kb": int(info.call("getRss")),
		"timestamp": int(info.call("getTimestamp")),
		"description": str(description) if description != null else "",
		"pid": int(info.call("getPid")),
	}
