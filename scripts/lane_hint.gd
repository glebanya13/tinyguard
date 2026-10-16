class_name LaneHint
extends Control
## Where the current wave comes from, shown globally and not only at the portal:
##  - for a few seconds a pulsing ring over a portal that is on screen;
##  - for the whole wave an arrow on the screen edge towards every road the wave uses,
##    on screen or not, blinking, with the side written next to it ("From the north!");
##  - a compass in the corner (the castle, the roads of the map from above, the roads of
##    this wave lit, the others dim) that opens with every wave for a few seconds and
##    by the button under the pause button.
## It only draws: the wave plan, the camera and the level are handed in.

## Seconds the rings stay (the last second fades out).
const SHOW_SECONDS := 6.0
## Seconds the compass stays open at the start of a wave (unless pinned by the button).
const COMPASS_SECONDS := 10.0
## The edge arrows go out by themselves after this long if nobody calls finish().
const ARROW_SECONDS := 60.0
## Margins (left, top, right, bottom) of the area the edge arrows live in, canvas pixels:
## they keep clear of the counters, the pause buttons, the card and the swing buttons.
const EDGE_MARGINS := Vector4(40.0, 108.0, 150.0, 120.0)
const ARROW_SIZE := 24.0
const RING_RADIUS := 34.0
const LABEL_SIZE := 22
const COLOR := Color(1.0, 0.66, 0.28)
const OUTLINE := Color(0.2, 0.1, 0.28)
const MUTED := Color(0.72, 0.78, 0.92, 0.38)
const PANEL_SIZE := Vector2(236.0, 150.0)
const PANEL_TOP := 172.0
const PANEL_RIGHT := 16.0
const PANEL_PAD := 18.0
const BUTTON_ICON: Texture2D = preload("res://ui/icons/flag.png")

var camera: Camera3D = null
## The level being played ("paths", "castle"): the compass is drawn from it.
var level: Dictionary = {}

var _points: Array[Vector3] = []
var _left: float = 0.0
var _age: float = 0.0
## Portals of the level and the indices of the roads the current wave uses.
var _portals: Array[Node3D] = []
var _lanes: Array[int] = []
## Side text per active lane ("From the north!"), same order as _lanes.
var _lane_texts: Array[String] = []
var _arrow_left: float = 0.0
var _arrow_age: float = 0.0
var _compass_left: float = 0.0
var _pinned: bool = false
var _stopped: bool = false
## The roads of the level in screen orientation, fitted to the compass panel (0..1 box).
var _compass_routes: Array[PackedVector2Array] = []
var _compass_built_for: int = -1
var _panel_style: StyleBoxFlat = null
var _button: Button = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.07, 0.09, 0.2, 0.74)
	_panel_style.border_color = Color(0.85, 0.88, 1.0, 0.55)
	_panel_style.set_border_width_all(2)
	_panel_style.set_corner_radius_all(14)
	_button = Button.new()
	_button.name = "CompassButton"
	_button.focus_mode = Control.FOCUS_NONE
	_button.custom_minimum_size = Vector2(72.0, 64.0)
	_button.size = Vector2(72.0, 64.0)
	_button.icon = BUTTON_ICON
	_button.expand_icon = true
	_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button.add_theme_constant_override("icon_max_width", 40)
	_button.tooltip_text = tr("LANES_COMPASS")
	_button.pressed.connect(toggle_compass)
	add_child(_button)
	_place_button()
	resized.connect(_place_button)


func _process(delta: float) -> void:
	var busy: bool = false
	if _left > 0.0:
		_left -= delta
		busy = true
	if _arrow_left > 0.0:
		_arrow_left -= delta
		_arrow_age += delta
		busy = true
	if _compass_left > 0.0:
		_compass_left -= delta
		busy = true
	_age += delta
	if busy or _pinned:
		queue_redraw()


## Marks the given world points (portal positions) with rings for `seconds`.
func show_points(points: Array[Vector3], seconds: float = SHOW_SECONDS) -> void:
	_points = points
	_left = seconds
	_age = 0.0
	show()
	queue_redraw()


## A wave starts on the paths `lanes`: the portals pulse, rings mark the ones on screen, an
## arrow on the screen edge points to every one of these roads for the whole wave and the
## compass opens for a moment.
func announce(portals: Array[Node3D], lanes: Array) -> void:
	_portals = portals
	var points: Array[Vector3] = []
	_lanes.clear()
	_lane_texts.clear()
	for lane: int in lanes:
		var portal: Node3D = portals[lane]
		points.append(portal.global_position + Vector3.UP * 0.6)
		var tween: Tween = portal.create_tween()
		for i in 3:
			tween.tween_property(portal, "scale", Vector3.ONE * 1.3, 0.25)
			tween.tween_property(portal, "scale", Vector3.ONE, 0.25)
		_lanes.append(lane)
		_lane_texts.append(
			LevelCatalog.direction_text(level, [lane]) if not level.is_empty() else ""
		)
	_arrow_left = ARROW_SECONDS if not _lanes.is_empty() else 0.0
	_arrow_age = 0.0
	_compass_left = COMPASS_SECONDS if not _lanes.is_empty() else 0.0
	_stopped = false
	show_points(points)


