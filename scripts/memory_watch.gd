class_name MemoryWatch
extends RefCounted
## Free memory of the phone and the memory of this process, read without any plugin.
## The system kills a game that eats too much (lowmemorykiller, aggressive on HyperOS/MIUI)
## without leaving a log, so the quality guard watches these numbers and lowers the
## picture before that happens, and the crash note keeps them for the next start.
## Order of sources: OS.get_memory_info() (if the platform fills it), then /proc/meminfo
## and /proc/self/status (readable by an Android app).

## Below this much available memory (MB) the guard takes a notch down.
const LOW_AVAILABLE_MB := 450
## Below this much it jumps to the last notch ("minimum") at once.
const CRITICAL_AVAILABLE_MB := 250
const MEMINFO_PATH := "/proc/meminfo"
const STATUS_PATH := "/proc/self/status"


## Value of "Key:   1234 kB" in a /proc text, in MB; -1 when absent.
static func parse_kb_line(text: String, key: String) -> int:
	for line in text.split("\n"):
		if line.begins_with(key + ":"):
			var digits: String = line.substr(key.length() + 1).strip_edges().get_slice(" ", 0)
			if digits.is_valid_int():
				@warning_ignore("integer_division")
				return int(digits) / 1024
	return -1


static func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


## Memory the system can still give out (MB); -1 when unknown.
static func available_mb() -> int:
	var info: Dictionary = OS.get_memory_info()
	for key in ["available", "free"]:
		var bytes: int = int(info.get(key, -1))
		if bytes > 0:
			@warning_ignore("integer_division")
			return bytes / 1048576
	var from_proc: int = parse_kb_line(_read(MEMINFO_PATH), "MemAvailable")
	return from_proc if from_proc >= 0 else parse_kb_line(_read(MEMINFO_PATH), "MemFree")


## Resident memory of this process (MB); -1 when unknown.
static func rss_mb() -> int:
	return parse_kb_line(_read(STATUS_PATH), "VmRSS")


## 0 = fine, 1 = low (one notch down), 2 = critical (straight to the last notch).
static func pressure(available: int) -> int:
	if available < 0:
		return 0
	if available < CRITICAL_AVAILABLE_MB:
		return 2
	return 1 if available < LOW_AVAILABLE_MB else 0
