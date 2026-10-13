class_name Tower
extends Node3D
## Shoots projectiles at the nearest enemy within range.

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

## Current upgrade level, 0-based.
var level: int = 0

var _cooldown: float = 0.0


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown > 0.0:
		return
	var target: Enemy = find_nearest_enemy()
	if target == null:
		return
	_shoot(target)
	_cooldown = fire_interval


## Takes damage, range and fire interval for `new_level` from the tower data.
func apply_level(data: TowerData, new_level: int) -> void:
	level = clampi(new_level, 0, data.max_level())
	damage = data.damage_levels[level]
	range_m = data.range_levels[level]
	fire_interval = data.interval_levels[level]
	level_changed.emit(level)


func find_nearest_enemy() -> Enemy:
	var nearest: Enemy = null
	var nearest_dist_sq: float = range_m * range_m
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or not enemy.is_alive():
			continue
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		var dist_sq: float = offset.length_squared()
		if dist_sq <= nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = enemy
	return nearest


func _shoot(target: Enemy) -> void:
	if projectile_scene == null:
		push_warning("Tower: projectile_scene is not set")
		return
	var projectile := projectile_scene.instantiate() as Projectile
	# top_level keeps the projectile in world space, independent of the tower.
	projectile.top_level = true
	add_child(projectile)
	var aim: Vector3 = target.global_position - global_position
	aim.y = 0.0
	var reach: Vector3 = aim.normalized() * muzzle_reach if aim.length() > 0.01 else Vector3.ZERO
	projectile.global_position = global_position + Vector3.UP * muzzle_height + reach
	projectile.launch(target, damage)
	fired.emit(target)
