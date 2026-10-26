class_name BattleMap
extends Panel
## The battle map (the "strategic mode" of the minimap button): the whole field from above over
## the screen, turned like the screen (LaneMap), with the roads, the castle, and circles for the
## towers (with their reach), the knight, the mercenaries and the enemies (bigger for a boss, a
## "!" on those that will reach the castle). The battle goes on under it; a tap anywhere closes
## it. It only draws: the level, the simulation and the knight are handed in. (A Panel, so the
## touch joystick sees it as UI and leaves its taps alone.)

const PANEL_COLOR := Color(0.05, 0.07, 0.18, 0.96)
const FIELD_COLOR := Color(0.2, 0.36, 0.2, 0.55)
const ROAD_COLOR := Color(0.86, 0.74, 0.52, 0.9)
const LIT_COLOR := Color(1.0, 0.66, 0.28)
const OUTLINE := Color(0.06, 0.04, 0.12, 0.95)
const TOWER_COLOR := Color(0.32, 0.62, 1.0)
const TOWER_REACH_COLOR := Color(0.32, 0.62, 1.0, 0.12)
const KNIGHT_COLOR := Color(1.0, 0.84, 0.25)
const MERC_COLOR := Color(0.45, 0.95, 0.85)
const ENEMY_COLOR := Color(0.95, 0.22, 0.22)
const FLYER_COLOR := Color(0.85, 0.4, 1.0)
const BOSS_COLOR := Color(0.75, 0.05, 0.1)
const ALERT_COLOR := Color(0.92, 0.16, 0.14)
const TITLE_SIZE := 30
const TEXT_SIZE := 20
## Room kept for the title above the map and the legend under it (pixels).
const TOP_ROOM := 64.0
const BOTTOM_ROOM := 56.0
const MARGIN := 24.0

## The level being played ("bounds", "paths", "castle").
var level: Dictionary = {}
var sim: Sim = null
var hero: Hero = null
## Enemies the castle alarm points at (LaneHint.threats()).
var threats: Callable = Callable()
## Gate of the mercenaries' tent: their guard area is drawn while any of them lives.
var guard_center: Vector3 = Vector3(INF, 0.0, INF)

var _map := LaneMap.new()
var _age: float = 0.0
## Roads of the waves that are on (lit like on the compass).
var _lanes: Array[int] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	z_index = 5  # over the counters, the banner and the buttons; under the menus (10)
	hide()


func _process(delta: float) -> void:
	if visible:
		_age += delta
		queue_redraw()


## Opens / closes the map; returns true when it is open now.
func toggle() -> bool:
	if visible:
		close()
	else:
		open()
	return visible


func open() -> void:
	_age = 0.0
	show()
	queue_redraw()


func close() -> void:
	hide()


## The roads the current waves use (their lines glow).
func set_lanes(lanes: Array[int]) -> void:
	_lanes = lanes.duplicate()
	_map.set_lit(_lanes)


## Where the map's frame is drawn on the screen (its own pixels start there).
func map_origin() -> Vector2:
	var box: Rect2 = _box()
	return box.position + (box.size - _map.frame.size) * 0.5


## Screen position of a world point (X, Z) on the open map.
func screen_of(world: Vector2) -> Vector2:
	return map_origin() + _map.to_map(world)


func _gui_input(event: InputEvent) -> void:
	var tap := event as InputEventMouseButton
	if tap != null and tap.pressed:
		close()
		accept_event()
		return
	var touch := event as InputEventScreenTouch
	if touch != null and touch.pressed:
		close()
		accept_event()


func _box() -> Rect2:
	var safe: Vector4 = ScreenUtil.safe_margins(get_viewport())
	var left: float = safe.x + MARGIN
	var top: float = safe.y + TOP_ROOM
	return Rect2(
		Vector2(left, top), size - Vector2(left + safe.z + MARGIN, top + safe.w + BOTTOM_ROOM)
	)


func _draw() -> void:
	if level.is_empty():
		return
	var font: Font = get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), PANEL_COLOR)
	var box: Rect2 = _box()
	_map.build(level, box.size, font)
	_map.set_lit(_lanes)
	var origin: Vector2 = map_origin()
	_draw_title(font, box)
	draw_set_transform(origin)
	var field: PackedVector2Array = _map.field_outline()
	draw_colored_polygon(field, FIELD_COLOR)
	field.append(field[0])
	draw_polyline(field, Color(1, 1, 1, 0.35), 2.0)
	draw_multiline(_map.dim, ROAD_COLOR, 8.0)
	if not _map.lit_core.is_empty():
		draw_multiline(_map.lit_core, LIT_COLOR, 8.0)
	for at: Vector2 in _map.portals:
		draw_circle(at, 9.0, OUTLINE)
		draw_circle(at, 6.0, LIT_COLOR)
	var atlas: Texture2D = LaneMap.atlas()
	var half: float = LaneMap.CASTLE_SIZE * 0.8
	draw_texture_rect_region(
		atlas,
		Rect2(_map.castle - Vector2.ONE * half, Vector2.ONE * half * 2.0),
		LaneMap.CASTLE_REGION
	)
	_draw_units()
	draw_set_transform(Vector2.ZERO)
	_draw_legend(font, box)


