class_name LevelPrefetch
extends RefCounted
## Loads the heavy models of a level (terrain, decor, forest: ~7 MB of .glb) on a worker
## thread while the player is still reading the level card on the map, so that pressing
## "Play" does not freeze a weak phone for a second on the main thread. Only the chosen
## level is kept: choosing another one lets go of the previous request. Without a
## prefetch take() simply loads on the spot.

const PARTS: Array[String] = ["terrain", "decor", "forest"]
const MODEL_PATH := "res://assets/models/level_%d_%s.glb"

## Paths asked for and not yet taken.
static var _pending: Array[String] = []
static var _level: int = 0


static func model_path(level_id: int, part: String) -> String:
	return MODEL_PATH % [level_id, part]


## Starts loading the models of `level_id` in the background (no-op if already asked for).
static func request(level_id: int) -> void:
	if level_id == _level and not _pending.is_empty():
		return
	release()
	_level = level_id
	for part in PARTS:
		var path: String = model_path(level_id, part)
		if ResourceLoader.load_threaded_request(path) == OK:
			_pending.append(path)


## The loaded resource at `path`: the prefetched one when there is one (waits for it if
## it is still loading), else a plain load.
static func take(path: String) -> Resource:
	if path in _pending:
		_pending.erase(path)
		return ResourceLoader.load_threaded_get(path)
	return load(path)


## Lets go of whatever was prefetched and not used.
static func release() -> void:
	for path in _pending:
		ResourceLoader.load_threaded_get(path)  # a finished request must be collected
	_pending.clear()
	_level = 0


static func pending_count() -> int:
	return _pending.size()
