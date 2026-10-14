class_name CommandLog
extends RefCounted
## Journal of a battle: a header (level, seed, versions) and every applied
## GameCommand in order. Recording one run and feeding it back to a fresh run
## of the same level reproduces the battle exactly (see Sim.begin_replay).

var header: Dictionary = {}
var commands: Array[GameCommand] = []


func add(cmd: GameCommand) -> void:
	commands.append(cmd)


func to_json() -> String:
	var rows: Array = []
	for cmd in commands:
		rows.append(cmd.to_array())
	return JSON.stringify({"header": header, "commands": rows})


static func from_json(text: String) -> CommandLog:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return null
	var journal := CommandLog.new()
	var header: Dictionary = (parsed as Dictionary).get("header", {})
	for key: Variant in header:
		# JSON has one number type: whole numbers come back as floats.
		if header[key] is float and is_equal_approx(header[key], roundf(header[key])):
			header[key] = int(header[key])
	journal.header = header
	for row: Variant in (parsed as Dictionary).get("commands", []):
		journal.commands.append(GameCommand.from_array(row as Array))
	return journal


func save(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(to_json())
	return OK


static func load_file(path: String) -> CommandLog:
	if not FileAccess.file_exists(path):
		return null
	return from_json(FileAccess.get_file_as_string(path))
