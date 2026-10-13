class_name TowerData
extends Resource
## Buildable tower type: the single source of its name and price.

@export var display_name: String = ""
@export var cost: int = 50
## Scene instantiated on a slot; its root must use tower.gd.
@export var scene: PackedScene
