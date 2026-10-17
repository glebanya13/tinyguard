class_name LaneMap
extends RefCounted
## Geometry of the road compass (the mini map in the corner): the top view of the field in
## world axes (X to the right, Z down, NOT rotated by the camera's 45 degrees), a frame with
## the proportions of the field, the roads simplified (Douglas-Peucker) and their corners
## rounded, the portals on the rim with the side written next to them (the words of the
## banner "From the north!", short). Everything is computed once per level and panel size,
## in the frame's own pixels, and cached: LaneHint only draws it.

const PAD := 12.0
## Roads are simplified to this tolerance (metres) before they are drawn.
const SIMPLIFY_METRES := 3.4
## Corner cutting rounds after the simplification (each round doubles the segments).
const ROUNDS := 1
const LABEL_SIZE := 18
## Side of a badge of the atlas (pixels); the dot is the left cell, the castle the right one.
const CELL := 64
const DOT_REGION := Rect2(0, 0, 64, 64)
const CASTLE_REGION := Rect2(64, 0, 64, 64)
## Drawn size of the castle badge (pixels).
const CASTLE_SIZE := 28.0
const DIM_CAP := 1.5
const LIT_OUTLINE_CAP := 3.5
const LIT_CORE_CAP := 2.0
const DASH := 6.0
## Short names of the 8 screen directions (the order of LevelCatalog.DIRECTION_KEYS).
const DIRECTION_KEYS: Array[String] = [
	"MAP_DIR_N",
	"MAP_DIR_NE",
	"MAP_DIR_E",
	"MAP_DIR_SE",
	"MAP_DIR_S",
	"MAP_DIR_SW",
	"MAP_DIR_W",
	"MAP_DIR_NW",
]
## The castle badge: a keep with three merlons (pixels from its centre) and a door.
const CASTLE_SHAPE: Array[Vector2] = [
	Vector2(-9, 8),
	Vector2(-9, -7),
	Vector2(-5, -7),
	Vector2(-5, -3),
	Vector2(-2, -3),
	Vector2(-2, -7),
	Vector2(2, -7),
	Vector2(2, -3),
	Vector2(5, -3),
	Vector2(5, -7),
	Vector2(9, -7),
	Vector2(9, 8),
]
const CASTLE_DOOR: Array[Vector2] = [
	Vector2(-3, 8), Vector2(-3, 2), Vector2(0, -0.5), Vector2(3, 2), Vector2(3, 8)
]

## True: the map is turned like the screen (its top is the top of the screen, so the side
## names of the banner point where they say; the field is a diamond, like in the game); false:
## the world's own axes (X to the right, Z down).
static var screen_oriented: bool = true
static var _atlas: ImageTexture = null
## Frame in the coordinates of the box it was built for (sits in the box's bottom-left corner).
var frame: Rect2 = Rect2()
var scale: float = 1.0
var castle: Vector2 = Vector2.ZERO
## Per road (index of level["paths"]): the full route to the castle, the portal, in pixels
## of the frame.
var routes: Array[PackedVector2Array] = []
var portals: Array[Vector2] = []
## {"lane", "text", "rect"} per drawn side name, rects in pixels of the frame.
var labels: Array[Dictionary] = []
## Segments (pairs of points) of every road's own part, for one draw_multiline.
var dim := PackedVector2Array()
## Segments of the lit roads: outline, core and the flight lines (see set_lit()).
var lit_outline := PackedVector2Array()
var lit_core := PackedVector2Array()
var lit_air := PackedVector2Array()

var _field: Rect2 = Rect2()
var _corners: Array[Vector2] = []
var _built_id: int = -1
var _built_box: Vector2 = Vector2.ZERO
var _built_locale: String = ""
var _lit: Array[int] = []


## Builds the map for `level` in a box of `box_size` (HudLayout "map" rect); does nothing when
## it is already built for them. `font` measures the side names.
func build(level: Dictionary, box_size: Vector2, font: Font) -> void:
	var id: int = int(level.get("id", 0))
	var locale: String = TranslationServer.get_locale()
	if _built_id == id and _built_box == box_size and _built_locale == locale:
		return
	_built_id = id
	_built_box = box_size
	_built_locale = locale
	routes.clear()
	portals.clear()
	labels.clear()
	dim.clear()
	if level.is_empty():
		return
	var bounds: Array = level["bounds"]
	var world := Rect2(float(bounds[0]), float(bounds[1]), float(bounds[2]), float(bounds[3]))
	_corners = [
		world.position,
		Vector2(world.end.x, world.position.y),
		world.end,
		Vector2(world.position.x, world.end.y)
	]
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner: Vector2 in _corners:
		low = low.min(_turn(corner))
		high = high.max(_turn(corner))
	_field = Rect2(low, high - low)
	var inner: Vector2 = box_size - Vector2.ONE * PAD * 2.0
	scale = minf(inner.x / _field.size.x, inner.y / _field.size.y)
	var frame_size: Vector2 = _field.size * scale + Vector2.ONE * PAD * 2.0
	frame = Rect2(Vector2(0.0, box_size.y - frame_size.y), frame_size)
	var castle_world := Vector2(float(level["castle"][0]), float(level["castle"][1]))
	castle = to_map(castle_world)
	var paths: Array = level["paths"]
	var full: Array[PackedVector2Array] = []
	var firsts: Array[Vector2] = []
	for lane in paths.size():
		var raw := PackedVector2Array()
		for point: Array in paths[lane]:
			raw.append(Vector2(float(point[0]), float(point[1])))
		var own: PackedVector2Array = simplify(raw, SIMPLIFY_METRES)
		firsts.append(raw[0])
		add_segments(dim, _pixels(own), DIM_CAP)
		var route: PackedVector2Array = own
		if not LevelCatalog.is_gate(raw[raw.size() - 1], castle_world):
			route = join_to_earlier(own, full)
		full.append(route)
		routes.append(_pixels(route))
		portals.append(to_map(raw[0]))
	_place_labels(firsts, castle_world, font)
	_lit.clear()
	_rebuild_lit()


