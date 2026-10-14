class_name Villagers
extends Node3D
## Villagers of a level: settles them on free ground near the castle, away
## from the enemy paths and tower slots, and buys the hero's wood for gold at
## the VillagerTrade prices (every lot sold makes the next one cheaper).

signal wood_sold(wood: int, gold: int)

const VILLAGER_SCENE: PackedScene = preload("res://scenes/villager.tscn")
## Centre and four sides of a villager (times body_radius) checked by is_open().
const BODY_POINTS: Array[Vector2] = [
	Vector2.ZERO, Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN
]

@export var trade: VillagerTrade = preload("res://resources/villager_trade.tres")
## Villagers per level (each costs a few draw calls).
@export var count: int = 2
## The trade card opens when the hero is this close to a villager (metres).
@export var trade_reach: float = 1.5
## Homes are searched this far from the castle centre.
@export var home_distance_min: float = 3.0
@export var home_distance_max: float = 9.0
## Score lost per metre from the castle when picking homes (closer is better).
@export var distance_penalty: float = 0.04
@export var home_spacing: float = 2.5
## Villagers stroll this far from home; a home needs at least `min_room` of
## the ground around it (within stroll_radius) open.
@export var stroll_radius: float = 1.8
@export_range(0.0, 1.0) var min_room: float = 0.45
## A home keeps this far from the hero's start (no trade card at level start).
@export var hero_clearance: float = 2.5
## Where villagers may stand: this far from the enemy paths and from slots.
@export var path_clearance: float = 1.5
@export var slot_clearance: float = 1.4
## Half the villager's width: these points around a spot must be free too.
@export var body_radius: float = 0.3

var game_state: GameState = null
## Seeds the villagers' decorative strolls (the battle seed).
var seed_value: int = 0
## Lots sold this level.
var lots_sold: int = 0

var _villagers: Array[Villager] = []
var _grid: WalkGrid = null
var _paths: Array[Path3D] = []
var _slots := PackedVector3Array()


## Places `count` villagers around `castle`. Needs the built walk grid.
func spawn(
	grid: WalkGrid,
	paths: Array[Path3D],
	castle: Vector3,
	hero_start: Vector3,
	slots: PackedVector3Array
) -> void:
	_grid = grid
	_paths = paths
	_slots = slots
	# Candidates on a 1 m lattice around the castle, roomiest and closest first.
	var candidates: Array[Vector4] = []  # x, z, score, unused
	var reach: int = ceili(home_distance_max)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var spot: Vector3 = castle + Vector3(dx, 0.0, dz)
			var distance: float = _flat_distance(spot, castle)
			if distance < home_distance_min or distance > home_distance_max:
				continue
			if _flat_distance(spot, hero_start) < hero_clearance or not is_open(spot):
				continue
			var room: float = _room(spot)
			if room >= min_room:
				candidates.append(Vector4(spot.x, spot.z, room - distance_penalty * distance, 0.0))
	# Equal scores are ordered by position: sort_custom is not stable.
	candidates.sort_custom(
		func(a: Vector4, b: Vector4) -> bool:
			if a.z != b.z:
				return a.z > b.z
			return a.x < b.x if a.x != b.x else a.y < b.y
	)
	var homes: Array[Vector3] = []
	for c in candidates:
		var spot := Vector3(c.x, 0.0, c.y)
		var spaced: bool = true
		for other in homes:
			spaced = spaced and _flat_distance(other, spot) >= home_spacing
		if spaced and homes.size() < count:
			homes.append(spot)
	for spot in homes:
		var villager := VILLAGER_SCENE.instantiate() as Villager
		villager.home = spot
		villager.rng.seed = seed_value + _villagers.size() + 1
		villager.wander_radius = stroll_radius
		villager.ground_check = is_open
		add_child(villager)
		villager.global_position = spot
		_villagers.append(villager)


func get_villagers() -> Array[Villager]:
	return _villagers


## True if a villager may stand on `point`: free ground, off the paths and slots.
func is_open(point: Vector3) -> bool:
	if _grid == null:
		return false
	for offset: Vector2 in BODY_POINTS:
		if not _grid.is_free(Vector2(point.x, point.z) + offset * body_radius):
			return false
	for slot in _slots:
		if _flat_distance(slot, point) < slot_clearance:
			return false
	for path in _paths:
		if path.curve.point_count < 2:
			continue
		var closest: Vector3 = path.to_global(path.curve.get_closest_point(path.to_local(point)))
		if _flat_distance(closest, point) < path_clearance:
			return false
	return true


## Nearest villager within `reach` of `point` on the ground, or null.
func nearest(point: Vector3, reach: float) -> Villager:
	var best: Villager = null
	var best_distance: float = reach
	for villager in _villagers:
		var d: float = _flat_distance(villager.global_position, point)
		if d <= best_distance:
			best_distance = d
			best = villager
	return best


## Gold the next lot of wood brings.
func lot_price() -> int:
	return trade.lot_gold(lots_sold)


## Whole lots the player's wood makes.
func lots_affordable() -> int:
	return floori(float(game_state.wood) / trade.wood_per_lot) if game_state else 0


## Gold for the next `lots` lots.
func quote(lots: int) -> int:
	return trade.quote(lots_sold, lots)


## Sells up to `lots` lots of wood (never more than the player has).
## Returns the gold received (0 if there was not enough wood for one lot).
func sell(lots: int) -> int:
	lots = mini(lots, lots_affordable())
	if lots <= 0:
		return 0
	var wood: int = lots * trade.wood_per_lot
	var gold: int = quote(lots)
	if not game_state.spend(Vector2i(0, wood)):
		return 0
	lots_sold += lots
	game_state.add_gold(gold)
	wood_sold.emit(wood, gold)
	return gold


## Share of open ground within stroll_radius of `spot` (3 rings of 8 samples).
func _room(spot: Vector3) -> float:
	var open: int = 0
	for ring in range(1, 4):
		for k in 8:
			var angle: float = TAU * k / 8.0
			var r: float = stroll_radius * ring / 3.0
			if is_open(spot + Vector3(cos(angle), 0.0, sin(angle)) * r):
				open += 1
	return open / 24.0


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
