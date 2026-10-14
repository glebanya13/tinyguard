class_name Tower
extends Node3D
## Shoots projectiles at the enemy within range that its priority picks (by
## default the one closest to the castle), or a chain bolt that
## jumps between enemies (lightning: no projectile, damage is instant).

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

var _cooldown: float = 0.0


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
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


## Next priority of the player's switch (wraps around).
func cycle_priority() -> void:
	priority = (priority + 1) % TowerData.Priority.size()


## The enemy in range that the current priority picks, or null.
func find_target() -> Enemy:
	var best: Enemy = null
	var best_key: float = INF
	var range_sq: float = range_m * range_m
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or not enemy.is_alive() or (enemy.is_flying() and not hits_air):
			continue
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		var dist_sq: float = offset.length_squared()
		if dist_sq > range_sq:
			continue
		var key: float = _priority_key(enemy, dist_sq)
		if key < best_key:
			best_key = key
			best = enemy
	return best


## Smaller is shot first. Ties (e.g. enemies at the same spot) go to the nearer one.
func _priority_key(enemy: Enemy, dist_sq: float) -> float:
	var tie: float = dist_sq * 0.0001
	match priority:
		TowerData.Priority.LAST:
			return -enemy.distance_to_goal() + tie
		TowerData.Priority.STRONGEST:
			return -enemy.health + tie
		TowerData.Priority.NEAREST:
			return dist_sq
		_:
			return enemy.distance_to_goal() + tie


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
	var aim: Vector3 = target.global_position - global_position
	aim.y = 0.0
	var reach: Vector3 = aim.normalized() * muzzle_reach if aim.length() > 0.01 else Vector3.ZERO
	projectile.global_position = global_position + Vector3.UP * muzzle_height + reach
	projectile.launch(target, damage, splash_radius, slow_factor, slow_duration, damage_kind)
	fired.emit(target)


## Lightning: hits the target, then jumps to the nearest unhit enemy within
## chain_range, chain_targets times; each jump deals 80% of the previous.
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
		var next: Enemy = _nearest_unhit(current.global_position, hit)
		var shock: float = chilled_bonus if current.is_slowed() else 1.0
		current.take_damage(amount * shock, damage_kind)
		amount *= 0.8
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
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or not enemy.is_alive() or enemy in hit:
			continue
		var d: float = enemy.global_position.distance_squared_to(from)
		if d <= best_sq:
			best_sq = d
			best = enemy
	return best
