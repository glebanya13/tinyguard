class_name GameState
extends Node
## Gold, wood and lives of the current level. Emits signals on every change.

signal gold_changed(gold: int)
signal wood_changed(wood: int)
signal lives_changed(lives: int)
signal defeated

@export var starting_gold: int = 0
@export var starting_wood: int = 0
@export var starting_lives: int = 20

var gold: int = 0
var wood: int = 0
var lives: int = 0
var is_defeated: bool = false


func _ready() -> void:
	reset()


## Starting values from a level's "start" block.
func configure(start: Dictionary) -> void:
	starting_gold = int(start.get("gold", starting_gold))
	starting_wood = int(start.get("wood", starting_wood))
	starting_lives = int(start.get("lives", starting_lives))


func reset() -> void:
	gold = starting_gold
	wood = starting_wood
	lives = starting_lives
	is_defeated = false
	gold_changed.emit(gold)
	wood_changed.emit(wood)
	lives_changed.emit(lives)


func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


func add_wood(amount: int) -> void:
	wood += amount
	wood_changed.emit(wood)


func can_afford(cost: Vector2i) -> bool:
	return cost.x >= 0 and cost.x <= gold and cost.y <= wood


## Pays cost.x gold and cost.y wood. Returns false and changes nothing if
## either is short.
func spend(cost: Vector2i) -> bool:
	if not can_afford(cost):
		return false
	gold -= cost.x
	wood -= cost.y
	gold_changed.emit(gold)
	wood_changed.emit(wood)
	return true


func lose_lives(amount: int) -> void:
	if is_defeated:
		return
	lives = maxi(lives - amount, 0)
	lives_changed.emit(lives)
	if lives == 0:
		is_defeated = true
		defeated.emit()
