extends SceneTree
## Why the previous run ended (ExitReasons) and the crash report wrapper (CrashReporter):
## code names, classification, "newer than the last seen", the streak that lowers the start
## quality, and the no-op / fake-backend behaviour off Android.
## godot --headless --path . --script res://tests/test_exit_reasons.gd

var fails := 0


# gdlint: disable=function-name
# (the fake mirrors the Java method names of FirebaseCrashlytics)
class FakeCrashlytics:
	extends Object
	var calls: Array = []

	func log(text: String) -> void:
		calls.append(["log", text])

	func setCustomKey(key: String, value: String) -> void:
		calls.append(["setCustomKey", key, value])

	func recordException(error: Variant) -> void:
		calls.append(["recordException", error])

	func setUserId(id: String) -> void:
		calls.append(["setUserId", id])

	func setCrashlyticsCollectionEnabled(on: bool) -> void:
		calls.append(["setCrashlyticsCollectionEnabled", on])


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	ExitReasons.state_path = "user://test_exit_reasons.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ExitReasons.state_path))
	ExitReasons.reset()
	GameSettings.config_path = "user://test_exit_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.config_path))
	_run.call_deferred()


func _run() -> void:
	_test_names()
	_test_classify()
	_test_records()
	_test_streak()
	_test_startup()
	_test_reporter_noop()
	_test_reporter_fake()
	_test_settings()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ExitReasons.state_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.config_path))
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _raw(reason: int, status: int, importance: int, ts: int, rss_kb: int = 614400) -> Dictionary:
	return {
		"reason": reason,
		"status": status,
		"importance": importance,
		"timestamp": ts,
		"rss_kb": rss_kb,
		"pss_kb": 307200,
		"description": "test",
	}


func _test_names() -> void:
	check(ExitReasons.reason_name(3) == "LOW_MEMORY", "3 is LOW_MEMORY")
	check(ExitReasons.reason_name(2) == "SIGNALED", "2 is SIGNALED")
	check(ExitReasons.reason_name(5) == "CRASH_NATIVE", "5 is CRASH_NATIVE")
	check(ExitReasons.reason_name(6) == "ANR", "6 is ANR")
	check(ExitReasons.reason_name(10) == "USER_REQUESTED", "10 is USER_REQUESTED")
	check(ExitReasons.reason_name(16) == "PACKAGE_UPDATED", "16 is PACKAGE_UPDATED")
	check(ExitReasons.reason_name(99) == "UNKNOWN_99", "an unknown code keeps its number")
	check(ExitReasons.REASON_NAMES.size() == 17, "all 17 reasons of API 33 are named")
	check(ExitReasons.importance_name(100) == "FOREGROUND", "importance 100")
	check(ExitReasons.importance_name(400) == "CACHED", "importance 400")
	check(ExitReasons.importance_name(7) == "IMPORTANCE_7", "an unknown importance")


func _test_classify() -> void:
	check(ExitReasons.classify(3, 0, true) == ExitReasons.KIND_LOW_MEMORY, "LOW_MEMORY")
	check(ExitReasons.classify(3, 0, false) == ExitReasons.KIND_LOW_MEMORY, "LOW_MEMORY, no report")
	check(ExitReasons.classify(4, 0, false) == ExitReasons.KIND_CRASH, "Java crash")
	check(ExitReasons.classify(5, 11, false) == ExitReasons.KIND_NATIVE_CRASH, "native crash")
	check(ExitReasons.classify(6, 0, false) == ExitReasons.KIND_ANR, "ANR")
	check(ExitReasons.classify(7, 0, false) == ExitReasons.KIND_CRASH, "initialization failure")
	check(
		ExitReasons.classify(2, 9, false) == ExitReasons.KIND_PROBABLE_LOW_MEMORY,
		"SIGKILL without memory reports is a probable memory kill"
	)
	check(
		ExitReasons.classify(2, 9, true) == ExitReasons.KIND_KILLED,
		"SIGKILL where memory kills are reported is some other kill"
	)
	check(ExitReasons.classify(2, 11, false) == ExitReasons.KIND_CRASH, "SIGSEGV is a crash")
	check(ExitReasons.classify(2, 15, false) == ExitReasons.KIND_KILLED, "SIGTERM is a kill")
	for ok_reason: int in [1, 10, 11, 8, 15, 16]:
		check(ExitReasons.classify(ok_reason, 0, false) == ExitReasons.KIND_OK, "ok %d" % ok_reason)
	check(ExitReasons.classify(9, 0, false) == ExitReasons.KIND_KILLED, "excessive resource usage")
	check(ExitReasons.classify(0, 0, false) == ExitReasons.KIND_OTHER, "unknown reason")
	check(ExitReasons.classify(12, 0, false) == ExitReasons.KIND_OTHER, "dependency died")


