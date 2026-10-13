class_name LevelCatalog
extends RefCounted
## Level layouts and wave plans from resources/levels.json, plus saved progress.
## The selected level survives scene changes as a static variable.

const LEVELS_PATH := "res://resources/levels.json"
const SAVE_PATH := "user://progress.cfg"

static var selected_id: int = 1
static var _levels: Array = []


static func levels() -> Array:
	if _levels.is_empty():
		var json: JSON = load(LEVELS_PATH)
		_levels = json.data["levels"]
	return _levels


static func get_level(id: int) -> Dictionary:
	for level: Dictionary in levels():
		if int(level["id"]) == id:
			return level
	return levels()[0]


## Highest level id the player may start (1 = only the first).
static func unlocked() -> int:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	return int(cfg.get_value("progress", "unlocked", 1))


static func is_completed(id: int) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	return bool(cfg.get_value("progress", "won_%d" % id, false))


static func complete(id: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("progress", "won_%d" % id, true)
	cfg.set_value("progress", "unlocked", maxi(unlocked(), mini(id + 1, levels().size())))
	cfg.save(SAVE_PATH)
