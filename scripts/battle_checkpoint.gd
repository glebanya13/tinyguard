class_name BattleCheckpoint
extends RefCounted
## Manages mid-level and endless battle checkpoints saved to user://battle_checkpoint.json.
## Enables players to leave lengthy battles and resume from the latest cleared wave.

const SAVE_PATH := "user://battle_checkpoint.json"
const TMP_PATH := "user://battle_checkpoint.json.tmp"


## Saves battle state atomically to user://battle_checkpoint.json.
static func save_checkpoint(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	var text: String = JSON.stringify(data, "  ")
	var tmp := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if tmp == null:
		return false
	tmp.store_string(text)
	tmp.close()

	var real_path: String = ProjectSettings.globalize_path(SAVE_PATH)
	var tmp_path: String = ProjectSettings.globalize_path(TMP_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(real_path)
	return DirAccess.rename_absolute(tmp_path, real_path) == OK


## Loads the battle checkpoint dictionary, or an empty dictionary if missing/invalid.
static func load_checkpoint() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {}
	return parsed as Dictionary


## Returns true if a valid checkpoint exists for `level_id`.
static func has_checkpoint(level_id: Variant = null) -> bool:
	var cp := load_checkpoint()
	if cp.is_empty():
		return false
	if level_id != null:
		var cp_id = cp.get("level_id", null)
		if cp_id == null or int(cp_id) != int(level_id):
			return false
	return true


## Clears the saved battle checkpoint.
static func clear_checkpoint() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if FileAccess.file_exists(TMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))
