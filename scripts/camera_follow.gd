class_name CameraFollow
extends Camera3D
## Fixed isometric camera that follows a target (the hero) with smoothing.
## The look-at point is clamped to `bounds` (XZ) so the view stays on the map.
## Zoom: pinch with two fingers, mouse wheel or trackpad pinch.

@export var target: Node3D
## Higher is snappier.
@export var smoothing: float = 6.0
## Allowed area for the point the camera looks at (x, z, width, depth).
@export var bounds: Rect2 = Rect2(-10, -7, 20, 14)
@export var min_size: float = 7.0
@export var max_size: float = 16.0
## Size change per mouse wheel notch.
@export var wheel_factor: float = 1.1

var _offset: Vector3
## Active touches not taken by the HUD: index -> position.
var _touches: Dictionary = {}
var _pinched: bool = false
var _pinch_distance: float = 0.0


func _ready() -> void:
	# Keep the editor-placed angle: the camera looks at the origin.
	_offset = global_position
	if target:
		global_position = _focus() + _offset


## Jump to the target without smoothing (after the level moved it).
func snap() -> void:
	if target:
		global_position = _focus() + _offset


# Physics frames, like the hero: following him at render rate made the view
# jitter when frame and physics ticks drift apart.
func _physics_process(delta: float) -> void:
	if target == null:
		return
	var goal: Vector3 = _focus() + _offset
	global_position = global_position.lerp(goal, 1.0 - exp(-smoothing * delta))


func _unhandled_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch:
		if touch.pressed:
			if _touches.is_empty():
				_pinched = false
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
		_pinch_distance = _touch_spread()
		return
	var drag := event as InputEventScreenDrag
	if drag and _touches.has(drag.index):
		_touches[drag.index] = drag.position
		if _touches.size() >= 2:
			_pinched = true
			var spread: float = _touch_spread()
			if _pinch_distance > 0.0 and spread > 0.0:
				zoom_by(_pinch_distance / spread)
			_pinch_distance = spread
		return
	var wheel := event as InputEventMouseButton
	if wheel and wheel.pressed:
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.0 / wheel_factor)
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(wheel_factor)
		return
	var magnify := event as InputEventMagnifyGesture
	if magnify:
		zoom_by(1.0 / magnify.factor)


## Forgets active touches (their release may have been lost during a pause).
func reset_touches() -> void:
	_touches.clear()
	_pinch_distance = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset_touches()


## Multiplies the orthographic size (> 1 zooms out).
func zoom_by(factor: float) -> void:
	size = clampf(size * factor, min_size, max_size)


## True if a second finger touched the screen since the first one went down:
## the gesture was a pinch, not a tap.
func is_pinch_gesture() -> bool:
	return _pinched or _touches.size() >= 2


func _touch_spread() -> float:
	if _touches.size() < 2:
		return 0.0
	var points: Array = _touches.values()
	return (points[0] as Vector2).distance_to(points[1])


func _focus() -> Vector3:
	var p: Vector3 = target.global_position
	return Vector3(
		clampf(p.x, bounds.position.x, bounds.end.x),
		0.0,
		clampf(p.z, bounds.position.y, bounds.end.y)
	)
