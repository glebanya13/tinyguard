class_name Enemy
extends PathFollow3D
## Walks along the parent Path3D towards the base. Built from EnemyData via
## setup() before entering the tree. Reports death and reaching the base
## through signals and frees itself in both cases. Drawn by an EnemyCrowd when
## one is set (MultiMesh, no own model); otherwise it instantiates its model.
## The walk is simulated in fixed steps by Sim (sim_step); the node's own
## `progress` / transform only show the position between two steps.

signal died(reward: int)
signal reached_base(damage: int)
## Every hit that landed, with the damage after armor (visual effects listen).
signal damaged(amount: float)
## A splitting enemy died: spawn its halves (WaveManager listens).
signal split(data: EnemyData, health_mult: float, progress: float, wave: int)

const GROUP := &"enemies"
## Damage type that ignores `EnemyData.armor` (lightning: the shock goes through plates).
const ARMOR_PIERCING := &"shock"
const LOOPING_MODEL := preload("res://scripts/looping_model.gd")
## Progress ratio treated as "arrived" (avoids float equality at the end).
const ARRIVAL_RATIO := 0.999
## Height of the point projectiles aim at, relative to the model height.
const AIM_FRACTION := 0.45
## Health bar colors by remaining health percentage.
const COLOR_HP_GREEN := Color(0.25, 0.85, 0.3, 1.0)
const COLOR_HP_YELLOW := Color(0.95, 0.8, 0.2, 1.0)
const COLOR_HP_RED := Color(0.95, 0.25, 0.2, 1.0)

@export var max_health: float = 30.0
## Movement speed in metres per second along the path.
@export var speed: float = 1.2
@export var reward: int = 5
@export var base_damage: int = 1
## Splash and coin burst spawned where the enemy dies.
@export var death_fx: PackedScene

var health: float = 0.0
var data: EnemyData = null
## Stable id (set by Sim.add_enemy in spawn order): the order of everything.
var id: int = 0
var sim: Sim = null
## The route walked (set before entering the tree; else the parent Path3D).
var path: Path3D = null
## Metres walked along the path in the simulation (the node shows an interpolation).
var sim_progress: float = 0.0
## Wave this enemy belongs to (set by WaveManager).
var wave: int = 0
## Shared renderer; set before adding the enemy to the tree (null = own model).
var crowd: EnemyCrowd = null
## Offset into the idle animation cycle (0..1) so a crowd does not bob in sync.
var anim_phase: float = randf()
## Squash on hits / heal pulses (the crowd renderer reads it).
var visual_scale: Vector3 = Vector3.ONE
## Rare tougher enemy of the wave plan: drawn bigger, always shows its bar.
var elite: bool = false
var elite_scale: float = 1.0
## Visual only: 1 right after a hit, fading to 0 (the crowd renderer tints by it).
var hit_flash: float = 0.0
## EnemyCrowd bookkeeping for the tint (last written slot and value).
var crowd_slot: int = -1
var crowd_flash: float = -1.0

var _is_dead: bool = false
var _prev_progress: float = 0.0
var _path_length: float = 1.0
var _sim_pos: Vector3 = Vector3.ZERO
var _slow_factor: float = 1.0
var _slow_left: float = 0.0
var _bar_width: float = 1.0
var _model: Node3D = null
var _health_mult: float = 1.0
var _heal_left: float = 0.0

@onready var _health_bar: MeshInstance3D = $HealthBar
@onready var _health_bar_bg: MeshInstance3D = get_node_or_null("HealthBarBg") as MeshInstance3D


## Configure from an enemy type; health is multiplied by the wave factor.
func setup(enemy_data: EnemyData, health_multiplier: float) -> void:
	data = enemy_data
	_health_mult = health_multiplier
	max_health = data.health * health_multiplier
	speed = data.speed
	reward = data.reward
	base_damage = data.base_damage


