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
@export var max_size: float = 24.0
## Size change per mouse wheel notch.
@export var wheel_factor: float = 1.1
## Multiplier of camera size in strategic view (45% zoom out).
@export var strategic_zoom_factor: float = 1.45

var strategic_view: bool = false
var flyover_active: bool = false

var _offset: Vector3
## Active touches not taken by the HUD: index -> position.
var _touches: Dictionary = {}
var _pinched: bool = false
var _pinch_distance: float = 0.0
var _default_size: float = 18.0
var _normal_size: float = 18.0
var _target_size: float = 18.0
var _flyover_waypoints: Array[Vector3] = []
var _flyover_progress: float = 0.0
var _flyover_duration: float = 6.0


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
	if flyover_active:
		stop_flyover()
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


## Starts a smooth tactical flyover along spawns towards castle before wave 1.
func start_flyover(spawns: Array[Vector3], castle_pos: Vector3, duration: float = 6.0) -> void:
	if spawns.is_empty():
		return
	_flyover_waypoints.clear()
	for s: Vector3 in spawns:
		_flyover_waypoints.append(Vector3(s.x, 0.0, s.z))
	_flyover_waypoints.append(Vector3(castle_pos.x, 0.0, castle_pos.z))
	_flyover_duration = maxf(duration, 2.0)
	_flyover_progress = 0.0
	flyover_active = true
	var start_focus: Vector3 = _clamp_bounds(_flyover_waypoints[0])
	global_position = start_focus + _offset


func stop_flyover() -> void:
	if not flyover_active:
		return
	flyover_active = false
	_flyover_waypoints.clear()


func _process_flyover(delta: float) -> void:
	if _flyover_waypoints.size() < 2 or _flyover_duration <= 0.0:
		stop_flyover()
		return
	_flyover_progress += delta / _flyover_duration
	if _flyover_progress >= 1.0:
		stop_flyover()
		return
	var seg_count: int = _flyover_waypoints.size() - 1
	var total_t: float = _flyover_progress * float(seg_count)
	var seg_idx: int = clampi(floori(total_t), 0, seg_count - 1)
	var seg_t: float = total_t - float(seg_idx)
	# Smoothstep curve for pleasant motion
	seg_t = seg_t * seg_t * (3.0 - 2.0 * seg_t)
	var from_pt: Vector3 = _flyover_waypoints[seg_idx]
	var to_pt: Vector3 = _flyover_waypoints[seg_idx + 1]
	var current_focus: Vector3 = _clamp_bounds(from_pt.lerp(to_pt, seg_t))
	var goal: Vector3 = current_focus + _offset
	global_position = global_position.lerp(goal, 1.0 - exp(-smoothing * delta))


## Jump to the target without smoothing (after the level moved it).
func snap() -> void:
	if target:
		global_position = _focus() + _offset


# Physics frames, like the hero: following him at render rate made the view
# jitter when frame and physics ticks drift apart.
func _physics_process(delta: float) -> void:
	if absf(size - _target_size) > 0.01:
		size = lerpf(size, _target_size, 1.0 - exp(-smoothing * delta))

	if flyover_active:
		_process_flyover(delta)
		return

	if target == null:
		return
	var goal: Vector3 = _focus() + _offset
	global_position = global_position.lerp(goal, 1.0 - exp(-smoothing * delta))


func _unhandled_input(event: InputEvent) -> void:
	if flyover_active and (event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton):
		stop_flyover()

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


func _focus() -> Vector3:
	return _clamp_bounds(target.global_position)


func _clamp_bounds(p: Vector3) -> Vector3:
	return Vector3(
		clampf(p.x, bounds.position.x, bounds.end.x),
		0.0,
		clampf(p.z, bounds.position.y, bounds.end.y)
	)
