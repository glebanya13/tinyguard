class_name PerkData
extends Resource
## Permanent upgrade bought with stars on the map ("Королевская казна").
## `values[i]` is the total effect after buying level i + 1.

@export var id: StringName = &""
@export var display_name: String = ""
## Shown with the current and next value, e.g. "Стартовое золото: +%d".
@export var description: String = ""
@export var icon: Texture2D
## Star price of each level.
@export var costs: Array[int] = [1]
@export var values: Array[float] = [1.0]
## Format of a value in the description: "+%d", "+%d%%"...
@export var value_format: String = "+%d"
## Values are shown multiplied by this (0.2 -> 20 for percentages).
@export var display_scale: float = 1.0


func max_level() -> int:
	return costs.size()


## Effect at `level` (0 = not bought).
func value_at(level: int) -> float:
	return 0.0 if level <= 0 else values[mini(level, values.size()) - 1]


func format_value(level: int) -> String:
	return value_format % roundi(value_at(level) * display_scale)
