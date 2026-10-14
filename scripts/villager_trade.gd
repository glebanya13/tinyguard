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


## Gold for one lot after `sold` lots were already sold this level.
func lot_gold(sold: int) -> int:
	return maxi(min_gold, roundi(start_gold * pow(price_decay, sold)))


## Gold for `lots` lots in a row, starting after `sold` sold lots.
func quote(sold: int, lots: int) -> int:
	var total: int = 0
	for i in lots:
		total += lot_gold(sold + i)
	return total