func _test_records() -> void:
	var rec: Dictionary = ExitReasons.parse(_raw(3, 0, 100, 5000), true)
	check(rec["reason_name"] == "LOW_MEMORY" and rec["rss_mb"] == 600, "parse: names, rss MB")
	check(rec["pss_mb"] == 300 and rec["importance_name"] == "FOREGROUND", "parse: pss, importance")
	var text: String = ExitReasons.summary(rec)
	check("LOW_MEMORY" in text and "rss=600" in text and "FOREGROUND" in text, text)
	var sig: String = ExitReasons.summary(ExitReasons.parse(_raw(2, 9, 100, 5000), false))
	check("SIGNALED/9" in sig and "probable_low_memory" in sig, sig)

	var all: Array = [
		ExitReasons.parse(_raw(1, 0, 400, 1000), false),
		ExitReasons.parse(_raw(3, 0, 100, 3000), false),
		ExitReasons.parse(_raw(4, 0, 100, 2000), false),
	]
	var fresh: Array[Dictionary] = ExitReasons.newer_than(all, 1500)
	check(fresh.size() == 2, "two records are newer than 1500 (%d)" % fresh.size())
	check(fresh[0]["timestamp"] == 3000 and fresh[1]["timestamp"] == 2000, "newest first")
	check(ExitReasons.newer_than(all, 3000).is_empty(), "nothing is newer than the newest")
	check(ExitReasons.newer_than(all, 0).size() == 3, "everything is newer than zero")
	check(
		ExitReasons.newer_than([], 0).is_empty() and ExitReasons.newer_than(["x"], 0).is_empty(),
		"junk and nothing are fine"
	)
	var long: String = "x".repeat(500)
	var cut: Dictionary = ExitReasons.parse({"reason": 13, "description": long}, false)
	check(str(cut["description"]).length() == ExitReasons.DESCRIPTION_MAX, "description cut")


func _test_streak() -> void:
	var low: Dictionary = ExitReasons.parse(_raw(3, 0, 100, 1), false)
	var cached_kill: Dictionary = ExitReasons.parse(_raw(2, 9, 400, 1), false)
	var fine: Dictionary = ExitReasons.parse(_raw(1, 0, 100, 1), false)
	check(ExitReasons.counts_against_quality(low), "a memory kill in front counts")
	check(not ExitReasons.counts_against_quality(cached_kill), "a cached process kill does not")
	check(
		ExitReasons.counts_against_quality(cached_kill, "battle"),
		"unless the old note says it was a battle"
	)
	check(not ExitReasons.counts_against_quality(fine), "an orderly exit does not")
	check(ExitReasons.next_streak(0, low) == 1 and ExitReasons.next_streak(1, low) == 2, "grows")
	check(ExitReasons.next_streak(2, fine) == 0, "an orderly exit clears it")
	check(ExitReasons.notch_for_streak(0) == 0, "no streak, no notch")
	check(ExitReasons.notch_for_streak(1) == 2, "first bad run: shadows and MSAA go")
	check(ExitReasons.notch_for_streak(2) == 3, "second: fewer effects")
	check(ExitReasons.notch_for_streak(7) == 4, "never above the last notch")
	check(ExitReasons.notch_for_streak(7) <= QualityGuard.MAX_LEVEL, "matches the guard")


