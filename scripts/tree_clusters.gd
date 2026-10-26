class_name TreeClusters
extends RefCounted
## Single choppable trees grow in small groves of 2..5: every tree of the level model gets a few
## neighbours around it, so chopping out in the field is worth the walk next to the thicket by a
## portal (playtest 2026-10-24). The spots are found once per level from its layout (seeded by
## the level id and the tree's index), so every run, a replay and both co-op players get the same
## trees. Nothing grows on the roads, by the slots, the castle, the portals, the camps, the
## knight's start or the bushes.

## How many neighbours a tree may get (picked evenly from this list: groves of 2..5, mostly 2..3).
const NEIGHBOURS: Array[int] = [1, 1, 2, 2, 3, 4]
## Distance of a neighbour from its tree, metres.
const RING_MIN := 1.15
const RING_MAX := 1.6
## Tries for one neighbour before it is given up.
const TRIES := 10
## Clearances (metres from the centre of the thing).
const FROM_TREE := 1.1
const FROM_ROAD := 1.6
const FROM_SLOT := 1.8
const FROM_CASTLE := 3.2
const FROM_PORTAL := 2.6
const FROM_CAMP := 3.6
const FROM_HERO := 2.6
const FROM_BUSH := 0.9
const FROM_EDGE := 1.2


## Neighbour spots (XZ) for every tree of `trees` (same order). `blocked` are the bushes and
## other trees of the level (the thicket, the field) the neighbours keep away from; `camps` the
## camp positions.
static func neighbours(
	level: Dictionary, trees: Array[Vector2], blocked: Array[Vector2], camps: Array[Vector2]
) -> Array:
	var field: Rect2 = LevelBuilder.map_rect(level).grow(-FROM_EDGE)
	var roads: Array[PackedVector2Array] = LevelCatalog.routes(level)
	var fixed: Array[Vector2] = []
	for point: Array in level.get("slots", []):
		fixed.append(Vector2(float(point[0]), float(point[1])))
	var castle := Vector2(float(level["castle"][0]), float(level["castle"][1]))
	var hero := Vector2(float(level["hero"][0]), float(level["hero"][1]))
	var taken: Array[Vector2] = trees.duplicate()
	taken.append_array(blocked)
	var out: Array = []
	for i in trees.size():
		var rng := RandomNumberGenerator.new()
		rng.seed = int(level.get("id", 0)) * 7919 + i * 104729
		var wanted: int = NEIGHBOURS[rng.randi_range(0, NEIGHBOURS.size() - 1)]
		var spots: Array[Vector2] = []
		for n in wanted:
			for attempt in TRIES:
				var angle: float = rng.randf() * TAU
				var spot: Vector2 = (
					trees[i] + Vector2.from_angle(angle) * rng.randf_range(RING_MIN, RING_MAX)
				)
				if _free(spot, field, roads, fixed, castle, hero, camps, taken, blocked):
					spots.append(spot)
					taken.append(spot)
					break
		out.append(spots)
	return out


static func _free(
	spot: Vector2,
	field: Rect2,
	roads: Array[PackedVector2Array],
	slots: Array[Vector2],
	castle: Vector2,
	hero: Vector2,
	camps: Array[Vector2],
	taken: Array[Vector2],
	bushes: Array[Vector2]
) -> bool:
	if not field.has_point(spot):
		return false
	if spot.distance_to(castle) < FROM_CASTLE or spot.distance_to(hero) < FROM_HERO:
		return false
	for road: PackedVector2Array in roads:
		if road.size() > 0 and spot.distance_to(road[0]) < FROM_PORTAL:
			return false
		for k in road.size() - 1:
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(spot, road[k], road[k + 1])
			if spot.distance_to(near) < FROM_ROAD:
				return false
	for slot: Vector2 in slots:
		if spot.distance_to(slot) < FROM_SLOT:
			return false
	for camp: Vector2 in camps:
		if spot.distance_to(camp) < FROM_CAMP:
			return false
	for other: Vector2 in taken:
		if spot.distance_to(other) < FROM_TREE:
			return false
	for bush: Vector2 in bushes:
		if spot.distance_to(bush) < FROM_BUSH + FROM_TREE * 0.5:
			return false
	return true
