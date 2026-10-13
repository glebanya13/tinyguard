class_name TowerData
extends Resource
## Buildable tower type: name, prices and stats for every level (index 0 = level 1).

@export var display_name: String = ""
@export var cost: int = 50
## Scene instantiated on a slot; its root must use tower.gd.
@export var scene: PackedScene

@export_group("Levels")
## Price of each upgrade: [level 1 -> 2, level 2 -> 3].
@export var upgrade_costs: Array[int] = [60, 90]
@export var damage_levels: Array[float] = [12.0, 18.0, 26.0]
@export var range_levels: Array[float] = [3.0, 3.4, 3.8]
@export var interval_levels: Array[float] = [0.5, 0.45, 0.4]


func max_level() -> int:
	return damage_levels.size() - 1


## Cost to upgrade from `level` (0-based), or -1 when already at the top.
func upgrade_cost(level: int) -> int:
	return upgrade_costs[level] if level < upgrade_costs.size() else -1
