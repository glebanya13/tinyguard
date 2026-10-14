class_name Perks
extends RefCounted
## Stars and the permanent upgrades they buy. Stars come from the campaign
## (best 1-3 per level) and from endless siege records (1 per 10 waves, up to
## 5 per level). Bought levels are saved next to the progress.

## Loaded on first use, not preloaded: a preload in a constant runs while
## scripts typed with PerkData are still compiling and breaks the resources.
const PATHS := [
	"res://resources/perks/gold_start.tres",
	"res://resources/perks/wood_start.tres",
	"res://resources/perks/walls.tres",
	"res://resources/perks/sword.tres",
	"res://resources/perks/towers.tres",
	"res://resources/perks/axe.tres",
]
const ENDLESS_WAVES_PER_STAR := 10
const ENDLESS_MAX_STARS := 5

static var _list: Array[PerkData] = []


static func all() -> Array[PerkData]:
	if _list.is_empty():
		for path: String in PATHS:
			_list.append(load(path) as PerkData)
	return _list


static func get_perk(id: StringName) -> PerkData:
	for perk in all():
		if perk.id == id:
			return perk
	return null


static func level(id: StringName) -> int:
	return int(_cfg().get_value("perks", String(id), 0))


## Current effect of a perk (0 when not bought).
static func value(id: StringName) -> float:
	var perk: PerkData = get_perk(id)
	return perk.value_at(level(id)) if perk else 0.0


static func endless_stars(level_id: int) -> int:
	return mini(
		floori(LevelCatalog.endless_record(level_id) / float(ENDLESS_WAVES_PER_STAR)),
		ENDLESS_MAX_STARS
	)


static func earned_stars() -> int:
	var total: int = 0
	for lv: Dictionary in LevelCatalog.levels():
		total += LevelCatalog.stars(int(lv["id"])) + endless_stars(int(lv["id"]))
	return total


static func max_stars() -> int:
	return LevelCatalog.levels().size() * (3 + ENDLESS_MAX_STARS)


static func spent_stars() -> int:
	var total: int = 0
	for perk in all():
		for i in level(perk.id):
			total += perk.costs[i]
	return total


static func free_stars() -> int:
	return earned_stars() - spent_stars()


## Star price of the next level, or -1 at the top.
static func next_cost(perk: PerkData) -> int:
	var current: int = level(perk.id)
	return perk.costs[current] if current < perk.max_level() else -1


static func can_buy(perk: PerkData) -> bool:
	var cost: int = next_cost(perk)
	return cost >= 0 and cost <= free_stars()


static func any_affordable() -> bool:
	for perk in all():
		if can_buy(perk):
			return true
	return false


static func buy(perk: PerkData) -> bool:
	if not can_buy(perk):
		return false
	var cfg: ConfigFile = _cfg()
	cfg.set_value("perks", String(perk.id), level(perk.id) + 1)
	cfg.save(LevelCatalog.save_path)
	return true


## Returns every star spent on perks.
static func reset() -> void:
	var cfg: ConfigFile = _cfg()
	if cfg.has_section("perks"):
		cfg.erase_section("perks")
	cfg.save(LevelCatalog.save_path)


static func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(LevelCatalog.save_path)
	return cfg
