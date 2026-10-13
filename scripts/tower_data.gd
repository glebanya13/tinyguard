class_name TowerData
extends Resource
## Buildable tower type: name, icon, prices (gold + wood) and stats per level
## (index 0 = level 1).

## Share of everything spent on a tower that selling it returns.
const SELL_REFUND := 0.7

@export var display_name: String = ""
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
