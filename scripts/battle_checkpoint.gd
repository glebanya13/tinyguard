class_name BattleCheckpoint
extends RefCounted
## Manages mid-level and endless battle checkpoints saved to user://battle_checkpoint.json.
## Enables players to leave lengthy battles and resume where they left: the running wave with
## its enemies (WaveManager.snapshot) and the felled trees with their regrow clocks.

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


## Trees that are not whole: [index in sim.trees, hits left, steps until regrown or -1].
static func tree_states(sim: Sim) -> Array:
	var out: Array = []
	for i in sim.trees.size():
		var tree: WoodTree = sim.trees[i]
		var regrow_at: int = tree.regrow_at()
		if tree.hits_left() < tree.hits or regrow_at >= 0:
			var regrow_in: int = maxi(regrow_at - sim.tick, 1) if regrow_at >= 0 else -1
			out.append([i, tree.hits_left(), regrow_in])
	return out


## Puts the trees of tree_states() back (the level plants them in the same order every time).
static func restore_trees(sim: Sim, states: Array) -> void:
	for item: Variant in states:
		var state: Array = item as Array
		if state.size() < 3:
			continue
		var index: int = int(state[0])
		if index >= 0 and index < sim.trees.size():
			sim.trees[index].restore_state(int(state[1]), int(state[2]))
