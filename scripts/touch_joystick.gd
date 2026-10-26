class_name TouchJoystick
extends Control
## On-screen floating dynamic joystick for touch devices. Reports a vector of length 0..1.
## Uses touch events (multi-touch safe: the stick keeps its own finger while
## another finger presses HUD buttons).
## When touched within the joystick zone (the home place of the stick and a margin around it,
## never more than ZONE_MAX_WIDTH of the screen), the base centers at the touch position,
## and returns to its home position when released. The rest of the screen stays free for the
## camera (pinch zoom) and taps (playtest 2026-10-24: a zone of half the screen ate the pinch).

signal vector_changed(vector: Vector2)

## The touch zone is the home rect grown by this share of its side on every side.
const ZONE_GROW := 0.5
## ... and never wider than this share of the screen from its own edge.
const ZONE_MAX_WIDTH := 0.38

@export var radius: float = 80.0
@export var force_visible: bool = false
@export var floating: bool = true

var base_position: Vector2:
	get:
		return _base_position
	set(v):
		_base_position = v
		_base_set = true
var base_center: Vector2:
	get:
		return global_position + size * 0.5

var _touch_index: int = -1
var _center: Vector2
var _knob: Vector2
var _base_position: Vector2 = Vector2.ZERO
var _base_set: bool = false


func _ready() -> void:
	visible = force_visible or OS.has_feature("mobile")
	_center = size / 2.0
	_knob = _center
	reset_base_position.call_deferred()


func reset_base_position() -> void:
	_base_position = global_position
	_base_set = true
	_center = size / 2.0
	if _touch_index == -1:
		_knob = _center


func get_base_center() -> Vector2:
	return global_position + size * 0.5


func _is_over_ui(pos: Vector2) -> bool:
	var hud_root: Control = get_parent() as Control
	if hud_root == null:
		return false
	while hud_root.get_parent() is Control:
		hud_root = hud_root.get_parent() as Control
	return _control_hits_ui(hud_root, pos)


func _control_hits_ui(c: Control, pos: Vector2) -> bool:
	if c == self or not c.visible:
		return false
	if c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		if (
			c is BaseButton
			or c is PanelContainer
			or c is Panel
			or c is LineEdit
			or c is Tree
			or c is ItemList
			or c is Slider
		):
			if c.get_global_rect().has_point(pos):
				return true
	for child in c.get_children():
		if child is Control and _control_hits_ui(child, pos):
			return true
	return false


func is_in_zone(pos: Vector2) -> bool:
	if not is_inside_tree() or (OS.has_feature("mobile") and not visible):
		return false
	if _is_over_ui(pos):
		return false
	if Rect2(global_position, size).has_point(pos):
		return true
	if pos.y < 72.0:
		return false
	return zone().has_point(pos)


## Where a touch grabs the stick: around its home place, not half of the screen.
func zone() -> Rect2:
	var home := Rect2(_base_position if _base_set else global_position, size)
	var area: Rect2 = home.grow(maxf(size.x, size.y) * ZONE_GROW)
	var vp_size: Vector2 = get_viewport_rect().size
	var limit: float = vp_size.x * ZONE_MAX_WIDTH
	if GameSettings.joystick_side() == HudLayout.SIDE_RIGHT:
		area = area.intersection(Rect2(vp_size.x - limit, 0.0, limit, vp_size.y))
	else:
		area = area.intersection(Rect2(0.0, 0.0, limit, vp_size.y))
	return area


func _input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	if OS.has_feature("mobile") and not visible:
		return
	var touch := event as InputEventScreenTouch
	if touch:
		if touch.pressed and _touch_index == -1:
			if is_in_zone(touch.position):
				_touch_index = touch.index
				_on_touch_down(touch.position)
				get_viewport().set_input_as_handled()
		elif not touch.pressed and touch.index == _touch_index:
			_release()
			get_viewport().set_input_as_handled()
		return
	var drag := event as InputEventScreenDrag
	if drag and drag.index == _touch_index:
		_move_knob(drag.position - global_position)
		get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed and _touch_index == -1:
			if is_in_zone(mb.position):
				_touch_index = 999
				_on_touch_down(mb.position)
				get_viewport().set_input_as_handled()
		elif not mb.pressed and _touch_index == 999:
			_release()
			get_viewport().set_input_as_handled()
		return
	var mm := event as InputEventMouseMotion
	if mm and _touch_index == 999:
		_move_knob(mm.position - global_position)
		get_viewport().set_input_as_handled()
		return


func _gui_input(event: InputEvent) -> void:
	# Fallback if an event arrives via GUI
	if not event.is_echo():
		_input(event)


func _notification(what: int) -> void:
	# A finger lifted while hidden or paused never reaches _gui_input / _input: let go.
	var hidden: bool = what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()
	if (hidden or what == NOTIFICATION_APPLICATION_FOCUS_OUT) and _touch_index != -1:
		_release()
	if what == NOTIFICATION_RESIZED:
		_center = size / 2.0
		if _touch_index == -1:
			_knob = _center
			if not _base_set or _base_position == Vector2.ZERO:
				_base_position = global_position
				_base_set = true


func _on_touch_down(touch_pos: Vector2) -> void:
	if not _base_set or _base_position == Vector2.ZERO:
		_base_position = global_position
		_base_set = true
	if floating:
		global_position = touch_pos - size * 0.5
	_center = size * 0.5
	_knob = _center
	vector_changed.emit(Vector2.ZERO)
	queue_redraw()


func _move_knob(local: Vector2) -> void:
	var offset: Vector2 = (local - _center).limit_length(radius)
	_knob = _center + offset
	vector_changed.emit(offset / radius)
	queue_redraw()


func _release() -> void:
	_touch_index = -1
	if _base_set:
		global_position = _base_position
	_center = size * 0.5
	_knob = _center
	vector_changed.emit(Vector2.ZERO)
	queue_redraw()


func _draw() -> void:
	var ring := Color(0.07, 0.11, 0.27)
	draw_circle(_center, radius, Color(0.11, 0.16, 0.36, 0.5))
	draw_arc(_center, radius, 0.0, TAU, 48, ring, 8.0, true)
	draw_arc(_center, radius, 0.0, TAU, 48, Color(0.98, 0.78, 0.3, 0.95), 4.0, true)
	var knob_r: float = radius * 0.42
	draw_circle(_knob + Vector2(0.0, 5.0), knob_r + 3.0, Color(0.03, 0.05, 0.15, 0.4))
	draw_circle(_knob, knob_r + 4.0, ring)
	draw_circle(_knob, knob_r, Color(0.96, 0.7, 0.2))
	draw_circle(_knob - Vector2(0.0, knob_r * 0.18), knob_r * 0.74, Color(1.0, 0.86, 0.4))
	draw_arc(
		_knob,
		knob_r * 0.62,
		deg_to_rad(200.0),
		deg_to_rad(290.0),
		12,
		Color(1, 1, 1, 0.7),
		4.0,
		true
	)
