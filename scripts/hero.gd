class_name Hero
extends CharacterBody3D
## The guardian knight. Walks with the move_* actions (WASD, arrows, gamepad),
## the on-screen joystick, or by order (walk to a point, then run a callback).
## Directions are relative to the camera: "up" walks up the screen.
## The attack action swings the sword: it hurts enemies in front and chops
## trees for wood. Standing still next to an enemy or a tree swings by itself
## (auto_action), so on a phone walking up to a tree is enough to chop it.

## Emitted when an order's destination is reached (before its callback runs).
signal order_finished
## Emitted when an order is dropped (player took control or the way is blocked).
signal order_cancelled
## Emitted when a sword hit chops wood off a tree.
signal wood_gathered(amount: int, at: Vector3)

## Metres per second.
@export var speed: float = 3.2
## Radians per second the model turns towards the walking direction.
@export var turn_speed: float = 12.0
## Seconds without progress after which an order gives up (blocked path).
@export var stuck_timeout: float = 1.5

@export_group("Attack")
@export var attack_damage: float = 14.0
## Reach of the sword from the hero's centre (metres).
@export var attack_range: float = 1.4
## Trees are hit from a little further away (their trunk is thick).
@export var chop_range: float = 1.6
@export var attack_cooldown: float = 0.5
## Delay from the start of the swing to the moment the blade hits.
@export var attack_hit_delay: float = 0.2
## Targets this far away turn the hero towards them before the swing.
@export var auto_aim_range: float = 2.4
## Cosine of the half-angle of the hit cone in front of the hero.
@export var attack_cone: float = 0.2
## Swing on its own at enemies/trees in reach while standing still.
@export var auto_action: bool = true

## Set by the on-screen joystick (length 0..1).
var joystick_vector: Vector2 = Vector2.ZERO
## Walkable grid for orders; without it the hero walks in a straight line.
var walk_grid: WalkGrid = null

var _has_order: bool = false
var _order_target: Vector3 = Vector3.ZERO
## Remaining corners of the route to _order_target (the target is last).
var _waypoints: PackedVector3Array = PackedVector3Array()
var _order_reach: float = 0.1
var _on_arrive: Callable = Callable()
var _stuck_time: float = 0.0
var _last_distance: float = INF
var _cooldown_left: float = 0.0
var _attack_left: float = 0.0

@onready var _model: Node3D = $Model
@onready var _anim: AnimationPlayer = $Model/AnimationPlayer
@onready var _swing_sound: AudioStreamPlayer3D = $SwingSound
@onready var _chop_sound: AudioStreamPlayer3D = $ChopSound


func _ready() -> void:
	for anim_name: StringName in [&"idle", &"walk"]:
		_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_anim.play(&"idle")


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_attack_left = maxf(_attack_left - delta, 0.0)
	if Input.is_action_just_pressed(&"attack"):
		try_attack()
	var input: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	input = (input + joystick_vector).limit_length(1.0)
	var direction := Vector3.ZERO
	if input.length() > 0.1:
		if _has_order:
			cancel_order()
		direction = _screen_to_world(input)
	elif _has_order:
		direction = _order_direction(delta)
	if auto_action and direction == Vector3.ZERO and _cooldown_left <= 0.0 and get_focus_target(true) != null:
		try_attack()
	if _attack_left > 0.0:
		direction *= 0.3  # plant the feet while swinging
	velocity = direction * speed
	move_and_slide()
	position.y = 0.0
	_animate(direction, delta)


## Walk to `target` until within `reach` metres, then call `on_arrive`.
func move_to(target: Vector3, reach: float = 0.1, on_arrive: Callable = Callable()) -> void:
	_has_order = true
	_order_target = Vector3(target.x, 0.0, target.z)
	_waypoints = walk_grid.find_path(global_position, _order_target) if walk_grid else PackedVector3Array()
	if not _waypoints.is_empty():
		_waypoints.remove_at(_waypoints.size() - 1)  # the target itself is handled below
	_order_reach = reach
	_on_arrive = on_arrive
	_stuck_time = 0.0
	_last_distance = INF


## Swings the sword unless it is still cooling down. Returns true on a swing.
func try_attack() -> bool:
	if _cooldown_left > 0.0:
		return false
	cancel_order()
	_cooldown_left = attack_cooldown
	_attack_left = _anim.get_animation(&"attack").length
	var target: Node3D = _nearest_target(auto_aim_range)
	if target != null:
		var offset: Vector3 = target.global_position - global_position
		_model.rotation.y = atan2(offset.x, offset.z)
	_anim.play(&"attack", 0.05)
	_anim.speed_scale = 1.0
	_swing_sound.play()
	get_tree().create_timer(attack_hit_delay, false).timeout.connect(_strike)
	return true


