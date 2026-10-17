class_name GameState
extends Node
## Gold, wood and lives of the current level. Emits signals on every change.

signal gold_changed(gold: int)
signal wood_changed(wood: int)
signal lives_changed(lives: int)
## The castle was upgraded (its new level, 1..CastleUpgrades.max_level()).
signal castle_upgraded(level: int)
signal defeated

@export var starting_gold: int = 0
@export var starting_wood: int = 0
@export var starting_lives: int = 20
## Castle repair at the forge: lives restored and its wood price.
@export var repair_lives: int = 2
@export var repair_wood: int = 25

var gold: int = 0
var wood: int = 0
var lives: int = 0
var is_defeated: bool = false
## Castle upgrades bought in this battle (0 = the plain castle). Part of the state hash
## only once above 0, so battles without upgrades keep the hashes they always had.
var castle_level: int = 0

var _base_lives: int = 0


func _ready() -> void:
	_base_lives = starting_lives
	reset()


## Starting values from a level's "start" block.
func configure(start: Dictionary) -> void:
	starting_gold = int(start.get("gold", starting_gold))
	starting_wood = int(start.get("wood", starting_wood))
	starting_lives = int(start.get("lives", starting_lives))
	_base_lives = starting_lives


func reset() -> void:
	castle_level = 0
	starting_lives = _base_lives
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


func can_repair() -> bool:
	return lives < starting_lives and wood >= repair_wood and not is_defeated


## Pays wood for up to repair_lives lives (never above the starting lives).
func repair() -> bool:
	if not can_repair():
		return false
	wood -= repair_wood
	lives = mini(lives + repair_lives, starting_lives)
	wood_changed.emit(wood)
	lives_changed.emit(lives)
	return true


## Price of the next castle upgrade (-1, -1 at the maximum).
func castle_upgrade_cost() -> Vector2i:
	return CastleUpgrades.cost(castle_level)


func can_upgrade_castle() -> bool:
	return not is_defeated and can_afford(castle_upgrade_cost()) and castle_upgrade_cost().x >= 0


## Buys the next castle upgrade: more lives (and a higher repair ceiling), more armor.
func upgrade_castle() -> bool:
	if not can_upgrade_castle():
		return false
	var bonus: int = CastleUpgrades.lives_bonus(castle_level)
	spend(castle_upgrade_cost())
	castle_level += 1
	starting_lives += bonus
	lives += bonus
	lives_changed.emit(lives)
	castle_upgraded.emit(castle_level)
	return true


## Armor of the castle: every leak takes that much less (at least 1 life).
func castle_armor() -> int:
	return CastleUpgrades.armor_at(castle_level)


## An enemy with `damage` reached the castle: its armor takes part of it off.
func take_leak(damage: int) -> void:
	lose_lives(CastleUpgrades.leak_damage(damage, castle_level))


func lose_lives(amount: int) -> void:
	if is_defeated:
		return
	lives = maxi(lives - amount, 0)
	lives_changed.emit(lives)
	if lives == 0:
		is_defeated = true
		defeated.emit()
