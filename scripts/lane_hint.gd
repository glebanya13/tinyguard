class_name LaneHint
extends Control
## Where the current wave comes from, shown globally and not only at the portal:
##  - for a few seconds a pulsing ring over a portal that is on screen;
##  - for the whole wave an arrow on the screen edge towards every road the wave uses,
##    on screen or not, blinking, with the side written next to it ("From the north!");
##  - a compass in the corner (the map from above, see LaneMap: the castle, the roads of
##    this wave lit and pulsing, the others dim, the portals on the rim with the side written)
##    that opens with every wave for a few seconds and
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
const PANEL_ALPHA := 0.72
const ROAD_DIM := Color(0.74, 0.8, 0.94, 0.6)
const BUTTON_ICON: Texture2D = preload("res://ui/icons/compass.png")

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
var _map := LaneMap.new()
var _panel_style: StyleBoxFlat = null
var _button: Button = null
## Compass mode from the settings (GameSettings): see apply_settings().
var _mode: int = HudLayout.MAP_WAVE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.07, 0.1, 0.26, PANEL_ALPHA)
	_panel_style.border_color = Color(0.96, 0.72, 0.24, 0.75)
	_panel_style.set_border_width_all(2)
	_panel_style.set_corner_radius_all(8)
	_button = Button.new()
	_button.name = "CompassButton"
	_button.focus_mode = Control.FOCUS_NONE
	_button.custom_minimum_size = HudLayout.PIN_SIZE
	_button.size = HudLayout.PIN_SIZE
	_button.theme_type_variation = &"SecondaryButton"
	_button.icon = BUTTON_ICON
	_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button.add_theme_constant_override("icon_max_width", 48)
	_button.tooltip_text = tr("LANES_COMPASS")
	_button.pressed.connect(toggle_compass)
	add_child(_button)
	apply_settings()
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
	return (
		not _stopped
		and _mode != HudLayout.MAP_HIDE
		and (_pinned or _compass_left > 0.0)
		and not level.is_empty()
	)


## Re-reads the compass size and mode from the settings (the settings dialog calls it live).
func apply_settings() -> void:
	_mode = GameSettings.minimap_mode()
	_pinned = _mode == HudLayout.MAP_SHOW
	if _button != null:
		_button.visible = _mode != HudLayout.MAP_HIDE and not _stopped
	_place_button()
	queue_redraw()


## The panel and the pin button sit in the bottom-left corner (see HudLayout).
func _place_button() -> void:
	if _button == null:
		return
	var r: Dictionary = HudLayout.current(size)
	if r.has("pin"):
		_button.position = (r["pin"] as Rect2).position


func _draw() -> void:
	if camera == null or _stopped:
		return
	var safe: Vector4 = ScreenUtil.safe_margins(get_viewport())
	if _left > 0.0:
		_draw_rings(safe)
	if _arrow_left > 0.0 and not _lanes.is_empty():
		_draw_edge_arrows(safe)
	if compass_visible():
		_draw_compass()


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
	draw_arc(at, radius, 0.0, TAU, 40, Color(OUTLINE, alpha), 9.0)
	draw_arc(at, radius, 0.0, TAU, 40, Color(COLOR, alpha), 5.0)


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
	draw_polyline(shape, Color(OUTLINE, alpha), 4.0)
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


func _draw_compass() -> void:
	var box: Rect2 = HudLayout.current(size)["map"]
	var font: Font = get_theme_default_font()
	_map.build(level, box.size, font)
	if _map.routes.is_empty():
		return
	_map.set_lit(_lanes)
	var fade: float = 1.0
	if not _pinned:
		fade = clampf(_compass_left, 0.0, 1.0)
	var frame := Rect2(box.position + _map.frame.position, _map.frame.size)
	_panel_style.bg_color.a = PANEL_ALPHA * fade
	_panel_style.border_color.a = 0.75 * fade
	draw_style_box(_panel_style, frame)
	# Everything below is cached in the frame's own pixels: nothing is allocated per frame.
	# Order = fewest draw calls: lines, then the textured badges, then the text.
	draw_set_transform(frame.position)
	var pulse: float = 0.5 + 0.5 * sin(_age * 6.0)
	var glow: Color = Color(COLOR, fade * (0.78 + 0.22 * pulse))
	if LaneMap.screen_oriented:
		var field: PackedVector2Array = _map.field_outline()
		field.append(field[0])
		draw_polyline(field, Color(ROAD_DIM, 0.4 * fade), 1.5)
	draw_multiline(_map.dim, Color(ROAD_DIM, ROAD_DIM.a * fade), 4.0)
	if not _map.lit_outline.is_empty():
		draw_multiline(_map.lit_outline, Color(OUTLINE, fade), 10.0)
		draw_multiline(_map.lit_core, glow, 6.0)
		draw_multiline(_map.lit_air, Color(COLOR, 0.9 * fade), 2.5)
	var atlas: Texture2D = LaneMap.atlas()
	# A dark pill behind every side name (the same texture as the dots: no extra draw call).
	for label: Dictionary in _map.labels:
		var pill: Rect2 = (label["rect"] as Rect2).grow_individual(5.0, 1.0, 5.0, 1.0)
		draw_texture_rect_region(
			atlas, pill, LaneMap.DOT_REGION, Color(0.04, 0.06, 0.16, 0.8 * fade)
		)
	for lane in _map.portals.size():
		var at: Vector2 = _map.portals[lane]
		var lit: bool = _lanes.has(lane)
		var radius: float = (6.5 + 2.0 * pulse) if lit else 4.5
		if lit:
			_draw_badge(atlas, LaneMap.DOT_REGION, at, radius + 2.0, Color(OUTLINE, fade))
		_draw_badge(atlas, LaneMap.DOT_REGION, at, radius, glow if lit else Color(ROAD_DIM, fade))
	_draw_badge(
		atlas, LaneMap.CASTLE_REGION, _map.castle, LaneMap.CASTLE_SIZE * 0.5, Color(1, 1, 1, fade)
	)
	for label: Dictionary in _map.labels:
		var rect: Rect2 = label["rect"]
		var color := Color(0.88, 0.91, 1.0, fade)
		if _lanes.has(int(label["lane"])):
			color = Color(1.0, 0.82, 0.5, fade)
		var baseline: Vector2 = rect.position + Vector2(0.0, rect.size.y * 0.8)
		draw_string(
			font,
			baseline,
			str(label["text"]),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			LaneMap.LABEL_SIZE,
			color
		)
	draw_set_transform(Vector2.ZERO)


## One badge of the atlas (all of them share one texture, so they are one draw call).
func _draw_badge(atlas: Texture2D, region: Rect2, at: Vector2, half: float, color: Color) -> void:
	draw_texture_rect_region(
		atlas, Rect2(at - Vector2.ONE * half, Vector2.ONE * half * 2.0), region, color
	)


## Geometry of the compass (public for tests); built for the current panel box.
func compass_map() -> LaneMap:
	_map.build(level, HudLayout.current(size)["map"].size, get_theme_default_font())
	return _map