func _ready() -> void:
	health = max_health
	add_to_group(GROUP)
	loop = false
	if path == null:
		path = get_parent() as Path3D
	if sim == null:
		sim = Sim.current
	_path_length = maxf(path.curve.get_baked_length(), 0.001) if path else 1.0
	sim.add_enemy(self)
	_update_sim_pos()
	_bar_width = data.health_bar_width / 0.6 if data else 1.0
	if crowd and data:
		crowd.add(self)
		_health_bar.queue_free()
		_health_bar = null
		if _health_bar_bg:
			_health_bar_bg.queue_free()
			_health_bar_bg = null
		return
	if data:
		_model = data.model.instantiate() as Node3D
		_model.set_script(LOOPING_MODEL)
		_model.rotation.y = PI  # models face +Z, PathFollow3D moves along -Z
		_model.position.y = data.fly_height
		add_child(_model)
		# Crowds of enemies: no shadows (one draw call each instead of two).
		for mesh: Node in _model.find_children("*", "GeometryInstance3D", true, false):
			(mesh as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_health_bar.position.y = data.health_bar_height + data.fly_height
		_health_bar.scale.x = _bar_width
		if _health_bar_bg:
			_health_bar_bg.position.y = _health_bar.position.y
			_health_bar_bg.scale.x = _bar_width
		if data.is_boss:
			_health_bar.scale.y = 1.8
			if _health_bar_bg:
				_health_bar_bg.scale.y = 1.8
	# A full bar says nothing; hiding it saves a draw call per fresh enemy.
	_health_bar.visible = is_boss()
	if _health_bar_bg:
		_health_bar_bg.visible = is_boss()
	_update_own_bar()


## Drawing only: shows the position between the last two simulation steps.
func _process(_delta: float) -> void:
	if _is_dead:
		return
	progress = minf(lerpf(_prev_progress, sim_progress, sim.alpha()), _path_length)


## One fixed simulation step (called by Sim in id order).
func sim_step() -> void:
	if _is_dead:
		return
	_prev_progress = sim_progress
	if _slow_left > 0.0:
		_slow_left -= Sim.TICK_DT
		if _slow_left <= 0.0:
			_slow_factor = 1.0
	sim_progress += speed * _slow_factor * Sim.TICK_DT
	_update_sim_pos()
	if data and data.heal_fraction > 0.0:
		_heal_left -= Sim.TICK_DT
		if _heal_left <= 0.0:
			_heal_left = data.heal_interval
			_heal_neighbours()
	if sim_progress / _path_length >= ARRIVAL_RATIO:
		_remove()
		reached_base.emit(base_damage)


## `kind` is the damage type of the hit (&"arrow" for archers, &"shock" for lightning,
## &"" otherwise).
func take_damage(amount: float, kind: StringName = &"") -> void:
	if _is_dead:
		return
	if kind == &"arrow" and data:
		amount *= data.arrow_damage_mult
	if data and data.armor > 0.0 and kind != ARMOR_PIERCING:
		amount = maxf(amount - data.armor, 1.0)
	health = maxf(health - amount, 0.0)
	hit_flash = 1.0
	damaged.emit(amount)
	_update_own_bar()
	if health <= 0.0:
		_spawn_death_fx()
		_remove()
		if data and data.split_into:
			# Halves first (they join the wave before this one leaves it), a bit apart.
			for i in data.split_count:
				split.emit(data.split_into, _health_mult, maxf(sim_progress - 0.35 * i, 0.0), wave)
		died.emit(reward)
	else:
		_pulse(Vector3(1.18, 0.82, 1.18), 0.0, 0.18)  # squash on hit


## Slows movement to `factor` of the normal speed for `duration` seconds.
func apply_slow(factor: float, duration: float) -> void:
	_slow_factor = minf(_slow_factor, factor)
	_slow_left = maxf(_slow_left, duration)


func is_alive() -> bool:
	return not _is_dead


## True while a frost hit still slows this enemy (lightning shocks it harder).
func is_slowed() -> bool:
	return _slow_factor < 1.0


## Millimetres of walking left to the castle along its own path (smaller = closer
## to the castle). An integer, comparable between paths: what target priorities use.
func goal_mm() -> int:
	return roundi(maxf(_path_length - sim_progress, 0.0) * 1000.0)


## Puts the enemy `metres` along the path at once (spawning halves, tests).
func place(metres: float) -> void:
	sim_progress = metres
	_prev_progress = metres
	_update_sim_pos()
	progress = minf(metres, _path_length)


## Where the simulation has the enemy (ground position; targeting uses it).
func sim_position() -> Vector3:
	return _sim_pos


## Integers describing the simulated state (for Sim.state_hash).
func state_ints() -> Array[int]:
	return [
		id,
		wave,
		roundi(sim_progress * 1000.0),
		roundi(health * 1000.0),
		roundi(_slow_left * 1000.0),
		roundi(_heal_left * 1000.0),
		roundi(_sim_pos.x * 1000.0),
		roundi(_sim_pos.z * 1000.0),
	]


## Restores health (capped at max) and refreshes the bar.
func heal(amount: float) -> void:
	if _is_dead or health >= max_health:
		return
	health = minf(health + amount, max_health)
	_update_own_bar()


func is_flying() -> bool:
	return data != null and data.flying


func is_boss() -> bool:
	return data != null and data.is_boss


func health_ratio() -> float:
	return health / max_health if max_health > 0.0 else 0.0


## A full bar says nothing: only hurt enemies and bosses show one.
func shows_health_bar() -> bool:
	return is_boss() or elite or health < max_health


## Bar scale relative to the 0.6 m bar mesh, and its height above the path.
func bar_width() -> float:
	return _bar_width


func bar_height() -> float:
	return data.health_bar_height + data.fly_height if data else 0.8


## Model transform relative to the enemy (turned to face the walking
## direction, lifted when flying, squashed by hits).
func model_offset() -> Transform3D:
	var lift: float = data.fly_height if data else 0.0
	var scale_now: Vector3 = visual_scale * elite_scale
	return Transform3D(Basis(Vector3.UP, PI).scaled(scale_now), Vector3(0.0, lift, 0.0))


func get_aim_point() -> Vector3:
	var height: float = data.health_bar_height * AIM_FRACTION + data.fly_height if data else 0.25
	return _sim_pos + Vector3.UP * height


func _update_sim_pos() -> void:
	if path != null and path.curve != null and path.curve.point_count >= 2:
		_sim_pos = path.global_transform * path.curve.sample_baked(sim_progress, true)


func _heal_neighbours() -> void:
	var r2: float = data.heal_radius * data.heal_radius
	for other in sim.enemies.duplicate():
		if other != self and other.sim_position().distance_squared_to(_sim_pos) <= r2:
			other.heal(other.max_health * data.heal_fraction)
	_pulse(Vector3.ONE * 1.12, 0.12, 0.2)


## Scale kick (hit squash / heal pulse) on the own model or the crowd instance.
func _pulse(peak: Vector3, rise: float, fall: float) -> void:
	var tween := create_tween()
	if _model:
		if rise > 0.0:
			tween.tween_property(_model, "scale", peak, rise)
		else:
			_model.scale = peak
		tween.tween_property(_model, "scale", Vector3.ONE, fall)
	else:
		if rise > 0.0:
			tween.tween_property(self, "visual_scale", peak, rise)
		else:
			visual_scale = peak
		tween.tween_property(self, "visual_scale", Vector3.ONE, fall)


func _update_own_bar() -> void:
	if not _health_bar:
		return
	var ratio := health_ratio()
	var show_bar := shows_health_bar()
	_health_bar.visible = show_bar
	_health_bar.scale.x = _bar_width * ratio
	if _health_bar_bg:
		_health_bar_bg.visible = show_bar
	var color := COLOR_HP_GREEN
	if ratio < 0.2:
		color = COLOR_HP_RED
	elif ratio <= 0.5:
		color = COLOR_HP_YELLOW
	if _health_bar.material_override == null:
		var base_mat: Material = _health_bar.get_active_material(0)
		if base_mat:
			_health_bar.material_override = base_mat.duplicate()
	var mat := _health_bar.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = color


func _spawn_death_fx() -> void:
	if death_fx == null:
		return
	var fx := death_fx.instantiate() as Node3D
	add_sibling(fx)
	fx.global_position = get_aim_point()
	if is_boss():
		fx.scale = Vector3.ONE * 2.5


func _exit_tree() -> void:
	if sim != null:
		sim.remove_enemy(self)
	if is_instance_valid(crowd):
		crowd.remove(self)


func _remove() -> void:
	_is_dead = true
	sim.remove_enemy(self)
	if crowd:
		crowd.remove(self)
	remove_from_group(GROUP)
	queue_free()
