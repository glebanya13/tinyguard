class_name Events
extends RefCounted
## Seasonal events from resources/events.json: a date range (UTC days), a gem reward
## multiplier and a castle flag. Pure: the answer depends on the date only.

const DATA_PATH := "res://resources/events.json"
## The multiplier is clamped to this range (the cloud rules assume at most x2).
const MAX_MULT := 2.0

static var _data: Array = []


static func all() -> Array:
	if _data.is_empty():
		var json: JSON = load(DATA_PATH)
		_data = json.data["events"]
	return _data


## The active event on a day ("yyyy-mm-dd") or an empty Dictionary.
static func active(day: String) -> Dictionary:
	var index: int = Daily.day_index(day)
	if index < 0:
		return {}
	for event: Dictionary in all():
		if not bool(event.get("enabled", false)):
			continue
		var from: int = Daily.day_index(str(event.get("from", "")))
		var to: int = Daily.day_index(str(event.get("to", "")))
		if from >= 0 and to >= from and index >= from and index <= to:
			return event
	return {}


## Reward multiplier on a day (1.0 without an event).
static func reward_mult(day: String) -> float:
	var event: Dictionary = active(day)
	return (
		clampf(float(event.get("reward_mult", 1.0)), 1.0, MAX_MULT) if not event.is_empty() else 1.0
	)
