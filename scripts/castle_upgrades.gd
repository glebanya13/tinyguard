class_name CastleUpgrades
extends RefCounted
## Castle upgrade table (resources/castle_upgrades.json): the price of every upgrade, the
## lives it adds and the armor the castle has after it. Pure data, no state: the level of
## the castle in a battle lives in GameState.

const PATH := "res://resources/castle_upgrades.json"

static var _rows: Array = []


## Rows [{"gold", "wood", "lives", "armor"}, ...], upgrade 1 first (cached).
static func rows() -> Array:
	if _rows.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary and (parsed as Dictionary).get("levels") is Array:
			_rows = (parsed as Dictionary)["levels"]
		else:
			push_error("CastleUpgrades: %s is missing or damaged" % PATH)
	return _rows


## How many upgrades there are (the castle level goes 0..max_level()).
static func max_level() -> int:
	return rows().size()


## Price of upgrading from `level` to `level + 1` as (gold, wood); (-1, -1) at the maximum.
static func cost(level: int) -> Vector2i:
	if level < 0 or level >= max_level():
		return Vector2i(-1, -1)
	var row: Dictionary = rows()[level]
	return Vector2i(int(row["gold"]), int(row["wood"]))


## Lives added by the upgrade from `level` to `level + 1`.
static func lives_bonus(level: int) -> int:
	if level < 0 or level >= max_level():
		return 0
	return int((rows()[level] as Dictionary)["lives"])


## Armor of a castle of `level` (0 for the plain castle).
static func armor_at(level: int) -> int:
	if level <= 0:
		return 0
	return int((rows()[mini(level, max_level()) - 1] as Dictionary)["armor"])


## Lives a leak of `damage` takes from a castle of `level` (never less than 1).
static func leak_damage(damage: int, level: int) -> int:
	return maxi(1, damage - armor_at(level))
