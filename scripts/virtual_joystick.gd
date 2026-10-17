extends Control
## On-screen joystick for touch devices. Reports a vector of length 0..1.
## Uses touch events (multi-touch safe: the stick keeps its own finger while
## another finger presses HUD buttons). Shown on mobile builds only: on desktop
## DisplayServer reports a touchscreen whenever mouse-to-touch emulation is on.

signal vector_changed(vector: Vector2)

@export var radius: float = 80.0
@export var force_visible: bool = false

var _touch_index: int = -1
var _center: Vector2
var _knob: Vector2


func _ready() -> void:
	visible = force_visible or OS.has_feature("mobile")
	_center = size / 2.0
	_knob = _center


func _gui_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch:
		if touch.pressed and _touch_index == -1:
			_touch_index = touch.index
			_move_knob(touch.position)
			accept_event()
		elif not touch.pressed and touch.index == _touch_index:
			_release()
			accept_event()
		return
	var drag := event as InputEventScreenDrag
	if drag and drag.index == _touch_index:
		_move_knob(drag.position)
		accept_event()
	elif event is InputEventMouseButton:
		accept_event()  # emulated mouse from the same finger must not reach the map


func _notification(what: int) -> void:
	# A finger lifted while hidden or paused never reaches _gui_input: let go.
	var hidden: bool = what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()
	if (hidden or what == NOTIFICATION_APPLICATION_FOCUS_OUT) and _touch_index != -1:
		_release()
	if what == NOTIFICATION_RESIZED:
		_center = size / 2.0
		if _touch_index == -1:
			_knob = _center


func _move_knob(local: Vector2) -> void:
	var offset: Vector2 = (local - _center).limit_length(radius)
	_knob = _center + offset
	vector_changed.emit(offset / radius)
	queue_redraw()


func _release() -> void:
	_touch_index = -1
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
	draw_arc(_knob, knob_r * 0.62, deg_to_rad(200.0), deg_to_rad(290.0), 12, Color(1, 1, 1, 0.7), 4.0, true)
