class_name Balance
extends RefCounted
## Balance numbers that are data, not code: resources/balance.json (the wave line-up
## table, boss count and growth, the share of the price a sold tower returns).
## tools/balance_sim.py reads the same file.

const PATH := "res://resources/balance.json"

static var _data: Dictionary = {}


## The parsed file (cached); an empty dictionary if it is missing or damaged.
static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("Balance: %s is missing or damaged" % PATH)
	return _data


static func waves() -> Dictionary:
	return data().get("waves", {})


## Share of everything spent on a tower that selling it returns.
static func sell_refund() -> float:
	return float(data().get("economy", {}).get("sell_refund", 0.0))
