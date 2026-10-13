class_name GameState
extends Node
## Gold and lives of the current level. Emits signals on every change.

signal gold_changed(gold: int)
signal lives_changed(lives: int)
signal defeated

@export var starting_gold: int = 100
@export var starting_lives: int = 20

var gold: int = 0
var lives: int = 0
var is_defeated: bool = false


func _ready() -> void:
	reset()


func reset() -> void:
	gold = starting_gold
	lives = starting_lives
	is_defeated = false
	gold_changed.emit(gold)
	lives_changed.emit(lives)


func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


func lose_lives(amount: int) -> void:
	if is_defeated:
		return
	lives = maxi(lives - amount, 0)
	lives_changed.emit(lives)
	if lives == 0:
		is_defeated = true
		defeated.emit()
