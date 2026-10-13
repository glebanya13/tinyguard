class_name LevelCatalog
extends RefCounted
## Level layouts and wave plans from resources/levels.json, plus saved progress.
## The selected level survives scene changes as a static variable.

const LEVELS_PATH := "res://resources/levels.json"
## Tests point this at a scratch file.
static var save_path: String = "user://progress.cfg"

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
	cfg.load(save_path)
	return int(cfg.get_value("progress", "unlocked", 1))


static func is_completed(id: int) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(save_path)
	return bool(cfg.get_value("progress", "won_%d" % id, false))


## Best result on a level: 0 (not won) .. 3 stars.
static func stars(id: int) -> int:
	var cfg := ConfigFile.new()
	cfg.load(save_path)
	var best: int = int(cfg.get_value("progress", "stars_%d" % id, 0))
	if best == 0 and bool(cfg.get_value("progress", "won_%d" % id, false)):
		best = 1  # saved before stars existed
	return best


## Stars for a win: 3 without losing lives, 2 with at least half left, else 1.
static func stars_for(lives_left: int, lives_start: int) -> int:
	if lives_left >= lives_start:
		return 3
	return 2 if lives_left * 2 >= lives_start else 1


static func complete(id: int, earned_stars: int = 1) -> void:
	var best: int = maxi(stars(id), earned_stars)
	var cfg := ConfigFile.new()
	cfg.load(save_path)
	cfg.set_value("progress", "won_%d" % id, true)
	cfg.set_value("progress", "stars_%d" % id, best)
	cfg.set_value("progress", "unlocked", maxi(unlocked(), mini(id + 1, levels().size())))
	cfg.save(save_path)
