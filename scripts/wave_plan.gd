class_name WavePlan
extends RefCounted
## Turns a level's "waves" block (resources/levels.json) into concrete spawn
## lists. Wave numbers are 1-based. Every wave adds enemies and multiplies
## their health; fast and tank slimes join later, bosses close every
## boss_every-th wave and the last one.

const SLIME: EnemyData = preload("res://resources/enemies/slime.tres")
const FAST: EnemyData = preload("res://resources/enemies/slime_fast.tres")
const TANK: EnemyData = preload("res://resources/enemies/slime_tank.tres")
const BOSS: EnemyData = preload("res://resources/enemies/slime_king.tres")
## Bosses grow slower than the crowd (exponent on the wave health factor).
const BOSS_GROWTH_EXPONENT := 0.75
## Interval shrink per wave.
const INTERVAL_DECAY := 0.97

var wave_count: int = 1
var first_delay: float = 30.0
var between: float = 30.0

var _w: Dictionary = {}


func _init(waves: Dictionary) -> void:
	_w = waves
	wave_count = int(waves["count"])
	first_delay = float(waves["first_delay"])
	between = float(waves["between"])


func is_boss_wave(wave: int) -> bool:
	return wave % int(_w["boss_every"]) == 0 or (bool(_w["boss_last"]) and wave == wave_count)


func health_factor(wave: int) -> float:
	return float(_w["hp_mult"]) * pow(float(_w["hp_growth"]), wave - 1)


func spawn_interval(wave: int) -> float:
	return maxf(float(_w["interval_min"]), float(_w["interval"]) * pow(INTERVAL_DECAY, wave - 1))


## Ordered spawn list: [{"data": EnemyData, "hp": float}, ...].
func spawns(wave: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hp: float = health_factor(wave)
	var count: int = roundi(float(_w["count_base"]) + float(_w["count_step"]) * (wave - 1))
	var fast_from: int = int(_w["fast_from"])
	var tank_from: int = int(_w["tank_from"])
	for i in count:
		var data: EnemyData = SLIME
		if wave >= tank_from and i % 4 == 3:
			data = TANK
		elif wave >= fast_from and i % 3 == 1:
			data = FAST
		out.append({"data": data, "hp": hp})
	if is_boss_wave(wave):
		var bosses: int = 1 + floori(wave / 20.0)
		for i in bosses:
			out.append({"data": BOSS, "hp": pow(hp, BOSS_GROWTH_EXPONENT)})
	return out