## The wave is over (its enemies are gone): the edge arrows and the compass close.
func finish() -> void:
	_arrow_left = 0.0
	_compass_left = 0.0
	_lanes.clear()
	_lane_texts.clear()
	queue_redraw()


## The battle is over: nothing is drawn any more.
func stop() -> void:
	_stopped = true
	_pinned = false
	finish()
	_left = 0.0
	_button.hide()
	queue_redraw()


## The button: the compass stays open until pressed again.
func toggle_compass() -> void:
	_pinned = not _pinned
	show()
	queue_redraw()


## True while the rings are shown.
func is_active() -> bool:
	return _left > 0.0


## True while the edge arrows are shown (the wave is on).
func arrows_active() -> bool:
	return _arrow_left > 0.0 and not _lanes.is_empty()


## True while the compass is on screen.
func compass_visible() -> bool:
	return not _stopped and (_pinned or _compass_left > 0.0) and not level.is_empty()


func _place_button() -> void:
	if _button == null:
		return
	var safe: Vector4 = ScreenUtil.safe_margins(get_viewport())
	_button.position = Vector2(size.x - safe.z - PANEL_RIGHT - _button.size.x, 100.0 + safe.y)


func _draw() -> void:
	if camera == null or _stopped:
		return
	var safe: Vector4 = ScreenUtil.safe_margins(get_viewport())
	if _left > 0.0:
		_draw_rings(safe)
	if _arrow_left > 0.0 and not _lanes.is_empty():
		_draw_edge_arrows(safe)
	if compass_visible():
		_draw_compass(safe)


func _draw_rings(safe: Vector4) -> void:
	var alpha: float = clampf(_left, 0.0, 1.0)
	var pulse: float = 0.5 + 0.5 * sin(_age * 7.0)
	var area: Rect2 = _arrow_area(safe)
	for point: Vector3 in _points:
		if camera.is_position_behind(point):
			continue
		var screen: Vector2 = camera.unproject_position(point)
		if area.has_point(screen):
			_draw_ring(screen, pulse, alpha)


func _draw_ring(at: Vector2, pulse: float, alpha: float) -> void:
	var radius: float = RING_RADIUS + 8.0 * pulse
	draw_arc(at, radius, 0.0, TAU, 40, Color(OUTLINE, alpha), 9.0, true)
	draw_arc(at, radius, 0.0, TAU, 40, Color(COLOR, alpha), 5.0, true)


## The part of the screen the edge arrows may use.
func _arrow_area(safe: Vector4) -> Rect2:
	var left: float = EDGE_MARGINS.x + safe.x
	var top: float = EDGE_MARGINS.y + safe.y
	var right: float = EDGE_MARGINS.z + safe.z
	var bottom: float = EDGE_MARGINS.w + safe.w
	return Rect2(Vector2(left, top), size - Vector2(left + right, top + bottom))


func _draw_edge_arrows(safe: Vector4) -> void:
	var area: Rect2 = _arrow_area(safe)
	# Blinks fast while the wave is new, then slower and a little dimmer.
	var fresh: bool = _arrow_age < SHOW_SECONDS
	var blink: float = 0.5 + 0.5 * sin(_arrow_age * (9.0 if fresh else 4.0))
	var alpha: float = lerpf(0.55, 1.0, blink) if fresh else lerpf(0.5, 0.85, blink)
	alpha *= clampf(_arrow_left, 0.0, 1.0)
	var labelled: Array[String] = []
	for i in _lanes.size():
		var portal: Node3D = _portals[_lanes[i]]
		var world: Vector3 = portal.global_position + Vector3.UP * 0.6
		var screen: Vector2 = camera.unproject_position(world)
		var tip: Vector2 = _draw_edge_arrow(area, screen, blink, alpha)
		if tip != Vector2.INF and _lane_texts[i] != "" and not labelled.has(_lane_texts[i]):
			labelled.append(_lane_texts[i])
			_draw_label(_lane_texts[i], tip, area, alpha)