func _draw_units() -> void:
	if sim == null:
		return
	for tower: Tower in sim.towers:
		if is_instance_valid(tower):
			var at: Vector2 = _at(tower.global_position)
			draw_circle(at, tower.range_m * _map.scale, TOWER_REACH_COLOR)
	for tower: Tower in sim.towers:
		if is_instance_valid(tower):
			_dot(_at(tower.global_position), 8.0, TOWER_COLOR)
	if not sim.mercenaries.is_empty() and guard_center.is_finite():
		var gate: Vector2 = _at(guard_center)
		var reach: float = Mercenary.guard_reach() * _map.scale
		draw_circle(gate, reach, Color(MERC_COLOR, 0.1))
		draw_arc(gate, reach, 0.0, TAU, 48, Color(MERC_COLOR, 0.6), 2.0)
	for merc: Mercenary in sim.mercenaries:
		if is_instance_valid(merc) and merc.is_alive():
			_dot(_at(merc.global_position), 6.0, MERC_COLOR)
	var pulse: float = 0.5 + 0.5 * sin(_age * 6.0)
	for enemy: Enemy in sim.enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var at: Vector2 = _at(enemy.sim_position())
		if enemy.is_boss():
			draw_arc(at, 13.0 + 3.0 * pulse, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 3.0)
			_dot(at, 11.0, BOSS_COLOR)
		else:
			_dot(at, 5.5, FLYER_COLOR if enemy.is_flying() else ENEMY_COLOR)
	if threats.is_valid():
		for enemy: Enemy in threats.call():
			if is_instance_valid(enemy) and enemy.is_alive():
				var at: Vector2 = _at(enemy.sim_position()) + Vector2(0.0, -16.0)
				_dot(at, 9.0 + 2.0 * pulse, ALERT_COLOR)
				_mark(at, "!")
	if hero != null and is_instance_valid(hero):
		var at: Vector2 = _at(hero.global_position)
		draw_circle(at, 13.0, Color(1, 1, 1, 0.95))
		_dot(at, 10.0, KNIGHT_COLOR)


func _at(world: Vector3) -> Vector2:
	return _map.to_map(Vector2(world.x, world.z))


func _dot(at: Vector2, radius: float, color: Color) -> void:
	draw_circle(at, radius + 2.5, OUTLINE)
	draw_circle(at, radius, color)


func _mark(at: Vector2, text: String) -> void:
	var font: Font = get_theme_default_font()
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
	draw_string(
		font,
		at + Vector2(-width * 0.5, TEXT_SIZE * 0.36),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		TEXT_SIZE,
		Color.WHITE
	)


func _draw_title(font: Font, box: Rect2) -> void:
	var title: String = tr("BATTLE_MAP_TITLE")
	var width: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x
	var at := Vector2(box.get_center().x - width * 0.5, box.position.y - 20.0)
	draw_string_outline(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, 8, OUTLINE)
	draw_string(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE, Color(1, 0.9, 0.6))


## Colour key and "tap to close" under the map.
func _draw_legend(font: Font, box: Rect2) -> void:
	var items: Array = [
		[KNIGHT_COLOR, "BATTLE_MAP_KNIGHT"],
		[TOWER_COLOR, "BATTLE_MAP_TOWERS"],
		[MERC_COLOR, "BATTLE_MAP_MERCS"],
		[ENEMY_COLOR, "BATTLE_MAP_ENEMIES"],
		[FLYER_COLOR, "BATTLE_MAP_FLYERS"],
		[BOSS_COLOR, "BATTLE_MAP_BOSS"],
	]
	var texts: Array[String] = []
	var total: float = 0.0
	for item: Array in items:
		var text: String = tr(str(item[1]))
		texts.append(text)
		total += (
			26.0 + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x + 18.0
		)
	var close_text: String = tr("BATTLE_MAP_CLOSE")
	total += font.get_string_size(close_text, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x
	var x: float = maxf(box.get_center().x - total * 0.5, box.position.x)
	var y: float = box.end.y + BOTTOM_ROOM * 0.55
	for i in items.size():
		_dot(Vector2(x + 9.0, y), 8.0, items[i][0])
		x += 26.0
		draw_string(
			font,
			Vector2(x, y + TEXT_SIZE * 0.36),
			texts[i],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			TEXT_SIZE,
			Color(0.92, 0.94, 1.0)
		)
		x += font.get_string_size(texts[i], HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE).x + 18.0
	draw_string(
		font,
		Vector2(x, y + TEXT_SIZE * 0.36),
		close_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		TEXT_SIZE,
		Color(1.0, 0.85, 0.5)
	)
