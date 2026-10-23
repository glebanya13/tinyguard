class_name VillagerTrade
extends Resource
## Prices villagers pay for wood. Wood is sold in lots of `wood_per_lot`; the
## first lot of a level brings `start_gold`, every lot sold makes the next one
## `price_decay` times cheaper (never below `min_gold`), so selling is a choice
## and not an endless gold mine.

@export var wood_per_lot: int = 10
@export var start_gold: float = 6.0
@export var price_decay: float = 0.93
@export var min_gold: int = 2

@export_group("Buying wood")
## The villager sells wood back in the same lots: the first lot costs `buy_start_gold`,
## every bought lot makes the next `buy_growth` times dearer, at most `buy_max_lots` a battle.
@export var buy_start_gold: float = 14.0
@export var buy_growth: float = 1.08
@export var buy_max_lots: int = 6
## One bought lot comes back for sale every this many seconds (an emergency valve, not a mine).
@export var buy_restock_seconds: float = 60.0

@export_group("Lumberjacks")
## A villager hired for `hire_gold` chops `hire_wood_per_minute` wood a minute (wood only,
## never gold); at most `hire_max` of the level's villagers can be hired.
@export var hire_gold: int = 25
@export var hire_max: int = 2
@export var hire_wood_per_minute: int = 5


## Gold for one lot after `sold` lots were already sold this level.
func lot_gold(sold: int) -> int:
	return maxi(min_gold, roundi(start_gold * pow(price_decay, sold)))


## Gold for `lots` lots in a row, starting after `sold` sold lots.
func quote(sold: int, lots: int) -> int:
	var total: int = 0
	for i in lots:
		total += lot_gold(sold + i)
	return total


## Gold for one bought lot after `bought` lots were already bought this level.
## Buying is dearer than selling by at least `buy_start_gold - start_gold`, so a
## round trip (buy, sell back) always loses gold.
func buy_lot_gold(bought: int) -> int:
	return maxi(1, roundi(buy_start_gold * pow(buy_growth, bought)))


## Gold for `lots` lots in a row, starting after `bought` bought lots.
func buy_quote(bought: int, lots: int) -> int:
	var total: int = 0
	for i in lots:
		total += buy_lot_gold(bought + i)
	return total


## One wood is `TICK_RATE * 60` units of chopping progress; a lumberjack earns
## `hire_wood_per_minute` units a tick (whole numbers: 5 a minute = one wood per 360 ticks).
func chop_accum_limit() -> int:
	return Sim.TICK_RATE * 60