## Map position (pixels of the frame) of a world point (X, Z).
func to_map(world: Vector2) -> Vector2:
	return (_turn(world) - _field.position) * scale + Vector2.ONE * PAD


## The outline of the field in map pixels (4 corners).
func field_outline() -> PackedVector2Array:
	var out := PackedVector2Array()
	for corner: Vector2 in _corners:
		out.append(to_map(corner))
	return out


func _turn(world: Vector2) -> Vector2:
	if not screen_oriented:
		return world
	return Vector2(world.dot(LevelCatalog.SCREEN_RIGHT), -world.dot(LevelCatalog.SCREEN_UP))


## The roads of the current wave glow; rebuilt only when the set changes.
func set_lit(lanes: Array[int]) -> void:
	if lanes == _lit:
		return
	_lit = lanes.duplicate()
	_rebuild_lit()


func _rebuild_lit() -> void:
	lit_outline.clear()
	lit_core.clear()
	lit_air.clear()
	for lane: int in _lit:
		if lane >= routes.size():
			continue
		add_segments(lit_outline, routes[lane], LIT_OUTLINE_CAP)
		add_segments(lit_core, routes[lane], LIT_CORE_CAP)
		# Flyers go straight from the portal to the castle: a dashed line.
		add_dashes(lit_air, portals[lane], castle, DASH)


func _pixels(route: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in route:
		out.append(to_map(p))
	return round_corners(out, ROUNDS)


## A path that ends on an earlier road continues along it (the remaining points of the earlier
## simplified route), so the shared stretches are the very same points and never double up.
static func join_to_earlier(
	own: PackedVector2Array, earlier: Array[PackedVector2Array]
) -> PackedVector2Array:
	var end: Vector2 = own[own.size() - 1]
	var best: float = INF
	var best_route: int = -1
	var best_segment: int = 0
	var best_point: Vector2 = end
	for r in earlier.size():
		for i in earlier[r].size() - 1:
			var at: Vector2 = Geometry2D.get_closest_point_to_segment(
				end, earlier[r][i], earlier[r][i + 1]
			)
			if at.distance_to(end) < best:
				best = at.distance_to(end)
				best_route = r
				best_segment = i
				best_point = at
	if best_route < 0:
		return own
	var out: PackedVector2Array = own.duplicate()
	out[out.size() - 1] = best_point
	for i in range(best_segment + 1, earlier[best_route].size()):
		out.append(earlier[best_route][i])
	return out


## The side names next to the portals, inside the frame, never over each other or over another
## portal's dot: a name that would overlap is nudged along the rim, and dropped if it cannot
## be placed (the banner still says it).
func _place_labels(starts: Array[Vector2], castle_world: Vector2, font: Font) -> void:
	var placed: Array[Rect2] = []
	var inside := Rect2(Vector2.ONE * 2.0, frame.size - Vector2.ONE * 4.0)
	for lane in starts.size():
		var key: String = DIRECTION_KEYS[LevelCatalog.screen_direction(starts[lane] - castle_world)]
		var text: String = TranslationServer.translate(key)
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		var extent := Vector2(width, LABEL_SIZE * 1.05)
		var toward: Vector2 = (frame.size * 0.5 - portals[lane]).normalized()
		var spot: Vector2 = portals[lane] + toward * (extent.length() * 0.5 + 6.0)
		var rect := Rect2(spot - extent * 0.5, extent)
		rect.position = rect.position.clamp(inside.position, inside.end - extent)
		var tangent := Vector2(-toward.y, toward.x)
		var tries: int = 0
		while (_overlaps(rect, placed) or _hits_dot(rect, lane)) and tries < 12:
			var sign: float = 1.0 if tries % 2 == 0 else -1.0
			rect.position += tangent * extent.y * 0.6 * sign * float(1 + tries / 2)
			rect.position = rect.position.clamp(inside.position, inside.end - extent)
			tries += 1
		if _overlaps(rect, placed) or _hits_dot(rect, lane):
			continue
		placed.append(rect)
		labels.append({"lane": lane, "text": text, "rect": rect})


func _overlaps(rect: Rect2, others: Array[Rect2]) -> bool:
	for other: Rect2 in others:
		if rect.grow(2.0).intersects(other):
			return true
	return false


func _hits_dot(rect: Rect2, lane: int) -> bool:
	for i in portals.size():
		if i != lane and rect.grow(5.0).has_point(portals[i]):
			return true
	return false


## Appends the segments of a polyline to `out` (pairs of points), each lengthened by `cap`
## at both ends so that the joints of a thick multiline have no notches.
static func add_segments(out: PackedVector2Array, points: PackedVector2Array, cap: float) -> void:
	for i in points.size() - 1:
		var dir: Vector2 = (points[i + 1] - points[i]).normalized() * cap
		out.append(points[i] - dir)
		out.append(points[i + 1] + dir)


## Dashes along the straight line a -> b (pairs of points) for a multiline.
static func add_dashes(out: PackedVector2Array, a: Vector2, b: Vector2, dash: float) -> void:
	var length: float = a.distance_to(b)
	var dir: Vector2 = (b - a) / maxf(length, 0.001)
	var at: float = 0.0
	while at < length:
		out.append(a + dir * at)
		out.append(a + dir * minf(at + dash, length))
		at += dash * 2.0


## Douglas-Peucker: the polyline without the points that lie within `epsilon` of the line
## through their neighbours. The ends always stay.
static func simplify(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var keep := PackedByteArray()
	keep.resize(points.size())
	keep[0] = 1
	keep[points.size() - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, points.size() - 1)]
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var far: float = 0.0
		var index: int = -1
		for at in range(span.x + 1, span.y):
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
				points[at], points[span.x], points[span.y]
			)
			var d: float = points[at].distance_to(closest)
			if d > far:
				far = d
				index = at
		if index >= 0 and far > epsilon:
			keep[index] = 1
			stack.append(Vector2i(span.x, index))
			stack.append(Vector2i(index, span.y))
	var out := PackedVector2Array()
	for i in points.size():
		if keep[i] == 1:
			out.append(points[i])
	return out


