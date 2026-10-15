class_name Achievements
extends RefCounted
## Achievements: data in resources/achievements.json (id, translation key, metric,
## threshold, bit). The logic is pure: evaluate() compares the player's metrics with
## the thresholds and answers which achievements are newly earned. Metrics come from
## the save file (campaign, records, daily book, counters in the [stats] section); the
## unlocked set is a bit mask kept in the player profile, so it syncs with the cloud
## profile (PlayerProfile "achievements"). Nothing here touches the UI.

const DATA_PATH := "res://resources/achievements.json"
const STATS_SECTION := "stats"
## Counters kept in [stats] (local to the device; the unlocked mask is what syncs).
const COUNTERS: Array[String] = [
	"kills_total", "towers_built_total", "upgrades_total", "wood_total"
]
## Everything a threshold can be measured in.
const METRICS: Array[String] = [
	"levels_won",
	"three_star_levels",
	"stars_total",
	"best_endless",
	"kills_total",
	"towers_built_total",
	"upgrades_total",
	"wood_total",
	"daily_played",
	"daily_streak_best",
	"daily_best_wave",
	"perks_bought",
]
## Most bits of the cloud mask (it is one integer, see firestore.rules).
const MAX_BITS := 31

static var _defs: Array[Dictionary] = []


static func all() -> Array[Dictionary]:
	if _defs.is_empty():
		var json: JSON = load(DATA_PATH)
		for def: Dictionary in json.data["achievements"]:
			_defs.append(def)
	return _defs


static func get_def(id: String) -> Dictionary:
	for def in all():
		if str(def["id"]) == id:
			return def
	return {}


## Mask with the bit of every known achievement.
static func known_mask() -> int:
	var mask: int = 0
	for def in all():
		mask |= 1 << int(def["bit"])
	return mask


static func mask_has(mask: int, def: Dictionary) -> bool:
	return (mask >> int(def["bit"])) & 1 == 1


## Pure: achievements of `defs` whose metric reaches the threshold and that are not in
## `mask` yet, in the order of `defs`.
static func evaluate(defs: Array[Dictionary], metrics: Dictionary, mask: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in defs:
		if mask_has(mask, def):
			continue
		if int(metrics.get(str(def["metric"]), 0)) >= int(def["threshold"]):
			out.append(def)
	return out


## Current value of the metric of `def` (0 when unknown).
static func progress(def: Dictionary, metrics: Dictionary) -> int:
	return mini(int(metrics.get(str(def["metric"]), 0)), int(def["threshold"]))


## Unlocked set of this device (profile mask).
static func unlocked_mask() -> int:
	return int(LevelCatalog.data().get_value(PlayerProfile.SECTION, "achievements", 0))


static func is_unlocked(id: String) -> bool:
	var def: Dictionary = get_def(id)
	return not def.is_empty() and mask_has(unlocked_mask(), def)


static func unlocked_count() -> int:
	var count: int = 0
	var mask: int = unlocked_mask()
	for def in all():
		if mask_has(mask, def):
			count += 1
	return count


## All metrics now, from the save file.
static func metrics() -> Dictionary:
	var cfg: ConfigFile = LevelCatalog.data()
	var out: Dictionary = {}
	var won: int = 0
	var perfect: int = 0
	var best_endless: int = 0
	for level: Dictionary in LevelCatalog.levels():
		var id: int = int(level["id"])
		if LevelCatalog.is_completed(id):
			won += 1
		if LevelCatalog.stars(id) >= 3:
			perfect += 1
		best_endless = maxi(best_endless, LevelCatalog.endless_record(id))
	out["levels_won"] = won
	out["three_star_levels"] = perfect
	out["best_endless"] = best_endless
	out["stars_total"] = Perks.earned_stars()
	for name in COUNTERS:
		out[name] = int(cfg.get_value(STATS_SECTION, name, 0))
	out["daily_played"] = Daily.days_played()
	out["daily_streak_best"] = Daily.best_streak()
	out["daily_best_wave"] = Daily.best_wave_ever()
	var bought: int = 0
	for perk in Perks.all():
		bought += Perks.level(perk.id)
	out["perks_bought"] = bought
	return out


## Adds to a counter (not written to disk until LevelCatalog.commit()).
static func add_stat(name: String, amount: int = 1) -> void:
	if not name in COUNTERS or amount <= 0:
		return
	var cfg: ConfigFile = LevelCatalog.data()
	cfg.set_value(STATS_SECTION, name, int(cfg.get_value(STATS_SECTION, name, 0)) + amount)


## Unlocks what the current metrics earn and saves the profile. Returns the newly
## unlocked definitions (empty most of the time).
static func check() -> Array[Dictionary]:
	var fresh: Array[Dictionary] = evaluate(all(), metrics(), unlocked_mask())
	if fresh.is_empty():
		return fresh
	var profile: Dictionary = PlayerProfile.local()
	var mask: int = int(profile["achievements"])
	for def in fresh:
		mask |= 1 << int(def["bit"])
	profile["achievements"] = mask
	PlayerProfile.save_local(profile)
	return fresh