## Draws one arrow towards `target` on the border of `area`; returns its tip.
func _draw_edge_arrow(area: Rect2, target: Vector2, pulse: float, alpha: float) -> Vector2:
	var centre: Vector2 = area.get_center()
	var dir: Vector2 = target - centre
	if dir.length() < 1.0:
		return Vector2.INF
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
	return tip


## The side's name next to an arrow, kept inside the screen.
func _draw_label(text: String, tip: Vector2, area: Rect2, alpha: float) -> void:
	var font: Font = get_theme_default_font()
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
	var centre: Vector2 = area.get_center()
	var inward: Vector2 = (centre - tip).normalized()
	var spot: Vector2 = tip + inward * (ARROW_SIZE * 2.4 + LABEL_SIZE * 0.6)
	var left: float = clampf(spot.x - width * 0.5, 8.0, maxf(size.x - width - 8.0, 8.0))
	var baseline: float = clampf(spot.y + LABEL_SIZE * 0.35, LABEL_SIZE + 4.0, size.y - 8.0)
	var at := Vector2(left, baseline)
	draw_string_outline(
		font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, 7, Color(OUTLINE, alpha)
	)
	draw_string(
		font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, Color(1, 0.9, 0.7, alpha)
	)


# --- compass ------------------------------------------------------------------


func _draw_compass(safe: Vector4) -> void:
	_build_compass()
	if _compass_routes.is_empty():
		return
	var fade: float = 1.0
	if not _pinned:
		fade = clampf(_compass_left, 0.0, 1.0)
	var origin := Vector2(size.x - safe.z - PANEL_RIGHT - PANEL_SIZE.x, PANEL_TOP + safe.y)
	var panel := Rect2(origin, PANEL_SIZE)
	_panel_style.bg_color.a = 0.74 * fade
	_panel_style.border_color.a = 0.55 * fade
	draw_style_box(_panel_style, panel)
	var inner := Rect2(origin + Vector2.ONE * PANEL_PAD, PANEL_SIZE - Vector2.ONE * PANEL_PAD * 2.0)
	var pulse: float = 0.5 + 0.5 * sin(_age * 6.0)
	# Dim roads first, the roads of this wave on top.
	for pass_index in 2:
		for lane in _compass_routes.size():
			var lit: bool = _lanes.has(lane)
			if lit != (pass_index == 1):
				continue
			var points := PackedVector2Array()
			for p: Vector2 in _compass_routes[lane]:
				points.append(inner.position + p * inner.size)
			if lit:
				var glow: Color = Color(COLOR, fade * (0.75 + 0.25 * pulse))
				draw_polyline(points, Color(OUTLINE, fade), 9.0, true)
				draw_polyline(points, glow, 6.0, true)
				draw_circle(points[0], 7.0 + 2.5 * pulse, glow)
			else:
				draw_polyline(points, Color(MUTED, MUTED.a * fade), 4.0, true)
				draw_circle(points[0], 4.0, Color(MUTED, MUTED.a * fade))
	# The castle at the end of the first road.
	var gate: Vector2 = (
		inner.position + _compass_routes[0][_compass_routes[0].size() - 1] * inner.size
	)
	var castle := Rect2(gate - Vector2(8.0, 8.0), Vector2(16.0, 16.0))
	draw_rect(castle.grow(2.0), Color(0.98, 0.8, 0.4, fade))
	draw_rect(castle, Color(0.35, 0.5, 0.95, fade))


## Roads of the level seen from above in screen orientation (up = the top of the screen),
## fitted into the 0..1 box of the compass panel with the aspect ratio kept.
func _build_compass() -> void:
	var id: int = int(level.get("id", 0))
	if _compass_built_for == id:
		return
	_compass_built_for = id
	_compass_routes.clear()
	if level.is_empty():
		return
	var flat: Array[PackedVector2Array] = []
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for route: PackedVector2Array in LevelCatalog.routes(level):
		var turned := PackedVector2Array()
		for p: Vector2 in route:
			var q := Vector2(p.dot(LevelCatalog.SCREEN_RIGHT), -p.dot(LevelCatalog.SCREEN_UP))
			turned.append(q)
			low = low.min(q)
			high = high.max(q)
		flat.append(turned)
	var extent: Vector2 = (high - low).max(Vector2.ONE)
	var inner: Vector2 = PANEL_SIZE - Vector2.ONE * PANEL_PAD * 2.0
	var scale: float = minf(inner.x / extent.x, inner.y / extent.y)
	var used: Vector2 = extent * scale
	var shift: Vector2 = (inner - used) * 0.5
	for route: PackedVector2Array in flat:
		var fitted := PackedVector2Array()
		for q: Vector2 in route:
			fitted.append(((q - low) * scale + shift) / inner)
		_compass_routes.append(fitted)
