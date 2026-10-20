class_name Tower
extends Node3D
## Shoots projectiles at the enemy within range that its priority picks (by
## default the one closest to the castle), or a chain bolt that jumps between
## enemies (lightning: no projectile, damage is instant).
## Acts in fixed simulation steps (sim_step); ties are broken by the enemy id.

## Emitted on every shot; visuals (aiming, recoil) listen to it.
signal fired(target: Enemy)
## Emitted after apply_level(); level is 0-based.
signal level_changed(level: int)

@export var projectile_scene: PackedScene
## Attack radius in metres, measured on the ground plane.
@export var range_m: float = 3.0
## Seconds between shots.
@export var fire_interval: float = 0.5
@export var damage: float = 12.0
## Height above the tower origin where projectiles appear.
@export var muzzle_height: float = 1.1
## Horizontal distance from the tower axis towards the target (crossbow tip).
@export var muzzle_reach: float = 0.3
## Seconds between target searches while nothing is in range.
@export var retarget_interval: float = 0.15
## Bolt effect for chain towers.
@export var chain_fx: PackedScene
## Chain lightning: share of the damage kept by every next jump.
@export var chain_falloff: float = 0.8

## Stable id (set by Sim.add_tower).
var id: int = 0
var sim: Sim = null
## Current upgrade level, 0-based.
var level: int = 0
## Tower type this tower was built from (set by apply_level).
var data: TowerData = null
var splash_radius: float = 0.0
var slow_factor: float = 1.0
var slow_duration: float = 0.0
var chain_targets: int = 0
var chain_range: float = 0.0
var damage_kind: StringName = &""
var hits_air: bool = true
var chilled_bonus: float = 1.0
## Which enemy in range is shot (a TowerData.Priority); -1 until apply_level.
var priority: int = -1
var level_indicator: Label3D = null

var _cooldown: float = 0.0


func _ready() -> void:
	update_level_indicator(level + 1)


func _exit_tree() -> void:
	if sim != null:
		sim.remove_tower(self)


## Joins the simulation (called by whoever builds the tower).
func attach(new_sim: Sim) -> void:
	sim = new_sim
	sim.add_tower(self)


## One fixed simulation step.
func sim_step() -> void:
	_cooldown = maxf(_cooldown - Sim.TICK_DT, 0.0)
	if _cooldown > 0.0:
		return
	var target: Enemy = find_target()
	if target == null:
		_cooldown = retarget_interval
		return
	_shoot(target)
	_cooldown = fire_interval


## Takes damage, range and fire interval for `new_level` from the tower data.
func apply_level(tower_data: TowerData, new_level: int) -> void:
	data = tower_data
	level = clampi(new_level, 0, data.max_level())
	damage = data.damage_levels[level]
	range_m = data.range_levels[level]
	fire_interval = data.interval_levels[level]
	splash_radius = data.splash_levels[level]
	slow_factor = data.slow_levels[level]
	slow_duration = data.slow_duration
	chain_targets = data.chain_levels[level]
	chain_range = data.chain_range
	damage_kind = data.damage_kind
	hits_air = data.hits_air
	chilled_bonus = data.chilled_bonus
	if priority < 0:
		priority = data.default_priority
	level_changed.emit(level)
	update_level_indicator(level + 1)


## Returns the Roman numeral or star string for the given display level (1..4).
static func level_symbol(lvl: int) -> String:
	match lvl:
		1:
			return "I"
		2:
			return "II"
		3:
			return "III"
		4:
			return "★"
		_:
			return "★" if lvl >= 4 else "I"


## Gets the level symbol string (e.g. "I", "II", "III", "★").
func get_level_symbol(lvl: int = -1) -> String:
	return level_symbol(lvl if lvl > 0 else (level + 1))


## Gets the text currently shown by the level indicator.
func get_level_text() -> String:
	return level_indicator.text if level_indicator != null else get_level_symbol()


