class_name WalkGrid
extends RefCounted
## Walkable grid of the level for the hero's orders (AStarGrid2D, X/Z plane).
## Built once from physics: a cell is blocked when a hero-sized cylinder at its
## centre touches a static body (trees, stumps, bushes, rocks, castle, walls).

const CELL := 0.5
## A bit wider than the hero's capsule so paths keep clear of trunks.
const CLEARANCE := 0.34
## Distance between samples when checking a straight line for obstacles.
const LINE_STEP := 0.2
## Half width of the corridor a shortcut must keep free (about the hero's radius).
const LINE_HALF_WIDTH := 0.3
## Radius blocked around a placed tower.
const TOWER_BLOCK_RADIUS := 0.6

var _astar := AStarGrid2D.new()
var _origin := Vector2.ZERO
## Cells blocked by block(), per blocked point, so unblock() frees only those.
var _blocked: Dictionary = {}


## `area` is the level rectangle in X/Z; `mask` the obstacle physics layers.
func build(space: PhysicsDirectSpaceState3D, area: Rect2, mask: int) -> void:
	_origin = area.position
	var cells := Vector2i(ceili(area.size.x / CELL), ceili(area.size.y / CELL))
	_astar.region = Rect2i(Vector2i.ZERO, cells)
	_astar.cell_size = Vector2.ONE * CELL
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	var shape := CylinderShape3D.new()
	shape.radius = CLEARANCE
	shape.height = 1.1  # same span as the hero capsule: from the ground up
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = mask
	query.collide_with_areas = false
	for x in cells.x:
		for y in cells.y:
			var p: Vector2 = _cell_center(Vector2i(x, y))
			query.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, 0.55, p.y))
			if not space.intersect_shape(query, 1).is_empty():
				_astar.set_point_solid(Vector2i(x, y))


## Marks cells within `radius` of `point` as blocked (e.g. a new tower).
func block(point: Vector3, radius: float) -> void:
	var r: int = ceili(radius / CELL)
	var center: Vector2i = _to_cell(point)
	var cells: Array[Vector2i] = []
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var cell := center + Vector2i(dx, dy)
			var near: bool = (
				_cell_center(cell).distance_to(Vector2(point.x, point.z)) <= radius + CELL * 0.5
			)
			if near and _astar.is_in_boundsv(cell) and not _astar.is_point_solid(cell):
				_astar.set_point_solid(cell)
				cells.append(cell)
	if _blocked.has(center):
		var existing: Array = _blocked[center]
		for c in cells:
			if not existing.has(c):
				existing.append(c)
	else:
		_blocked[center] = cells


## Undoes block() at the same point.
func unblock(point: Vector3) -> void:
	for cell: Vector2i in _blocked.get(_to_cell(point), []):
		_astar.set_point_solid(cell, false)
	_blocked.erase(_to_cell(point))


## Blocks the walk grid cells occupied by a tower on a slot (static or dynamic).
func block_slot(slot: TowerSlot, radius: float = TOWER_BLOCK_RADIUS) -> void:
	if slot != null:
		block(slot.global_position, radius)


## Undoes block_slot() when a tower is sold/removed from a slot.
func unblock_slot(slot: TowerSlot) -> void:
	if slot != null:
		unblock(slot.global_position)


## Waypoints (on the ground) from `from` to near `to`, without `from`.
## Empty if there is no way or the grid was not built.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _astar.region.size == Vector2i.ZERO:
		return out
	var start: Vector2i = _nearest_free(_to_cell(from))
	var goal: Vector2i = _nearest_free(_to_cell(to))
	if start.x < 0 or goal.x < 0:
		return out
	var ids: Array[Vector2i] = _astar.get_id_path(start, goal)
	if ids.is_empty():
		return out
	var points: Array[Vector2] = [Vector2(from.x, from.z)]
	for id in ids:
		points.append(_cell_center(id))
	points[-1] = Vector2(to.x, to.z) if is_free(Vector2(to.x, to.z)) else points[-1]
	# String pulling: skip waypoints that can be reached in a straight line.
	var i: int = 0
	while i < points.size() - 1:
		var j: int = points.size() - 1
		while j > i + 1 and not _line_free(points[i], points[j]):
			j -= 1
		out.append(Vector3(points[j].x, 0.0, points[j].y))
		i = j
	return out


func is_free(point: Vector2) -> bool:
	var cell: Vector2i = _to_cell(Vector3(point.x, 0.0, point.y))
	return _astar.is_in_boundsv(cell) and not _astar.is_point_solid(cell)


## Straight walk check with the hero's width: the centre line and two lines
## shifted sideways must all stay on free cells (no cutting past trunks).
func _line_free(a: Vector2, b: Vector2) -> bool:
	var length: float = a.distance_to(b)
	if length < 0.001:
		return true
	var side: Vector2 = (b - a).orthogonal().normalized() * LINE_HALF_WIDTH
	var steps: int = maxi(1, ceili(length / LINE_STEP))
	for k in range(1, steps):
		var p: Vector2 = a.lerp(b, float(k) / steps)
		if not (is_free(p) and is_free(p + side) and is_free(p - side)):
			return false
	return true


func _to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - _origin.x) / CELL), floori((p.z - _origin.y) / CELL))


func _cell_center(cell: Vector2i) -> Vector2:
	return _origin + (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


## The cell itself if walkable, else the closest walkable one (ring search).
func _nearest_free(cell: Vector2i) -> Vector2i:
	for r in 6:
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := cell + Vector2i(dx, dy)
				if _astar.is_in_boundsv(c) and not _astar.is_point_solid(c):
					return c
	return Vector2i(-1, -1)
