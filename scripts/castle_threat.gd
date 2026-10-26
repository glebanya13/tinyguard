class_name CastleThreat
extends RefCounted
## Which enemies will reach the castle alive: a few seconds of walking from it, and the towers
## along the rest of their road are not expected to finish them. An estimate for the castle
## alarm (LaneHint draws a pulsing "!" over them), read from the simulation, never changing it.

## An enemy is announced when it is at most this many seconds of walking from the castle: early
## enough for the knight to run there (playtest 2026-10-24: the old alarm came too late).
const WARN_SECONDS := 16.0
## Metres between the points of the rest of the road the estimate looks at.
const SAMPLE_STEP := 0.5
## Share of the towers' damage the estimate counts on (misses, shots at other enemies, overkill).
const TOWER_EFFICIENCY := 0.6
## At most this many enemies are announced at a time (the nearest to the castle).
const MAX_ALERTS := 4


## Enemies that will most likely reach the castle, nearest first.
static func find(
	enemies: Array[Enemy], towers: Array[Tower], warn_seconds: float = WARN_SECONDS
) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for enemy: Enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		if seconds_to_castle(enemy) > warn_seconds:
			continue
		if enemy.health > expected_damage(enemy, towers):
			out.append(enemy)
	out.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.goal_mm() < b.goal_mm())
	if out.size() > MAX_ALERTS:
		out.resize(MAX_ALERTS)
	return out


## Seconds of walking left to the castle at the enemy's own speed.
static func seconds_to_castle(enemy: Enemy) -> float:
	return enemy.goal_mm() / 1000.0 / maxf(enemy.speed, 0.1)


## Damage the towers are expected to deal along the rest of the enemy's road.
static func expected_damage(enemy: Enemy, towers: Array[Tower]) -> float:
	var path: Path3D = enemy.path
	if path == null or path.curve == null or towers.is_empty():
		return 0.0
	var length: float = path.curve.get_baked_length()
	var step_time: float = SAMPLE_STEP / maxf(enemy.speed, 0.1)
	var xform: Transform3D = path.global_transform
	var total: float = 0.0
	var at: float = enemy.sim_progress
	while at < length:
		var point: Vector3 = xform * path.curve.sample_baked(at, true)
		for tower: Tower in towers:
			if enemy.is_flying() and not tower.hits_air:
				continue
			var offset := Vector2(
				point.x - tower.global_position.x, point.z - tower.global_position.z
			)
			if offset.length_squared() <= tower.range_m * tower.range_m:
				total += _dps(tower, enemy) * step_time
		at += SAMPLE_STEP
	return total * TOWER_EFFICIENCY


## Damage per second of `tower` against `enemy` (its arrow weakness and armour counted).
static func _dps(tower: Tower, enemy: Enemy) -> float:
	var hit: float = tower.damage
	if enemy.data != null:
		if tower.damage_kind == &"arrow":
			hit *= enemy.data.arrow_damage_mult
		if enemy.data.armor > 0.0 and tower.damage_kind != Enemy.ARMOR_PIERCING:
			hit = maxf(hit - enemy.data.armor, 1.0)
	return hit / maxf(tower.fire_interval, 0.05)
