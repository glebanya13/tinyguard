class_name LevelCatalog
extends RefCounted
## Level layouts and wave plans from resources/levels.json, plus saved progress
## (stars per level) and the sound setting.
## The selected level survives scene changes as a static variable.

const LEVELS_PATH := "res://resources/levels.json"
## A path's last point counts as lying on another path this close to it (metres).
const JOIN_TOLERANCE := 0.01
## Tests point this at a scratch file.
static var save_path: String = "user://progress.cfg"

static var selected_id: int = 1
## True when the selected level is played as an endless siege.
static var endless: bool = false
static var _levels: Array = []
static var _save: ConfigFile = null
static var _save_loaded_from: String = ""
## Set when the save exists but cannot be parsed: never overwrite it then.
static var _save_broken: bool = false


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


## Full enemy routes of a level (X/Z points), one per entry of level["paths"]:
## path 0 runs to the castle; every other path ends on a segment of an earlier
## one and its route goes on along that one (see tools/validate_project.py).
static func routes(level: Dictionary) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for points: Array in level["paths"]:
		var route := PackedVector2Array()
		for point: Array in points:
			route.append(Vector2(float(point[0]), float(point[1])))
		if not out.is_empty():
			route.append_array(_route_after(out, route[route.size() - 1]))
		out.append(route)
	return out


## Highest level id the player may start (1 = only the first).
static func unlocked() -> int:
	var cfg: ConfigFile = data()
	return int(cfg.get_value("progress", "unlocked", 1))


static func is_completed(id: int) -> bool:
	var cfg: ConfigFile = data()
	return bool(cfg.get_value("progress", "won_%d" % id, false))


## Best result on a level: 0 (not won) .. 3 stars.
static func stars(id: int) -> int:
	var cfg: ConfigFile = data()
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
	var cfg: ConfigFile = data()
	cfg.set_value("progress", "won_%d" % id, true)
	cfg.set_value("progress", "stars_%d" % id, best)
	cfg.set_value("progress", "unlocked", maxi(unlocked(), mini(id + 1, levels().size())))
	commit()


static func sound_on() -> bool:
	var cfg: ConfigFile = data()
	return bool(cfg.get_value("settings", "sound", true))


## Mutes or unmutes the master bus and remembers the choice.
static func set_sound_on(on: bool) -> void:
	var cfg: ConfigFile = data()
	cfg.set_value("settings", "sound", on)
	commit()
	apply_sound()


static func apply_sound() -> void:
	AudioServer.set_bus_mute(0, not sound_on())


## Best wave survived in the endless siege of a level (0 = never played).
static func endless_record(id: int) -> int:
	var cfg: ConfigFile = data()
	return int(cfg.get_value("progress", "endless_%d" % id, 0))


## Saves `wave` if it beats the record; returns true for a new record.
static func save_endless(id: int, wave: int) -> bool:
	if wave <= endless_record(id):
		return false
	var cfg: ConfigFile = data()
	cfg.set_value("progress", "endless_%d" % id, wave)
	commit()
	return true


## The save file, loaded once and cached. A corrupt file falls back to its
## .bak copy; if both fail the game runs on defaults and never writes.
static func data() -> ConfigFile:
	if _save != null and _save_loaded_from == save_path:
		return _save
	_save = ConfigFile.new()
	_save_loaded_from = save_path
	_save_broken = false
	var error: Error = _save.load(save_path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_error("Save %s is damaged (%s), trying the backup" % [save_path, error_string(error)])
		_save = ConfigFile.new()
		if _save.load(save_path + ".bak") != OK:
			_save = ConfigFile.new()
			_save_broken = true
	return _save


## Writes the cached save atomically: temp file, keep the old one as .bak, rename.
static func commit() -> void:
	if _save == null or _save_broken:
		return
	var tmp: String = save_path + ".tmp"
	if _save.save(tmp) != OK:
		push_error("Cannot write the save to %s" % tmp)
		return
	var real: String = ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(real, real + ".bak")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), real)


## Replaces the whole progress with a saved text (cloud restore). False if the
## text does not parse; the current progress is kept then.
static func replace_with(text: String) -> bool:
	var incoming := ConfigFile.new()
	if incoming.parse(text) != OK:
		return false
	data()
	_save = incoming
	_save_broken = false
	commit()
	return true


## Points of the first route in `routes` that passes through `join`, after it.
static func _route_after(routes: Array[PackedVector2Array], join: Vector2) -> PackedVector2Array:
	for route in routes:
		for i in route.size() - 1:
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
				join, route[i], route[i + 1]
			)
			if closest.distance_to(join) < JOIN_TOLERANCE:
				return route.slice(i + 1)
	push_error("LevelCatalog: path ending at %s does not join another path" % join)
	return PackedVector2Array()
