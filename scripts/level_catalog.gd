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
## Number of difficulty levels above Normal (Hard, Nightmare).
const MAX_DIFFICULTY := 2
const MAX_LEVEL := 6
## Tests point this at a scratch file.
static var save_path: String = "user://progress.cfg"

static var selected_id: int = 1
## True when the selected level is played as the Record Run (free mode without an end,
## every wave harder than the last; see WavePlan.record_run).
static var endless: bool = false
## Difficulty of the campaign battle that starts next: 0 Normal, 1 Hard, 2 Nightmare
## (rows of "difficulty" in resources/balance.json). The Record Run and the daily challenge
## ignore it.
static var difficulty: int = 0
## The map opens the records table of the selected level on arrival (set by the Record Run
## end screen), once.
static var open_records: bool = false
## True when the selected level is played as the onboarding tutorial.
static var tutorial: bool = false
## True when entering battle to resume from a saved battle checkpoint.
static var resume_checkpoint: bool = false
## The next battle opens with the map inspection (free camera, the knight and the battle clock
## wait for "To battle!"). Set by the screens that start a battle for the player (the map,
## restart, next level); read once by the battle. Tests that load the level directly leave it off.
static var inspect_map: bool = false
## Date ("yyyy-mm-dd") of the daily challenge being played, "" otherwise. Daily runs
## are endless sieges with the day's seed and modifiers (see DailyRun).
static var daily_key: String = ""
## Called after every successful commit (the Online autoload schedules a cloud sync).
static var on_committed: Callable = Callable()
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


## Highest difficulty above Normal a level was won on: 0 none, 1 Hard, 2 Nightmare
## (the "difficulty crown" next to the stars; it adds no stars).
static func crown(id: int) -> int:
	var cfg: ConfigFile = data()
	return clampi(int(cfg.get_value("progress", "crown_%d" % id, 0)), 0, MAX_DIFFICULTY)


## Hard opens once the level is won, Nightmare once it is won on Hard.
static func is_difficulty_open(id: int, level_difficulty: int) -> bool:
	if level_difficulty <= 0:
		return true
	return (
		is_completed(id)
		and crown(id) >= level_difficulty - 1
		and level_difficulty <= MAX_DIFFICULTY
	)


static func complete(id: int, earned_stars: int = 1, won_difficulty: int = 0) -> void:
	var best: int = maxi(stars(id), earned_stars)
	var cfg: ConfigFile = data()
	cfg.set_value("progress", "won_%d" % id, true)
	cfg.set_value("progress", "stars_%d" % id, best)
	if won_difficulty > 0:
		cfg.set_value(
			"progress", "crown_%d" % id, clampi(maxi(crown(id), won_difficulty), 0, MAX_DIFFICULTY)
		)
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


## The save file, loaded once and cached. A damaged file falls back to its .bak
## copy (the previous good state). If both are unreadable because of a parse error,
## the damaged file is kept aside as ".corrupt" and the game starts a fresh, writable
## save: progress made from now on is never lost to a file nobody can read. Any other
## read error (permissions, busy file) only makes the save read-only for this run.
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
			if error == ERR_PARSE_ERROR and _quarantine_damaged_save():
				_save_broken = false
			else:
				_save_broken = true
	return _save


## Writes the cached save atomically: temp file, read it back to be sure it parses,
## keep the previous good file as .bak, rename over the real one.
static func commit() -> void:
	if _save == null or _save_broken:
		return
	var tmp: String = save_path + ".tmp"
	if _save.save(tmp) != OK:
		push_error("Cannot write the save to %s" % tmp)
		return
	var verify := ConfigFile.new()
	if verify.load(tmp) != OK:
		push_error("The save written to %s does not parse, keeping the old file" % tmp)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return
	var real: String = ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path) and ConfigFile.new().load(save_path) == OK:
		DirAccess.copy_absolute(real, real + ".bak")  # only a good file becomes the backup
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), real) != OK:
		push_error("Cannot replace the save %s" % save_path)
		return
	if on_committed.is_valid():
		on_committed.call()


