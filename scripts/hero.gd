class_name Hero
extends CharacterBody3D
## The guardian knight. Walks with the move_* actions (WASD, arrows, gamepad),
## the on-screen joystick, or by order (walk to a point, then run a callback).
## Directions are relative to the camera: "up" walks up the screen.
## The attack action swings the sword: it hurts enemies in front and chops
## trees for wood. Standing still next to an enemy or a tree swings by itself
## (auto_action), so on a phone walking up to a tree is enough to chop it.
##
## Simulation boundary: the knight's walking (CharacterBody3D, physics) is local
## and not part of the deterministic simulation. What he does to the world
## enters it only as GameCommands: a swing / whirlwind carries his position and
## facing, and the hit itself, cooldowns and wood are resolved in Sim steps.

## Emitted when an order's destination is reached (before its callback runs).
signal order_finished
## Emitted when an order is dropped (player took control or the way is blocked).
signal order_cancelled
## The sword swing / whirlwind started (visual effects listen; the hit is a Sim step).
signal swung(origin: Vector3, yaw: float)
signal spun(origin: Vector3)
## Emitted when a sword hit chops wood off a tree.
signal wood_gathered(amount: int, at: Vector3)
signal damaged(amount: float)

const GROUP := &"heroes"
const HURT_SOUND: AudioStream = preload("res://assets/audio/hero_hurt.wav")

## Metres per second (without the "swift feet" perk, see walk_speed()).
@export var speed: float = 3.2
## Radians per second the model turns towards the walking direction.
@export var turn_speed: float = 12.0
## Seconds without progress after which an order gives up (blocked path).
@export var stuck_timeout: float = 1.5

@export_group("Attack")
@export var attack_damage: float = 14.0
## Sword damage per forge level (index 0 = starting sword).
@export var sword_damage_levels: Array[float] = [14.0, 22.0, 32.0, 45.0]
## Forge prices: [level 1 -> 2, 2 -> 3, 3 -> 4].
@export var sword_upgrade_gold: Array[int] = [40, 90, 160]
@export var sword_upgrade_wood: Array[int] = [30, 60, 100]
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
## Extra reach (metres) for the moment the blade lands: the enemy keeps walking during
## attack_hit_delay, the swing must not miss an enemy that was in reach when it began.
@export var strike_slack: float = 0.4
## Swing on its own at enemies/trees in reach while standing still.
@export var auto_action: bool = true

@export_group("Whirlwind")
## Spin attack: hits every enemy around for attack damage x spin_damage_mult.
@export var spin_radius: float = 2.2
@export var spin_damage_mult: float = 1.6
@export var spin_cooldown: float = 12.0
## Seconds one whirlwind turn takes.
@export var spin_duration: float = 0.45
@export var spin_fx: PackedScene

@export_group("Health")
@export var max_health: float = 100.0
var health: float = 100.0
var _damage_flash_timer: float = 0.0
var _recoil_velocity: Vector3 = Vector3.ZERO
var _last_synced_pos: Vector3 = Vector3.ZERO
var _hurt_sound_player: AudioStreamPlayer3D = null
var _flash_material: StandardMaterial3D = null
var _meshes: Array[GeometryInstance3D] = []

## Where swings are submitted and what clock times them (set by the level).
var commands: GameCommands = null
var sim: Sim = null
## Co-op: the partner's knight. Takes no input and no physics: he is shown at the
## last position his commands carried and glides there (drawing only; what he does
## to the battle happens in Sim steps like any swing).
var is_ghost: bool = false
## Co-op: the skin id of the partner whose ghost this is (validated by the caller).
var skin_id: String = ""
## Set by the on-screen joystick (length 0..1).
var joystick_vector: Vector2 = Vector2.ZERO
## Walkable grid for orders; without it the hero walks in a straight line.
var walk_grid: WalkGrid = null

## Forge level of the sword, 0-based.
var sword_level: int = 0
## Permanent bonuses from perks: sword damage multiplier, extra wood per chop, extra walking
## speed (0.18 = +18 %; the command validator reads walk_speed(), so it follows the perk).
var damage_multiplier: float = 1.0
var wood_bonus: int = 0
var speed_bonus: float = 0.0