## Updates the 3D level badge above the tower.
func update_level_indicator(lvl: int = -1) -> void:
	var target_lvl: int = lvl if lvl > 0 else (level + 1)
	if level_indicator == null:
		level_indicator = Label3D.new()
		level_indicator.name = "LevelIndicator"
		level_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		level_indicator.no_depth_test = true
		level_indicator.pixel_size = 0.0055
		level_indicator.font_size = 32
		level_indicator.outline_size = 8
		level_indicator.outline_modulate = Color(0.12, 0.08, 0.05, 0.95)
		level_indicator.position = Vector3(0.0, 2.3, 0.0)
		add_child(level_indicator)
	var sym: String = level_symbol(target_lvl)
	level_indicator.text = sym
	if sym == "★":
		level_indicator.modulate = Color(1.0, 0.84, 0.15)
	else:
		level_indicator.modulate = Color(1.0, 0.96, 0.85)


## Integers describing the simulated state (for Sim.state_hash).
func state_ints() -> Array[int]:
	return [id, level, roundi(damage * 1000.0), roundi(_cooldown * 1000.0), priority]


## Changes the target priority (a TowerData.Priority); the SET_PRIORITY command.
func set_priority(new_priority: int) -> void:
	priority = clampi(new_priority, 0, TowerData.Priority.size() - 1)


## The enemy in range that the priority picks. Integer keys, and the first of
## equal keys wins (enemies are in id order), so the choice is deterministic.
func find_target() -> Enemy:
	var best: Enemy = null
	if sim == null:
		return null
	var best_key: int = 0
	var range_sq: float = range_m * range_m
	for enemy in sim.enemies:
		if not enemy.is_alive() or (enemy.is_flying() and not hits_air):
			continue
		var offset: Vector3 = enemy.sim_position() - global_position
		offset.y = 0.0
		var dist_sq: float = offset.length_squared()
		if dist_sq > range_sq:
			continue
		var key: int = _priority_key(enemy, dist_sq)
		if best == null or key < best_key:
			best_key = key
			best = enemy
	return best


## Smaller is shot first.
func _priority_key(enemy: Enemy, dist_sq: float) -> int:
	match priority:
		TowerData.Priority.LAST:
			return -enemy.goal_mm()
		TowerData.Priority.STRONGEST:
			return -roundi(enemy.health * 1000.0)
		TowerData.Priority.NEAREST:
			return roundi(dist_sq * 1000.0)
		_:
			return enemy.goal_mm()


func _shoot(target: Enemy) -> void:
	if chain_targets > 0:
		_shoot_chain(target)
		return
	if projectile_scene == null:
		push_warning("Tower: projectile_scene is not set")
		return
	var projectile := projectile_scene.instantiate() as Projectile
	# A sibling, not a child: shots in flight survive selling the tower.
	projectile.top_level = true
	add_sibling(projectile)
	var aim: Vector3 = target.sim_position() - global_position
	aim.y = 0.0
	var reach: Vector3 = aim.normalized() * muzzle_reach if aim.length() > 0.01 else Vector3.ZERO
	projectile.global_position = global_position + Vector3.UP * muzzle_height + reach
	projectile.sim = sim
	projectile.launch(target, damage, splash_radius, slow_factor, slow_duration, damage_kind)
	fired.emit(target)


## Lightning: hits the target, then jumps to the nearest unhit enemy within
## chain_range, chain_targets times; each jump deals `chain_falloff` of the previous.
func _shoot_chain(target: Enemy) -> void:
	var points := PackedVector3Array([global_position + Vector3.UP * muzzle_height])
	var hit: Array[Enemy] = []
	var current: Enemy = target
	var amount: float = damage
	for i in chain_targets + 1:
		if current == null:
			break
		points.append(current.get_aim_point())
		hit.append(current)
		var next: Enemy = _nearest_unhit(current.sim_position(), hit)
		var shock: float = chilled_bonus if current.is_slowed() else 1.0
		current.take_damage(amount * shock, damage_kind)
		amount *= chain_falloff
		current = next
	if chain_fx:
		var fx: Node3D = chain_fx.instantiate()
		fx.top_level = true
		add_child(fx)
		fx.call(&"setup", points)
	fired.emit(target)


func _nearest_unhit(from: Vector3, hit: Array[Enemy]) -> Enemy:
	var best: Enemy = null
	var best_sq: float = chain_range * chain_range
	for enemy in sim.enemies:
		if not enemy.is_alive() or enemy in hit:
			continue
		var d: float = enemy.sim_position().distance_squared_to(from)
		if best == null and d <= best_sq or d < best_sq:
			best_sq = d
			best = enemy
	return best