## What a swing would hit now: the nearest living enemy in sword reach, else
## the nearest choppable tree in chop reach (null if none). With `strict`
## false the reach is a little longer, for showing the target ahead of time.
func get_focus_target(strict: bool = false) -> Node3D:
	var slack: float = 0.0 if strict else 0.5
	var best: Node3D = null
	var best_distance: float = attack_range + slack
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var d: float = _flat_distance(node as Node3D)
		if (node as Enemy).is_alive() and d < best_distance:
			best_distance = d
			best = node as Node3D
	if best != null:
		return best
	best_distance = chop_range + slack
	for node: Node in get_tree().get_nodes_in_group(WoodTree.GROUP):
		var tree := node as WoodTree
		var d: float = _flat_distance(tree)
		if tree.is_choppable() and d < best_distance:
			best_distance = d
			best = tree
	return best


func is_attacking() -> bool:
	return _attack_left > 0.0


func cancel_order() -> void:
	if not _has_order:
		return
	_has_order = false
	_on_arrive = Callable()
	_waypoints.clear()
	order_cancelled.emit()


func has_order() -> bool:
	return _has_order


func is_near(point: Vector3, reach: float) -> bool:
	var offset: Vector3 = point - global_position
	offset.y = 0.0
	return offset.length() <= reach


func _strike() -> void:
	var forward := Vector3(sin(_model.rotation.y), 0.0, cos(_model.rotation.y))
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy.is_alive() and _in_cone(enemy.global_position, forward, attack_range):
			enemy.take_damage(attack_damage)
	var chopped := false
	for node: Node in get_tree().get_nodes_in_group(WoodTree.GROUP):
		var tree := node as WoodTree
		if tree.is_choppable() and _in_cone(tree.global_position, forward, chop_range):
			var wood: int = tree.chop(global_position)
			if wood > 0:
				chopped = true
				wood_gathered.emit(wood, tree.global_position)
	if chopped:
		_chop_sound.play()


func _in_cone(point: Vector3, forward: Vector3, reach: float) -> bool:
	var offset: Vector3 = point - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance > reach:
		return false
	return distance < 0.3 or forward.dot(offset / distance) >= attack_cone


## Nearest living enemy, or else choppable tree, within `reach`.
func _nearest_target(reach: float) -> Node3D:
	var best: Node3D = null
	var best_distance: float = reach
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var d: float = _flat_distance(node as Node3D)
		if d < best_distance:
			best_distance = d
			best = node as Node3D
	if best != null:
		return best
	best_distance = reach
	for node: Node in get_tree().get_nodes_in_group(WoodTree.GROUP):
		var tree := node as WoodTree
		var d: float = _flat_distance(tree)
		if tree.is_choppable() and d < best_distance:
			best_distance = d
			best = tree
	return best


func _flat_distance(node: Node3D) -> float:
	var offset: Vector3 = node.global_position - global_position
	offset.y = 0.0
	return offset.length()


func _order_direction(delta: float) -> Vector3:
	# Follow the route corners first.
	while not _waypoints.is_empty():
		var corner: Vector3 = _waypoints[0] - global_position
		corner.y = 0.0
		if corner.length() > 0.2:
			_track_progress(corner.length() + _route_rest(), delta)
			if not _has_order:
				return Vector3.ZERO
			return corner.normalized()
		_waypoints.remove_at(0)
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
	_track_progress(distance, delta)
	if not _has_order:
		return Vector3.ZERO
	return offset / distance


## Gives up the order when sliding along an obstacle does not bring us closer.
func _track_progress(distance: float, delta: float) -> void:
	if distance < _last_distance - 0.01:
		_last_distance = distance
		_stuck_time = 0.0
	else:
		_stuck_time += delta
		if _stuck_time > stuck_timeout:
			cancel_order()


## Length of the route after the next corner.
func _route_rest() -> float:
	var total: float = 0.0
	var prev: Vector3 = _waypoints[0]
	for i in range(1, _waypoints.size()):
		total += prev.distance_to(_waypoints[i])
		prev = _waypoints[i]
	return total + prev.distance_to(_order_target)


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
	if _attack_left > 0.0:
		return
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