var _target_enemy: Enemy = null

## Enemy the hero is pursuing and attacking.
var target_enemy: Enemy:
	get:
		if _target_enemy != null and (not is_instance_valid(_target_enemy) or not _target_enemy.is_alive()):
			_target_enemy = null
		return _target_enemy
	set(value):
		if value != null and (not is_instance_valid(value) or not value.is_alive()):
			value = null
		if _target_enemy != value:
			_target_enemy = value
			if value != null and _has_order:
				cancel_order(false)

var _has_order: bool = false
var _order_target: Vector3 = Vector3.ZERO
## Remaining corners of the route to _order_target (the target is last).
var _waypoints: PackedVector3Array = PackedVector3Array()
var _replanned: bool = false
var _order_reach: float = 0.1
var _on_arrive: Callable = Callable()
var _stuck_time: float = 0.0
var _last_distance: float = INF
## Simulation steps before which the next swing / whirlwind is refused.
var _attack_ready_tick: int = 0
var _spin_ready_tick: int = 0
## Co-op: a command takes the input delay to come back, so own commands wait until
## their effect (and cooldown) is due instead of flooding the network every frame.
var _attack_gate_tick: int = 0
var _spin_gate_tick: int = 0
var _ghost_goal: Vector3 = Vector3.ZERO
var _ghost_set: bool = false
## Seconds of swing animation left (the feet are planted meanwhile; drawing only).
var _attack_left: float = 0.0

@onready var _model: Node3D = $Model
@onready var _puppet: Puppet = $Puppet
@onready var _swing_sound: AudioStreamPlayer3D = $SwingSound
@onready var _chop_sound: AudioStreamPlayer3D = $ChopSound


