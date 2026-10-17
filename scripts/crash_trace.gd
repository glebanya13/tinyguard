class_name CrashTrace
extends RefCounted
## A phone gives us no log, so the game leaves a note about itself: every few seconds of
## a battle it writes where it is (level, wave, enemies, memory, frame rate) to a tiny
## file, and says "map" or "closed" when it leaves in an orderly way. On the next start the
## note of the previous run is read back: "battle" means the process died while the player
## was in a battle (crash, out of memory in the foreground), "background" that it was gone
## after being sent to the background (the system killed it, or the player swiped it away).
## The diagnostics overlay shows it (see DiagOverlay, docs/DEBUG_ANDROID.md).

const PATH := "user://last_session.json"
## Seconds between two notes in a battle.
const INTERVAL := 5.0
## Last failed account request (what a tester sends to support): operation and server code.
const AUTH_PATH := "user://last_auth_error.json"
## States that mean "the run did not end in an orderly way".
const ABNORMAL: Array[String] = ["battle", "background"]

## Note left by the previous run; {} when there is none (first start, clean exit).
static var previous: Dictionary = {}
static var _read: bool = false


## Reads the previous note once per run (the first call).
static func read_previous() -> Dictionary:
	if _read:
		return previous
	_read = true
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary and str((parsed as Dictionary).get("state", "")) in ABNORMAL:
			previous = parsed
	return previous


## Short text for the overlay; "" when the previous run ended in an orderly way.
static func previous_text() -> String:
	var note: Dictionary = read_previous()
	if note.is_empty():
		return ""
	return (
		"prev run ended in %s: level %d wave %d enemies %d mem %d MB fps %d"
		% [
			note.get("state"),
			int(note.get("level", 0)),
			int(note.get("wave", 0)),
			int(note.get("enemies", 0)),
			int(note.get("mem_mb", 0)),
			int(note.get("fps", 0)),
		]
	)


## Writes the note. `state`: "battle", "background", "map" or "closed".
static func write(state: String, details: Dictionary = {}) -> void:
	read_previous()  # the old note must be read before it is overwritten
	var note: Dictionary = details.duplicate()
	note["state"] = state
	note["time"] = Time.get_unix_time_from_system()
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(note))


## Remembers the last failed account request: `op` ("link", "signup", ...) and the `detail`
## text of AuthErrors.detail (no address, password or token in it). One tiny file.
static func note_auth_error(op: String, detail: String) -> void:
	var note := {"op": op, "detail": detail, "time": Time.get_unix_time_from_system()}
	var file := FileAccess.open(AUTH_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(note))


## "last auth error: link HTTP 400 OPERATION_NOT_ALLOWED (3 min ago)" or "" when none.
static func last_auth_text() -> String:
	if not FileAccess.file_exists(AUTH_PATH):
		return ""
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUTH_PATH))
	if not parsed is Dictionary:
		return ""
	var note: Dictionary = parsed
	var ago: int = maxi(
		int((Time.get_unix_time_from_system() - float(note.get("time", 0))) / 60.0), 0
	)
	return (
		"last auth error: %s %s (%d min ago)" % [note.get("op", "?"), note.get("detail", "?"), ago]
	)