## Chaikin corner cutting: rounds the corners of a polyline, the ends stay.
static func round_corners(points: PackedVector2Array, rounds: int) -> PackedVector2Array:
	var current: PackedVector2Array = points
	for r in rounds:
		if current.size() < 3:
			break
		var next := PackedVector2Array([current[0]])
		for i in current.size() - 1:
			var a: Vector2 = current[i]
			var b: Vector2 = current[i + 1]
			if i > 0:
				next.append(a.lerp(b, 0.25))
			if i < current.size() - 2:
				next.append(a.lerp(b, 0.75))
		next.append(current[current.size() - 1])
		current = next
	return current


## One small texture with the two badges (a white dot, the castle), so that all the dots and the
## castle are drawn in a single batch: drawing each circle and polygon on its own cost a draw
## call apiece. Baked once, in code (no image file).
static func atlas() -> ImageTexture:
	if _atlas != null:
		return _atlas
	var image := Image.create(CELL * 2, CELL, false, Image.FORMAT_RGBA8)
	var shape := PackedVector2Array()
	for p: Vector2 in CASTLE_SHAPE:
		shape.append(p * (CELL * 0.45 / 9.0) + Vector2(CELL * 1.5, CELL * 0.5))
	var door := PackedVector2Array()
	for p: Vector2 in CASTLE_DOOR:
		door.append(p * (CELL * 0.45 / 9.0) + Vector2(CELL * 1.5, CELL * 0.5))
	var outline: float = 2.2
	for y in CELL:
		for x in CELL * 2:
			var sum := Color(0, 0, 0, 0)
			for sample in 9:
				var at := Vector2(x + (sample % 3 + 0.5) / 3.0, y + (sample / 3 + 0.5) / 3.0)
				var c: Color = (
					_dot_color(at) if x < CELL else _castle_color(at, shape, door, outline)
				)
				sum += Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a)
			if sum.a > 0.0:
				image.set_pixel(
					x, y, Color(sum.r / sum.a, sum.g / sum.a, sum.b / sum.a, sum.a / 9.0)
				)
	_atlas = ImageTexture.create_from_image(image)
	return _atlas


static func _dot_color(at: Vector2) -> Color:
	var centre := Vector2(CELL * 0.5, CELL * 0.5)
	return Color.WHITE if at.distance_to(centre) <= CELL * 0.48 else Color(0, 0, 0, 0)


static func _castle_color(
	at: Vector2, shape: PackedVector2Array, door: PackedVector2Array, outline: float
) -> Color:
	var inside: bool = Geometry2D.is_point_in_polygon(at, shape)
	var edge: float = INF
	for i in shape.size():
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(
			at, shape[i], shape[(i + 1) % shape.size()]
		)
		edge = minf(edge, at.distance_to(closest))
	if edge <= outline * 0.6 + (0.0 if inside else outline * 0.6):
		return Color(0.2, 0.1, 0.28)
	if not inside:
		return Color(0, 0, 0, 0)
	if Geometry2D.is_point_in_polygon(at, door):
		return Color(0.2, 0.28, 0.6)
	return Color(0.98, 0.8, 0.4)