func _ready() -> void:
	health = max_health
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.albedo_color = Color(1.0, 0.2, 0.2, 0.65)
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_hurt_sound_player = AudioStreamPlayer3D.new()
	_hurt_sound_player.stream = HURT_SOUND
	_hurt_sound_player.volume_db = -4.0
	add_child(_hurt_sound_player)

	# Each shadow caster is one more draw call: the body's shadow is enough.
	for mesh: Node in _model.find_children("*", "GeometryInstance3D", true, false):
		_meshes.append(mesh as GeometryInstance3D)
		if mesh.name != &"Body":
			(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Cosmetic skin (the partner's for the ghost): colours only, outside the simulation.
	Cosmetics.apply(_model, skin_id if is_ghost else Cosmetics.equipped(Cosmetics.HERO))
	add_to_group(GROUP)


func _physics_process(delta: float) -> void:
	if _damage_flash_timer > 0.0:
		_damage_flash_timer = maxf(_damage_flash_timer - delta, 0.0)
		if _damage_flash_timer == 0.0:
			_set_flash_overlay(false)
	if _recoil_velocity.length_squared() > 0.001:
		_recoil_velocity = _recoil_velocity.move_toward(Vector3.ZERO, delta * 12.0)
	_attack_left = maxf(_attack_left - delta, 0.0)
	if is_ghost:
		_glide(delta)
		return
	if Input.is_action_just_pressed(&"attack"):
		try_attack()
	if Input.is_action_just_pressed(&"spin"):
		try_spin()
	var input: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	input = (input + joystick_vector).limit_length(1.0)
	var direction := Vector3.ZERO
	if input.length() > 0.1:
		cancel_order()
		direction = _screen_to_world(input)
	elif target_enemy != null:
		direction = _chase_direction(delta)
	elif _has_order:
		direction = _order_direction(delta)
	var enemy: Enemy = target_enemy
	var should_attack: bool = false
	if can_attack():
		if enemy != null:
			if _flat_distance(enemy) <= attack_range:
				should_attack = true
		elif auto_action and direction == Vector3.ZERO:
			var target: Node3D = get_focus_target(true)
			if target != null:
				if target is Enemy:
					if GameSettings.is_auto_attack():
						should_attack = true
				else:
					should_attack = true
	if should_attack:
		try_attack()
	if _attack_left > 0.0:
		direction *= 0.3  # plant the feet while swinging
	velocity = direction * walk_speed() + _recoil_velocity
	move_and_slide()
	position.y = 0.0
	if commands != null and commands.coop != null and sim != null and sim.running and sim.tick % 6 == 0:
		if (global_position - _last_synced_pos).length_squared() > 0.08:
			_last_synced_pos = global_position
			commands.submit(GameCommand.hero_move(global_position))
	_animate(direction, delta)


func take_damage(amount: float, from_dir: Vector3 = Vector3.ZERO) -> void:
	health = maxf(health - amount, 0.0)
	_damage_flash_timer = 0.25
	_set_flash_overlay(true)
	if _hurt_sound_player != null:
		_hurt_sound_player.pitch_scale = randf_range(0.92, 1.08)
		_hurt_sound_player.play()
	var recoil_dir: Vector3 = from_dir.normalized()
	if recoil_dir.length_squared() < 0.01:
		recoil_dir = -transform.basis.z
	recoil_dir.y = 0.0
	_recoil_velocity = recoil_dir.normalized() * 3.5
	damaged.emit(amount)


func is_flashing() -> bool:
	return _damage_flash_timer > 0.0


func _set_flash_overlay(on: bool) -> void:
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = _flash_material if on else null


## Walking speed with the perk, metres per second.
func walk_speed() -> float:
	return speed * (1.0 + speed_bonus)


## Sets an enemy target to pursue and attack until dead.
func chase_enemy(enemy: Enemy) -> void:
	target_enemy = enemy


## Stops pursuing the current enemy target, if any.
func stop_chasing() -> void:
	target_enemy = null


func is_chasing() -> bool:
	return target_enemy != null


## Walk to `target` until within `reach` metres, then call `on_arrive`.
func move_to(target: Vector3, reach: float = 0.1, on_arrive: Callable = Callable()) -> void:
	cancel_order()  # a new order replaces the old one (listeners hear it end)
	_has_order = true
	_replanned = false
	_order_target = Vector3(target.x, 0.0, target.z)
	_waypoints = (
		walk_grid.find_path(global_position, _order_target) if walk_grid else PackedVector3Array()
	)
	if not _waypoints.is_empty():
		_waypoints.remove_at(_waypoints.size() - 1)  # the target itself is handled below
	_order_reach = reach
	_on_arrive = on_arrive
	_stuck_time = 0.0
	_last_distance = INF


## Price of the next sword level as (gold, wood), or (-1, -1) at the top.
func sword_upgrade_cost() -> Vector2i:
	if sword_level >= sword_upgrade_gold.size():
		return Vector2i(-1, -1)
	return Vector2i(sword_upgrade_gold[sword_level], sword_upgrade_wood[sword_level])


func upgrade_sword() -> void:
	sword_level = mini(sword_level + 1, sword_damage_levels.size() - 1)
	attack_damage = sword_damage_levels[sword_level]


## Swings the sword unless it is still cooling down. Returns true on a swing.
func try_attack() -> bool:
	if commands == null or not can_attack():
		return false
	var yaw: float = _model.rotation.y
	var target: Node3D = _aim_target()
	if target != null:
		var offset: Vector3 = target.global_position - global_position
		yaw = atan2(offset.x, offset.z)
	if _gated(_attack_gate_tick):
		return false
	var sent: bool = commands.submit(GameCommand.hero_attack(global_position, yaw))
	if sent and commands.coop != null:
		_attack_gate_tick = sim.tick + commands.coop.lockstep.delay + Sim.ticks(attack_cooldown)
		_model.rotation.y = yaw
		_puppet.play_action(&"attack")
		_swing_sound.play()
		_attack_left = _puppet.action_length(&"attack")
	return sent


## Whirlwind: one turn of the sword that hits every enemy within spin_radius.
func try_spin() -> bool:
	if commands == null or not sim.running or spin_cooldown_left() > 0.0:
		return false
	if _gated(_spin_gate_tick):
		return false
	var sent: bool = commands.submit(GameCommand.hero_spin(global_position))
	if sent and commands.coop != null:
		_spin_gate_tick = sim.tick + commands.coop.lockstep.delay + Sim.ticks(attack_cooldown)
	return sent


## Co-op: the partner's knight shows up where his command says he is.
func ghost_goto(point: Vector3) -> void:
	if not is_ghost:
		return
	_ghost_goal = Vector3(point.x, 0.0, point.z)
	if not _ghost_set:
		_ghost_set = true
		position = _ghost_goal


func can_attack() -> bool:
	# Nothing swings before the battle clock runs (the level is still being built).
	return sim != null and sim.running and sim.tick >= _attack_ready_tick


## Seconds until the whirlwind is ready again (0 = ready).
func spin_cooldown_left() -> float:
	if sim == null:
		return 0.0
	return maxi(_spin_ready_tick - sim.tick, 0) * Sim.TICK_DT


## The swing command executes (live or from a replay): starts the swing at
## `origin` facing `yaw`; the blade hits attack_hit_delay later, in a Sim step.
func apply_attack(origin: Vector3, yaw: float) -> bool:
	if not can_attack():
		return false
	cancel_order(false)
	_attack_ready_tick = sim.tick + Sim.ticks(attack_cooldown)
	_model.rotation.y = yaw
	if _attack_left <= 0.05 or is_ghost or commands == null or commands.coop == null:
		_attack_left = _puppet.action_length(&"attack")
		_puppet.play_action(&"attack")
		_swing_sound.play()
	swung.emit(origin, yaw)
	sim.schedule_in(Sim.ticks(attack_hit_delay), _strike.bind(origin, yaw))
	return true


## The whirlwind command executes: hurts every enemy within reach of `origin` now.
func apply_spin(origin: Vector3) -> bool:
	if spin_cooldown_left() > 0.0:
		return false
	cancel_order(false)
	_spin_ready_tick = sim.tick + Sim.ticks(spin_cooldown)
	_attack_ready_tick = sim.tick + Sim.ticks(attack_cooldown)
	_attack_left = spin_duration
	_puppet.play_action(&"spin", spin_duration)
	var tween := create_tween()
	tween.tween_property(_model, "rotation:y", _model.rotation.y + TAU, spin_duration)
	_swing_sound.play()
	spun.emit(origin)
	if spin_fx:
		var fx := spin_fx.instantiate() as Node3D
		add_sibling(fx)
		fx.global_position = origin
	for enemy in sim.enemies.duplicate():
		if enemy.is_alive() and _flat_distance_from(origin, enemy.sim_position()) <= spin_radius:
			enemy.take_damage(attack_damage * damage_multiplier * spin_damage_mult)
	return true


## Integers describing the simulated state (for Sim.state_hash).
func state_ints() -> Array[int]:
	return [sword_level, _attack_ready_tick, _spin_ready_tick]


## What a swing would hit now: the nearest living enemy in sword reach, else
## the nearest choppable tree in chop reach (null if none). With `strict`
## false the reach is a little longer, for showing the target ahead of time.
func get_focus_target(strict: bool = false) -> Node3D:
	var slack: float = 0.0 if strict else 0.5
	var best: Node3D = null
	var best_distance: float = attack_range + slack
	if sim == null:
		return null
	for enemy in sim.enemies:
		var d: float = _flat_distance(enemy)
		if enemy.is_alive() and d < best_distance:
			best_distance = d
			best = enemy
	if best != null:
		return best
	best_distance = chop_range + slack
	for tree in sim.trees:
		var d: float = _flat_distance(tree)
		if tree.is_choppable() and d < best_distance:
			best_distance = d
			best = tree
	return best


## Reach of the blade against an enemy at the moment it lands.
func strike_reach() -> float:
	return attack_range + strike_slack


func is_attacking() -> bool:
	return _attack_left > 0.0


func cancel_order(drop_target: bool = true) -> void:
	if drop_target:
		_target_enemy = null
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


func _gated(gate_tick: int) -> bool:
	return commands.coop != null and sim.tick < gate_tick


## Ghost: glides to the last known position with smooth adaptive catch-up.
func _glide(delta: float) -> void:
	var offset: Vector3 = _ghost_goal - position
	offset.y = 0.0
	var dist: float = offset.length()
	var moving: bool = _ghost_set and dist > 0.05 and _attack_left <= 0.0
	if moving:
		var target_speed: float = speed * clampf(dist * 2.0, 1.2, 4.0)
		var step: Vector3 = offset.limit_length(target_speed * delta)
		position += step
	_animate(offset.normalized() if moving else Vector3.ZERO, delta)


func _strike(origin: Vector3, yaw: float) -> void:
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var hit_enemy := false
	# The blade lands attack_hit_delay after the swing began, the enemy walked on meanwhile.
	for enemy in sim.enemies.duplicate():
		if enemy.is_alive() and _in_cone(origin, enemy.sim_position(), forward, strike_reach()):
			enemy.take_damage(attack_damage * damage_multiplier)
			hit_enemy = true
	if hit_enemy:
		return  # an enemy in reach always comes before a tree
	var chopped := false
	for tree in sim.trees:
		if tree.is_choppable() and _in_cone(origin, tree.global_position, forward, chop_range):
			var wood: int = tree.chop(origin)
			if wood > 0:
				wood_gathered.emit(wood + wood_bonus, tree.global_position)
			chopped = true
	if chopped:
		_chop_sound.play()


func _in_cone(origin: Vector3, point: Vector3, forward: Vector3, reach: float) -> bool:
	var offset: Vector3 = point - origin
	offset.y = 0.0
	var distance: float = offset.length()
	if distance > reach:
		return false
	return distance < 0.3 or forward.dot(offset / distance) >= attack_cone


## What the swing turns to: the same thing it can hit (focus target: an enemy in sword
## reach, else a tree in chop reach), so a tree beside the knight is chopped even while an
## enemy walks by out of reach; only without both he turns to whatever is nearby.
func _aim_target() -> Node3D:
	var enemy: Enemy = target_enemy
	if enemy != null:
		return enemy
	var focus: Node3D = get_focus_target(true)
	return focus if focus != null else _nearest_target(auto_aim_range)


## Nearest living enemy, or else choppable tree, within `reach`.
func _nearest_target(reach: float) -> Node3D:
	var best: Node3D = null
	var best_distance: float = reach
	if sim == null:
		return null
	for enemy in sim.enemies:
		var d: float = _flat_distance(enemy)
		if enemy.is_alive() and d < best_distance:
			best_distance = d
			best = enemy
	if best != null:
		return best
	best_distance = reach
	for tree in sim.trees:
		var d: float = _flat_distance(tree)
		if tree.is_choppable() and d < best_distance:
			best_distance = d
			best = tree
	return best


func _flat_distance_from(origin: Vector3, point: Vector3) -> float:
	var offset: Vector3 = point - origin
	offset.y = 0.0
	return offset.length()


func _flat_distance(node: Node3D) -> float:
	var offset: Vector3 = node.global_position - global_position
	offset.y = 0.0
	return offset.length()


func _chase_direction(_delta: float) -> Vector3:
	var enemy: Enemy = target_enemy
	if enemy == null:
		return Vector3.ZERO
	var offset: Vector3 = enemy.global_position - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	var desired_distance: float = attack_range * 0.85
	if distance > desired_distance:
		return offset / distance
	return Vector3.ZERO


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
		return
	_stuck_time += delta
	if _stuck_time <= stuck_timeout:
		return
	if not _replanned and walk_grid:
		# Snagged on an obstacle: plan once more from here before giving up.
		_replanned = true
		_stuck_time = 0.0
		_last_distance = INF
		_waypoints = walk_grid.find_path(global_position, _order_target)
		if not _waypoints.is_empty():
			_waypoints.remove_at(_waypoints.size() - 1)
		return
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
		# The legs follow the real speed (Puppet measures it).
	elif target_enemy != null:
		var offset: Vector3 = target_enemy.global_position - global_position
		offset.y = 0.0
		if offset.length() > 0.01:
			var yaw: float = atan2(offset.x, offset.z)
			_model.rotation.y = rotate_toward(_model.rotation.y, yaw, turn_speed * delta)
