class_name LaneHint
extends Control
## Short-lived markers at the portals a new wave comes from: a pulsing ring over a
## portal that is on screen, an arrow on the screen edge pointing to one that is not.

## Seconds the markers stay (the last second fades out).
const SHOW_SECONDS := 6.0
## Distance of the markers from the screen edge, in canvas pixels.
const EDGE_MARGIN := 64.0
const ARROW_SIZE := 24.0
const RING_RADIUS := 34.0
const COLOR := Color(1.0, 0.66, 0.28)
const OUTLINE := Color(0.2, 0.1, 0.28)

var camera: Camera3D = null

var _points: Array[Vector3] = []
var _left: float = 0.0
var _age: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	_age += delta
	if _left <= 0.0:
		hide()
		return
	queue_redraw()


## Marks the given world points (portal positions) for `seconds`.
func show_points(points: Array[Vector3], seconds: float = SHOW_SECONDS) -> void:
	_points = points
	_left = seconds
	_age = 0.0
	show()
	queue_redraw()


## True while markers are shown.
func is_active() -> bool:
	return _left > 0.0


func _draw() -> void:
	if camera == null or _left <= 0.0:
		return
	var alpha: float = clampf(_left, 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(_age * 7.0)
	var area := Rect2(Vector2.ZERO, size).grow(-EDGE_MARGIN)
	var safe: Vector4 = ScreenUtil.safe_margins(get_viewport())
	area = Rect2(
		area.position + Vector2(safe.x, safe.y),
		area.size - Vector2(safe.x + safe.z, safe.y + safe.w)
	)
	for point: Vector3 in _points:
		var screen: Vector2 = camera.unproject_position(point)
		if area.has_point(screen):
			_draw_ring(screen, pulse, alpha)
		else:
			_draw_edge_arrow(area, screen, pulse, alpha)


func _draw_ring(at: Vector2, pulse: float, alpha: float) -> void:
	var radius: float = RING_RADIUS + 8.0 * pulse
	draw_arc(at, radius, 0.0, TAU, 40, Color(OUTLINE, alpha), 9.0, true)
	draw_arc(at, radius, 0.0, TAU, 40, Color(COLOR, alpha), 5.0, true)


func _draw_edge_arrow(area: Rect2, target: Vector2, pulse: float, alpha: float) -> void:
	var centre: Vector2 = area.get_center()
	var dir: Vector2 = target - centre
	if dir.length() < 1.0:
		return
	# Where the line centre -> target leaves the area.
	var t: float = minf(
		area.size.x * 0.5 / maxf(absf(dir.x), 0.001), area.size.y * 0.5 / maxf(absf(dir.y), 0.001)
	)
	var tip: Vector2 = centre + dir * t
	var forward: Vector2 = dir.normalized()
	var side := Vector2(-forward.y, forward.x)
	var s: float = ARROW_SIZE * (1.0 + 0.2 * pulse)
	var base: Vector2 = tip - forward * s * 1.6
	var shape := PackedVector2Array([tip, base + side * s, base - side * s])
	draw_colored_polygon(shape, Color(COLOR, alpha))
	shape.append(tip)
	draw_polyline(shape, Color(OUTLINE, alpha), 4.0, true)
