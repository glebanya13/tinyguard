class_name LevelCatalog
extends RefCounted
## Level layouts and wave plans from resources/levels.json, plus saved progress
## (stars per level) and the sound setting.
## The selected level survives scene changes as a static variable.

const LEVELS_PATH := "res://resources/levels.json"
## A path's last point counts as lying on another path this close to it (metres).
const JOIN_TOLERANCE := 0.01
## A path whose last point is this close to the castle (taxicab metres) ends at one of
## its gates. Every level has four such paths, one on each side of the castle.
const GATE_REACH := 1.5
## Translation keys of the 8 screen directions, clockwise from the top.
const DIRECTION_KEYS: Array[String] = [
	"DIR_N", "DIR_NE", "DIR_E", "DIR_SE", "DIR_S", "DIR_SW", "DIR_W", "DIR_NW"
]
## Screen "up" and "right" on the ground plane (X, Z): the camera of main.tscn
## looks along (-1, -1, -1), so the top of the screen is the world's (-X, -Z) corner.
const SCREEN_UP := Vector2(-0.7071068, -0.7071068)
const SCREEN_RIGHT := Vector2(0.7071068, -0.7071068)
## Tests point this at a scratch file.
static var save_path: String = "user://progress.cfg"

static var selected_id: int = 1
## True when the selected level is played as an endless siege.
static var endless: bool = false
## True when the selected level is played as the onboarding tutorial.
static var tutorial: bool = false
## Date ("yyyy-mm-dd") of the daily challenge being played, "" otherwise. Daily runs
## are endless sieges with the day's seed and modifiers (see DailyRun).
static var daily_key: String = ""
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
## the first four paths run to the castle gates (one from each side of the castle);
## every other path ends on a segment of an earlier one and its route goes on along
## that one (see tools/validate_project.py).
static func routes(level: Dictionary) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var castle := Vector2(float(level["castle"][0]), float(level["castle"][1]))
	for points: Array in level["paths"]:
		var route := PackedVector2Array()
		for point: Array in points:
			route.append(Vector2(float(point[0]), float(point[1])))
		if not is_gate(route[route.size() - 1], castle):
			route.append_array(_route_after(out, route[route.size() - 1]))
		out.append(route)
	return out


## True if `point` is at a castle gate (the end of a path that reaches the castle).
static func is_gate(point: Vector2, castle: Vector2) -> bool:
	return absf(point.x - castle.x) + absf(point.y - castle.y) <= GATE_REACH


## Straight flight lines of the flying enemies, one per entry of level["paths"]:
## from the portal over the ground to the castle gate its route ends at, so flyers
## too come from every side.
static func air_routes(level: Dictionary) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for route: PackedVector2Array in routes(level):
		out.append(PackedVector2Array([route[0], route[route.size() - 1]]))
	return out


## Where on the screen a point (relative to the castle) is seen: 0..7 clockwise from
## the top (index into DIRECTION_KEYS).
static func screen_direction(point: Vector2) -> int:
	var angle: float = atan2(point.dot(SCREEN_RIGHT), point.dot(SCREEN_UP))
	return posmod(roundi(angle / (PI / 4.0)), 8)


## "From the north and west!" for the paths a wave uses; "From every side!" for all.
static func direction_text(level: Dictionary, lanes: Array) -> String:
	var paths: Array = level["paths"]
	if lanes.size() >= paths.size() and paths.size() > 1:
		return TranslationServer.translate("LANES_ALL")
	var names: Array[String] = []
	for lane: int in lanes:
		var start: Array = paths[lane][0]
		var castle: Array = level["castle"]
		var from := Vector2(float(start[0]) - float(castle[0]), float(start[1]) - float(castle[1]))
		var side: String = TranslationServer.translate(DIRECTION_KEYS[screen_direction(from)])
		if not names.has(side):
			names.append(side)
	if names.is_empty():
		return ""
	var last: String = names.pop_back()
	if names.is_empty():
		return TranslationServer.translate("LANES_FROM") % last
	return TranslationServer.translate("LANES_FROM_TWO") % [", ".join(names), last]


## "30 seconds" / "30 секунд"; Russian has three plural forms, English two.
static func seconds_text(seconds: float) -> String:
	var n: int = roundi(seconds)
	var key: String = "TIME_SECONDS_MANY"
	if TranslationServer.get_locale().begins_with("ru"):
		if n % 10 == 1 and n % 100 != 11:
			key = "TIME_SECONDS_ONE"
		elif n % 10 in [2, 3, 4] and not (n % 100 in [12, 13, 14]):
			key = "TIME_SECONDS_FEW"
	elif n == 1:
		key = "TIME_SECONDS_ONE"
	return TranslationServer.translate(key) % n


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


## Deletes the save (and its backup) and drops the cache: a fresh install.
## Used when the player deletes the account or the local data.
static func erase_all() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	_save = null
	_save_loaded_from = ""
	_save_broken = false