## Writes the save now (the app is going to the background or closing). Everything
## is committed at every change already; this is the belt-and-braces call.
static func flush() -> void:
	commit()


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


## Moves a save that cannot be parsed (and has no usable backup) aside, so a new one can
## be written. The old bytes stay in ".corrupt" for support.
static func _quarantine_damaged_save() -> bool:
	var real: String = ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path + ".corrupt"):
		DirAccess.remove_absolute(real + ".corrupt")
	return DirAccess.rename_absolute(real, real + ".corrupt") == OK


## Deletes the save (and its backup) and drops the cache: a fresh install.
## Used when the player deletes the account or the local data.
static func erase_all() -> void:
	for suffix in ["", ".bak", ".tmp", ".corrupt"]:
		if FileAccess.file_exists(save_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path + suffix))
	_save = null
	_save_loaded_from = ""
	_save_broken = false


## Coordinates of the thicket grove trees around outpost `lane` (up to 24 spots).
## If the level dictionary contains "outposts", reads from it; otherwise computes
## deterministic positions in an arc of radius 2.6..6.8m around the route entrance
## inside the hero walking bounds and clear of the roads and slots.
static func outpost_thickets(level: Dictionary, lane: int) -> Array[Vector2]:
	var custom_outposts: Array = level.get("outposts", [])
	for entry: Variant in custom_outposts:
		if entry is Dictionary and int((entry as Dictionary).get("lane", -1)) == lane:
			var list: Array[Vector2] = []
			for pt: Variant in (entry as Dictionary).get("thicket", []):
				if pt is Array and (pt as Array).size() >= 2:
					list.append(Vector2(float((pt as Array)[0]), float((pt as Array)[1])))
			return list

	var all_routes: Array[PackedVector2Array] = routes(level)
	if lane < 0 or lane >= all_routes.size():
		return []
	var route: PackedVector2Array = all_routes[lane]
	if route.size() < 2:
		return []

	var start: Vector2 = route[0]
	var hero_rect := Rect2(-21.0, -13.8, 42.0, 27.6)
	var slots: Array = level.get("slots", [])
	var trees: Array = level.get("trees", [])

	var spots: Array[Vector2] = []
	var radii: Array[float] = [2.6, 3.2, 3.8, 4.4, 5.0, 5.6, 6.2, 6.8]
	for r in radii:
		for a_deg in range(-180, 180, 8):
			if spots.size() >= 24:
				break
			var rad: float = deg_to_rad(float(a_deg))
			var pt := Vector2(start.x + r * cos(rad), start.y + r * sin(rad))
			if not hero_rect.has_point(pt):
				continue
			var too_close_to_road := false
			for rt: PackedVector2Array in all_routes:
				for s_idx in rt.size() - 1:
					if (
						(
							Geometry2D
							. get_closest_point_to_segment(pt, rt[s_idx], rt[s_idx + 1])
							. distance_to(pt)
						)
						< 1.3
					):
						too_close_to_road = true
						break
				if too_close_to_road:
					break
			if too_close_to_road:
				continue
			var too_close_slot := false
			for s in slots:
				if pt.distance_to(Vector2(float(s[0]), float(s[1]))) < 1.4:
					too_close_slot = true
					break
			if too_close_slot:
				continue
			var too_close_tree := false
			for t in trees:
				if pt.distance_to(Vector2(float(t[0]), float(t[1]))) < 1.2:
					too_close_tree = true
					break
			if too_close_tree:
				continue
			var too_close_thicket := false
			for existing in spots:
				if pt.distance_to(existing) < 0.7:
					too_close_thicket = true
					break
			if too_close_thicket:
				continue
			spots.append(Vector2(snappedf(pt.x, 0.01), snappedf(pt.y, 0.01)))
		if spots.size() >= 24:
			break
	return spots
