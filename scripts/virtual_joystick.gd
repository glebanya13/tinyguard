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
	draw_circle(_center, radius, Color(0.11, 0.16, 0.31, 0.45))
	draw_arc(_center, radius, 0.0, TAU, 48, Color(0.91, 0.71, 0.3, 0.8), 3.0, true)
	draw_circle(_knob, radius * 0.42, Color(0.95, 0.73, 0.29, 0.9))
	draw_arc(_knob, radius * 0.42, 0.0, TAU, 32, Color(0.66, 0.45, 0.12, 1.0), 3.0, true)
