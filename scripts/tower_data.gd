class_name TowerData
extends Resource
## Buildable tower type: name, icon, prices (gold + wood) and stats per level
## (index 0 = level 1).

## Which enemy in range a tower shoots at; the player switches it per tower.
enum Priority { FIRST, LAST, STRONGEST, NEAREST }

## Translation keys of the Priority values (label and one-line meaning).
const PRIORITY_KEYS: Array[String] = [
	"PRIORITY_FIRST", "PRIORITY_LAST", "PRIORITY_STRONGEST", "PRIORITY_NEAREST"
]
const PRIORITY_HINT_KEYS: Array[String] = [
	"PRIORITY_FIRST_HINT",
	"PRIORITY_LAST_HINT",
	"PRIORITY_STRONGEST_HINT",
	"PRIORITY_NEAREST_HINT",
]
## Share of everything spent on a tower that selling it returns.
const SELL_REFUND := 0.7

@export var display_name: String = ""
## One-line role for the build menu ("fast, single target").
@export var role: String = ""
@export var icon: Texture2D
## Scene instantiated on a slot; its root must use tower.gd.
@export var scene: PackedScene
@export var cost_gold: int = 20
@export var cost_wood: int = 15

@export_group("Levels")
## Upgrade prices: [level 1 -> 2, level 2 -> 3].
@export var upgrade_gold: Array[int] = [35, 60]
@export var upgrade_wood: Array[int] = [20, 35]
@export var damage_levels: Array[float] = [9.0, 15.0, 24.0]
@export var range_levels: Array[float] = [3.2, 3.6, 4.0]
@export var interval_levels: Array[float] = [0.6, 0.5, 0.42]
## Splash radius in metres (0 = single target).
@export var splash_levels: Array[float] = [0.0, 0.0, 0.0]
## Speed multiplier applied to hit enemies (1 = no slow).
@export var slow_levels: Array[float] = [1.0, 1.0, 1.0]
@export var slow_duration: float = 1.6
## Extra enemies a lightning bolt jumps to (0 = normal projectile).
@export var chain_levels: Array[int] = [0, 0, 0]
## Max jump distance of a chain bolt (metres).
@export var chain_range: float = 2.2
## Damage type passed to enemies: &"arrow" is weak against shields.
@export var damage_kind: StringName = &""
## Who the tower shoots first unless the player changes it.
@export var default_priority: Priority = Priority.FIRST
## Damage multiplier against enemies slowed by frost (the shock of a chilled
## enemy hurts more); 1 = no bonus.
@export var chilled_bonus: float = 1.0
## False for cannons: their shells cannot hit flying enemies.
@export var hits_air: bool = true


## Gold and wood spent on a tower of `level` (build + upgrades).
func total_cost(level: int) -> Vector2i:
	var total := Vector2i(cost_gold, cost_wood)
	for i in mini(level, upgrade_gold.size()):
		total += Vector2i(upgrade_gold[i], upgrade_wood[i])
	return total


## What selling a tower of `level` gives back.
func sell_value(level: int) -> Vector2i:
	var total: Vector2i = total_cost(level)
	return Vector2i(floori(total.x * SELL_REFUND), floori(total.y * SELL_REFUND))


func max_level() -> int:
	return damage_levels.size() - 1


## Upgrade price from `level` (0-based) as Vector2i(gold, wood), or (-1, -1) at the top.
func upgrade_cost(level: int) -> Vector2i:
	if level >= upgrade_gold.size():
		return Vector2i(-1, -1)
	return Vector2i(upgrade_gold[level], upgrade_wood[level])


## Label of the target-priority button.
static func priority_name(priority: int) -> String:
	return TranslationServer.translate(PRIORITY_KEYS[priority])


## Tooltip of the target-priority button.
static func priority_tooltip(priority: int) -> String:
	var hint: String = TranslationServer.translate(PRIORITY_HINT_KEYS[priority])
	return TranslationServer.translate("PRIORITY_TIP") % [priority_name(priority), hint]


## One-line stats of `level_index` for the command card.
func stats_text(level_index: int) -> String:
	var text: String = (
		TranslationServer.translate("TOWER_STATS")
		% [damage_levels[level_index], range_levels[level_index], interval_levels[level_index]]
	)
	if splash_levels[level_index] > 0.0:
		text += TranslationServer.translate("TOWER_STATS_SPLASH") % splash_levels[level_index]
	if slow_levels[level_index] < 1.0:
		var percent: int = roundi((1.0 - slow_levels[level_index]) * 100.0)
		text += TranslationServer.translate("TOWER_STATS_SLOW") % percent
	return text
