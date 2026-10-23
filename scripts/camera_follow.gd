class_name CameraFollow
extends Camera3D
## Fixed isometric camera that follows a target (the hero) with smoothing.
## The look-at point is clamped to `bounds` (XZ) so the view stays on the map.
## Zoom: pinch with two fingers, mouse wheel or trackpad pinch.
## Free look (the map inspection before the battle): the camera leaves the hero and the
## player pans it with one finger (or the mouse, or the movement keys).

@export var target: Node3D
## Higher is snappier.
@export var smoothing: float = 6.0
## Allowed area for the point the camera looks at (x, z, width, depth).
@export var bounds: Rect2 = Rect2(-10, -7, 20, 14)
@export var min_size: float = 7.0
@export var max_size: float = 24.0
## Size change per mouse wheel notch.
@export var wheel_factor: float = 1.1
## Multiplier of camera size in strategic view (45% zoom out).
@export var strategic_zoom_factor: float = 1.45
## Free look: panning speed of the movement keys, metres per second.
@export var key_pan_speed: float = 12.0

var strategic_view: bool = false
## The camera looks where the player pans it instead of following the target.
var free_look: bool = false

var _offset: Vector3
## Active touches not taken by the HUD: index -> position.
var _touches: Dictionary = {}
var _pinched: bool = false
var _pinch_distance: float = 0.0
var _default_size: float = 18.0
var _normal_size: float = 18.0
var _target_size: float = 18.0
## Free look: the ground point the camera looks at.
var _free_focus: Vector3 = Vector3.ZERO


func _ready() -> void:
	# Keep the editor-placed angle: the camera looks at the origin.
	_offset = global_position
	_default_size = size
	_normal_size = size
	_target_size = size
	if target:
		global_position = _focus() + _offset


## Toggles strategic view ("General mode") on and off with smooth transition.
func toggle_strategic_view() -> bool:
	set_strategic_view(not strategic_view)
	return strategic_view


func set_strategic_view(on: bool) -> void:
	strategic_view = on
	if strategic_view:
		_target_size = clampf(_default_size * strategic_zoom_factor, min_size, max_size)
	else:
		_target_size = clampf(_default_size, min_size, max_size)


## Resets camera zoom back to the default tactical zoom.
func reset_zoom() -> void:
	strategic_view = false
	_target_size = _default_size


func is_strategic_view() -> bool:
	return strategic_view


## Free look on: the camera stays where it looks now and follows the player's pans;
## off: it glides back to the target.
func set_free_look(on: bool) -> void:
	if on and not free_look:
		_free_focus = _clamp_bounds(global_position - _offset)
	free_look = on


## Free look: moves the point the camera looks at by `delta` (ground metres, XZ).
func pan_by(delta: Vector3) -> void:
	if not free_look:
		return
	_free_focus = _clamp_bounds(_free_focus + Vector3(delta.x, 0.0, delta.z))
	global_position = _free_focus + _offset


## The point on the ground (y = 0) under screen position `screen_pos`.
func ground_at(screen_pos: Vector2) -> Vector3:
	var origin: Vector3 = project_ray_origin(screen_pos)
	var normal: Vector3 = project_ray_normal(screen_pos)
	if absf(normal.y) < 0.001:
		return Vector3(origin.x, 0.0, origin.z)
	return origin + normal * (-origin.y / normal.y)


## Jump to the target without smoothing (after the level moved it).
## In free look the camera looks at the target from there on.
func snap() -> void:
	if target:
		if free_look:
			_free_focus = _focus()
		global_position = _focus() + _offset


# Physics frames, like the hero: following him at render rate made the view
# jitter when frame and physics ticks drift apart.
func _physics_process(delta: float) -> void:
	if absf(size - _target_size) > 0.01:
		size = lerpf(size, _target_size, 1.0 - exp(-smoothing * delta))

	if free_look:
		var keys: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		if keys != Vector2.ZERO:
			pan_by(_screen_to_ground(keys) * key_pan_speed * delta)
		global_position = global_position.lerp(
			_free_focus + _offset, 1.0 - exp(-smoothing * delta)
		)
		return

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
		elif free_look and not _pinched:
			# One finger drags the map: the ground point under it stays under it.
			pan_by(ground_at(drag.position - drag.relative) - ground_at(drag.position))
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
	if strategic_view:
		strategic_view = false
	size = clampf(size * factor, min_size, max_size)
	_normal_size = size
	_target_size = size


## True if a second finger touched the screen since the first one went down:
## the gesture was a pinch, not a tap.
func is_pinch_gesture() -> bool:
	return _pinched or _touches.size() >= 2


func _touch_spread() -> float:
	if _touches.size() < 2:
		return 0.0
	var points: Array = _touches.values()
	return (points[0] as Vector2).distance_to(points[1])


## Screen direction (x right, y down) as a flat ground direction of the same length.
func _screen_to_ground(dir: Vector2) -> Vector3:
	var right: Vector3 = global_transform.basis.x
	var down: Vector3 = -global_transform.basis.y
	right.y = 0.0
	down.y = 0.0
	return (right.normalized() * dir.x + down.normalized() * dir.y).limit_length(1.0)


func _focus() -> Vector3:
	return _clamp_bounds(target.global_position)


func _clamp_bounds(p: Vector3) -> Vector3:
	return Vector3(
		clampf(p.x, bounds.position.x, bounds.end.x),
		0.0,
		clampf(p.z, bounds.position.y, bounds.end.y)
	)
