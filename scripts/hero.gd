class_name Hero
extends CharacterBody3D
## The guardian knight. Walks with the move_* actions (WASD, arrows, gamepad),
## the on-screen joystick, or by order (walk to a point, then run a callback).
## Directions are relative to the camera: "up" walks up the screen.

## Emitted when an order's destination is reached (before its callback runs).
signal order_finished
## Emitted when an order is dropped (player took control or the way is blocked).
signal order_cancelled

## Metres per second.
@export var speed: float = 3.2
## Radians per second the model turns towards the walking direction.
@export var turn_speed: float = 12.0
## Seconds without progress after which an order gives up (blocked path).
@export var stuck_timeout: float = 1.5

## Set by the on-screen joystick (length 0..1).
var joystick_vector: Vector2 = Vector2.ZERO

var _has_order: bool = false
var _order_target: Vector3 = Vector3.ZERO
var _order_reach: float = 0.1
var _on_arrive: Callable = Callable()
var _stuck_time: float = 0.0
var _last_distance: float = INF

@onready var _model: Node3D = $Model
@onready var _anim: AnimationPlayer = $Model/AnimationPlayer


func _ready() -> void:
	for anim_name: StringName in [&"idle", &"walk"]:
		_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_anim.play(&"idle")


func _physics_process(delta: float) -> void:
	var input: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	input = (input + joystick_vector).limit_length(1.0)
	var direction := Vector3.ZERO
	if input.length() > 0.1:
		if _has_order:
			cancel_order()
		direction = _screen_to_world(input)
	elif _has_order:
		direction = _order_direction(delta)
	velocity = direction * speed
	move_and_slide()
	position.y = 0.0
	_animate(direction, delta)


## Walk to `target` until within `reach` metres, then call `on_arrive`.
func move_to(target: Vector3, reach: float = 0.1, on_arrive: Callable = Callable()) -> void:
	_has_order = true
	_order_target = Vector3(target.x, 0.0, target.z)
	_order_reach = reach
	_on_arrive = on_arrive
	_stuck_time = 0.0
	_last_distance = INF


func cancel_order() -> void:
	if not _has_order:
		return
	_has_order = false
	_on_arrive = Callable()
	order_cancelled.emit()


func has_order() -> bool:
	return _has_order


func is_near(point: Vector3, reach: float) -> bool:
	var offset: Vector3 = point - global_position
	offset.y = 0.0
	return offset.length() <= reach


func _order_direction(delta: float) -> Vector3:
	var offset: Vector3 = _order_target - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance <= _order_reach:
		var callback: Callable = _on_arrive
		_has_order = false
		_on_arrive = Callable()
		order_finished.emit()
		if callback.is_valid():
			callback.call()
		return Vector3.ZERO
	# Give up when sliding along an obstacle does not bring us closer.
	if distance < _last_distance - 0.01:
		_last_distance = distance
		_stuck_time = 0.0
	else:
		_stuck_time += delta
		if _stuck_time > stuck_timeout:
			cancel_order()
			return Vector3.ZERO
	return offset / distance


func _screen_to_world(input: Vector2) -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return Vector3(input.x, 0.0, input.y)
	var right: Vector3 = camera.global_transform.basis.x
	var forward: Vector3 = -camera.global_transform.basis.z
	right.y = 0.0
	forward.y = 0.0
	return (right.normalized() * input.x - forward.normalized() * input.y).limit_length(1.0)


func _animate(direction: Vector3, delta: float) -> void:
	if direction.length() > 0.05:
		# The model faces +Z at rest.
		var yaw: float = atan2(direction.x, direction.z)
		_model.rotation.y = rotate_toward(_model.rotation.y, yaw, turn_speed * delta)
		if _anim.current_animation != &"walk":
			_anim.play(&"walk", 0.15)
		_anim.speed_scale = clampf(direction.length(), 0.5, 1.0)
	elif _anim.current_animation != &"idle":
		_anim.play(&"idle", 0.2)
		_anim.speed_scale = 1.0