func _test_startup() -> void:
	CrashReporter.reset()
	ExitReasons.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ExitReasons.state_path))
	var fake := FakeCrashlytics.new()
	CrashReporter.backend = fake
	CrashReporter.enabled = true
	var records: Array = [_raw(3, 0, 100, 2000), _raw(1, 0, 400, 1000)]
	ExitReasons.startup_with(records, true, "battle", true)
	check(ExitReasons.streak == 1, "a memory kill in a battle starts a streak")
	check(ExitReasons.start_notch() == 2, "the next battle starts lowered")
	check("LOW_MEMORY" in ExitReasons.last_text, "overlay text: %s" % ExitReasons.last_text)
	var errors: int = 0
	for call: Array in fake.calls:
		if call[0] == "recordException":
			errors += 1
	check(errors == 1, "one non-fatal for the one bad record (%d)" % errors)
	check(CrashReporter.keys.get("prev_exit_reason") == "LOW_MEMORY", "keys carry the reason")

	# The same records again: nothing is new, nothing is sent twice.
	fake.calls.clear()
	ExitReasons.startup_with(records, true, "", true)
	check(ExitReasons.streak == 1 and fake.calls.is_empty(), "old records are not counted twice")

	# The state survives a restart of the process.
	ExitReasons.reset()
	check(ExitReasons.start_notch() == 2, "streak is read back from the file")

	# A newer orderly exit clears it.
	ExitReasons.startup_with([_raw(10, 0, 100, 3000)], true, "", true)
	check(ExitReasons.streak == 0 and ExitReasons.start_notch() == 0, "orderly exit clears")

	# Reports off: the quality still adapts, nothing is sent.
	fake.calls.clear()
	ExitReasons.startup_with([_raw(2, 9, 100, 4000)], false, "", false)
	check(ExitReasons.streak == 1, "SIGKILL on a device without reports counts")
	check(fake.calls.is_empty(), "nothing is sent when the player said no")

	# A run that lived long enough clears the streak.
	ExitReasons._run_started = Time.get_unix_time_from_system() - ExitReasons.SURVIVED_SECONDS - 1
	ExitReasons.tick()
	check(ExitReasons.streak == 0, "a long run clears the streak")
	ExitReasons.reset()
	check(ExitReasons.start_notch() == 0, "and it is saved")

	# Off Android there is nothing to read.
	var none: Dictionary = ExitReasons.read_android(5)
	check(none["records"].is_empty(), "no Android, no records")
	fake.free()
	CrashReporter.reset()


func _test_reporter_noop() -> void:
	CrashReporter.reset()
	CrashReporter.init(true)
	check(not CrashReporter.is_available(), "no Crashlytics on this machine")
	CrashReporter.log_line("hello\nworld")
	CrashReporter.set_key("level", 3)
	CrashReporter.record_error("boom")
	CrashReporter.set_enabled(false)
	check(
		CrashReporter.calls.get("log") == 1 and CrashReporter.calls.get("set_key") == 1, "counted"
	)
	check(CrashReporter.calls.get("record_error") == 1, "error counted")
	check(CrashReporter.lines[0] == "hello world", "one line: %s" % CrashReporter.lines[0])
	check(CrashReporter.keys["level"] == "3", "key kept as text")
	check(not CrashReporter.enabled, "switched off")
	check(CrashReporter.set_user_id("not an id") == false, "an email or uid is refused")
	check(CrashReporter.set_user_id("a@b.c") == false, "an email is refused")
	var hashed: String = CrashReporter.hash_id("some-firebase-uid")
	check(hashed.length() == 16 and "some" not in hashed, "hash is opaque: %s" % hashed)
	check(CrashReporter.set_user_id(hashed), "a hash is accepted")
	for i in CrashReporter.KEEP_LINES + 10:
		CrashReporter.log_line("line %d" % i)
	check(CrashReporter.lines.size() == CrashReporter.KEEP_LINES, "the ring is bounded")
	CrashReporter.log_line("y".repeat(2000))
	check(CrashReporter.lines[-1].length() == CrashReporter.MAX_TEXT, "long lines are cut")
	CrashReporter.reset()


func _test_reporter_fake() -> void:
	CrashReporter.reset()
	var fake := FakeCrashlytics.new()
	CrashReporter.backend = fake
	CrashReporter.init(false)
	check(fake.calls[0] == ["setCrashlyticsCollectionEnabled", false], "init passes the choice")
	CrashReporter.log_line("muted")
	CrashReporter.record_error("muted")
	check(fake.calls.size() == 1, "nothing is sent while reports are off")
	CrashReporter.set_enabled(true)
	check(fake.calls[-1] == ["setCrashlyticsCollectionEnabled", true], "switch on, no restart")
	CrashReporter.battle_started(4, "endless", 1, "")
	check(["log", "battle start: level 4 mode endless difficulty 1"] in fake.calls, "battle line")
	check(["setCustomKey", "level", "4"] in fake.calls, "level key")
	CrashReporter.record_error("exit")
	check(["recordException", "exit"] in fake.calls, "non-fatal goes through")
	var hashed: String = CrashReporter.hash_id("x")
	CrashReporter.set_user_id(hashed)
	check(["setUserId", hashed] in fake.calls, "user id goes through")
	fake.free()
	CrashReporter.reset()


func _test_settings() -> void:
	check(GameSettings.crash_reports(), "crash reports are on by default")
	GameSettings.set_crash_reports(false)
	check(not GameSettings.crash_reports(), "and can be turned off")
	GameSettings.set_crash_reports(true)
	check(GameSettings.crash_reports(), "and back on")
