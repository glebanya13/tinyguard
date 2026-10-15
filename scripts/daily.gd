class_name Daily
extends RefCounted
## The daily challenge ("Испытание дня"): one level and one preset of modifiers
## per UTC day, both computed from the date alone (so every player gets the same
## trial, offline too), and the local record book (best wave and time per day,
## streak of days in a row, the bonus stars). Data: resources/daily_modifiers.json.
## Everything here is pure or works on the save file; the battle wiring is in
## DailyRun. See docs/GAME_DESIGN.md ("Испытание дня").

const DATA_PATH := "res://resources/daily_modifiers.json"
## Save section (user://progress.cfg).
const SECTION := "daily"
## Days of results kept in the save.
const KEEP_DAYS := 40
const SECONDS_PER_DAY := 86400
## FNV-1a 32-bit.
const FNV_BASIS := 2166136261
const FNV_PRIME := 16777619

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var json: JSON = load(DATA_PATH)
		_data = json.data
	return _data


## UTC date "yyyy-mm-dd" of a unix time.
static func key_for(unix: int) -> String:
	var d: Dictionary = Time.get_date_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


static func today_key() -> String:
	return key_for(int(Time.get_unix_time_from_system()))


static func is_valid_key(key: String) -> bool:
	var parts: PackedStringArray = key.split("-")
	if parts.size() != 3 or parts[0].length() != 4 or parts[1].length() != 2:
		return false
	if parts[2].length() != 2 or not (parts[0] + parts[1] + parts[2]).is_valid_int():
		return false
	var year: int = int(parts[0])
	var month: int = int(parts[1])
	if year < 1970 or month < 1 or month > 12:
		return false
	var leap: bool = year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
	var days: int = [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
	return int(parts[2]) >= 1 and int(parts[2]) <= days


## Days since 1970-01-01 of a valid key (-1 for a bad one).
static func day_index(key: String) -> int:
	if not is_valid_key(key):
		return -1
	var parts: PackedStringArray = key.split("-")
	var d: Dictionary = {"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2])}
	@warning_ignore("integer_division")
	return int(Time.get_unix_time_from_datetime_dict(d)) / SECONDS_PER_DAY


static func key_of_day(index: int) -> String:
	return key_for(index * SECONDS_PER_DAY)


static func yesterday_key(key: String) -> String:
	return key_of_day(day_index(key) - 1)


## FNV-1a 32-bit of a text.
static func fnv1a(text: String) -> int:
	var h: int = FNV_BASIS
	for byte in text.to_utf8_buffer():
		h = ((h ^ byte) * FNV_PRIME) & 0xFFFFFFFF
	return h


## Stable 32-bit hash of a text (the same on every platform): FNV-1a followed by the
## murmur3 finalizer, so neighbouring dates do not give neighbouring numbers.
static func hash_text(text: String) -> int:
	var h: int = fnv1a(text)
	h = ((h ^ (h >> 16)) * 0x85EBCA6B) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 0xC2B2AE35) & 0xFFFFFFFF
	return h ^ (h >> 16)


## Level of the day (one of data()["levels"]).
static func level_for(key: String) -> int:
	var levels: Array = data()["levels"]
	return int(levels[hash_text("level:" + key) % levels.size()])


## Battle seed of the day (positive, fits 31 bits).
static func seed_for(key: String) -> int:
	return hash_text("seed:" + key) & 0x7FFFFFFF


## Preset of the day: {id, key, towers, hp_mult, reward_mult, wave_duration_mult}.
static func preset_for(key: String) -> Dictionary:
	var presets: Array = data()["presets"]
	return presets[posmod(day_index(key), presets.size())]


## Waves needed in one run for the day's bonus star.
static func star_wave() -> int:
	return int(data()["reward"]["star_wave"])


static func max_stars() -> int:
	return int(data()["reward"]["max_stars"])


# --- Record book (the save file) ---


static func best_wave(key: String) -> int:
	return int(LevelCatalog.data().get_value(SECTION, "wave_" + key, 0))


static func best_time(key: String) -> int:
	return int(LevelCatalog.data().get_value(SECTION, "time_" + key, 0))


## Bonus stars earned so far (counted by Perks next to the campaign stars).
static func bonus_stars() -> int:
	var stars: int = int(LevelCatalog.data().get_value(SECTION, "bonus_stars", 0))
	return clampi(stars, 0, max_stars())


static func streak() -> int:
	return int(LevelCatalog.data().get_value(SECTION, "streak", 0))


static func best_streak() -> int:
	return int(LevelCatalog.data().get_value(SECTION, "streak_best", 0))


## Days with a finished run, ever.
static func days_played() -> int:
	return int(LevelCatalog.data().get_value(SECTION, "played", 0))


static func best_wave_ever() -> int:
	return int(LevelCatalog.data().get_value(SECTION, "wave_best", 0))


## Streak as shown on `today`: it is still alive when the last day played is today or
## yesterday, otherwise it has run out (0).
static func live_streak(today: String) -> int:
	var last: String = str(LevelCatalog.data().get_value(SECTION, "last_day", ""))
	if last == today or last == yesterday_key(today):
		return streak()
	return 0


## Records the result of a finished run of day `key`: best wave and time, the streak
## (a day counts when at least one wave was survived), the bonus star (once per day,
## when the run reaches star_wave, at most max_stars in all) and the lifetime
## counters. Returns {"new_best", "streak", "star", "wave", "time"}.
static func record_result(key: String, wave: int, seconds: int) -> Dictionary:
	var cfg: ConfigFile = LevelCatalog.data()
	var out := {"new_best": false, "streak": streak(), "star": false, "wave": wave, "time": seconds}
	if not is_valid_key(key) or wave < 1:
		return out
	var old: int = best_wave(key)
	if wave > old or (wave == old and seconds < best_time(key)):
		out["new_best"] = wave > old
		cfg.set_value(SECTION, "wave_" + key, wave)
		cfg.set_value(SECTION, "time_" + key, seconds)
	if wave > old and old < star_wave() and wave >= star_wave() and bonus_stars() < max_stars():
		cfg.set_value(SECTION, "bonus_stars", bonus_stars() + 1)
		out["star"] = true
	var last: String = str(cfg.get_value(SECTION, "last_day", ""))
	if last != key:
		var next: int = streak() + 1 if last == yesterday_key(key) else 1
		cfg.set_value(SECTION, "streak", next)
		cfg.set_value(SECTION, "streak_best", maxi(best_streak(), next))
		cfg.set_value(SECTION, "last_day", key)
		cfg.set_value(SECTION, "played", days_played() + 1)
		out["streak"] = next
	cfg.set_value(SECTION, "wave_best", maxi(best_wave_ever(), wave))
	_prune(cfg, key)
	LevelCatalog.commit()
	return out


## Drops the per-day entries older than KEEP_DAYS.
static func _prune(cfg: ConfigFile, today: String) -> void:
	var limit: int = day_index(today) - KEEP_DAYS
	for name: String in cfg.get_section_keys(SECTION):
		for prefix in ["wave_", "time_"]:
			if name.begins_with(prefix) and name != "wave_best":
				var day: int = day_index(name.trim_prefix(prefix))
				if day >= 0 and day < limit:
					cfg.erase_section_key(SECTION, name)
