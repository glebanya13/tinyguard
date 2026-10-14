class_name WavePlan
extends RefCounted
## Turns a level's "waves" block (resources/levels.json) into concrete spawn
## lists. Wave numbers are 1-based. Every wave adds enemies and multiplies
## their health; other kinds replace plain slimes from their "<kind>_from"
## wave (see MIX), bosses close every boss_every-th wave and the last one.

## Enemy data is loaded when a plan is made, not preloaded in constants: a
## preload here runs while EnemyData (which references itself for splitting
## slimes) is still compiling and breaks the resources.
const ENEMY_PATH := "res://resources/enemies/%s.tres"
## Wave number used when a level has no "<kind>_from" key (never).
const NEVER := 100000
## Bosses grow slower than the crowd (exponent on the wave health factor).
const BOSS_GROWTH_EXPONENT := 0.75
## Who replaces a plain slime in the line-up, checked in this order:
## [level key, enemy file, every Nth slot, at offset]. Unlocked from wave "<key>".
const MIX := [
	["golem_from", "stone_golem", 9, 8],
	["tank_from", "slime_tank", 4, 3],
	["shield_from", "slime_shield", 6, 5],
	["healer_from", "slime_healer", 8, 4],
	["splitter_from", "slime_splitter", 7, 6],
	["bat_from", "slime_bat", 5, 2],
	["fast_from", "slime_fast", 3, 1],
]

## Endless siege: waves never run out, no "last wave" boss.
const ENDLESS_WAVES := 9999

var wave_count: int = 1
var endless: bool = false
var first_delay: float = 30.0
## Every wave lasts this long; then the next one starts.
var wave_duration: float = 30.0
## Its enemies come out evenly during the first spawn_window seconds.
var spawn_window: float = 24.0

var _w: Dictionary = {}
var _slime: EnemyData
var _boss: EnemyData
var _mix_data: Array[EnemyData] = []


func _init(waves: Dictionary, endless_siege: bool = false) -> void:
	_w = waves
	endless = endless_siege
	wave_count = ENDLESS_WAVES if endless else int(waves["count"])
	_slime = load(ENEMY_PATH % "slime")
	_boss = load(ENEMY_PATH % "slime_king")
	for mix: Array in MIX:
		_mix_data.append(load(ENEMY_PATH % mix[1]))
	first_delay = float(waves["first_delay"])
	wave_duration = float(waves.get("wave_duration", wave_duration))
	spawn_window = float(waves.get("spawn_window", spawn_window))


func is_boss_wave(wave: int) -> bool:
	var last: bool = not endless and bool(_w["boss_last"]) and wave == wave_count
	return wave % int(_w["boss_every"]) == 0 or last


func health_factor(wave: int) -> float:
	return float(_w["hp_mult"]) * pow(float(_w["hp_growth"]), wave - 1)


## Ordered spawn list: [{"data": EnemyData, "hp": float}, ...].
func spawns(wave: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hp: float = health_factor(wave)
	var count: int = roundi(float(_w["count_base"]) + float(_w["count_step"]) * (wave - 1))
	for i in count:
		var data: EnemyData = _slime
		for k in MIX.size():
			var mix: Array = MIX[k]
			if wave >= int(_w.get(mix[0], NEVER)) and i % int(mix[2]) == int(mix[3]):
				data = _mix_data[k]
				break
		out.append({"data": data, "hp": hp})
	if is_boss_wave(wave):
		var bosses: int = 1 + floori(wave / 30.0)
		for i in bosses:
			out.append({"data": _boss, "hp": pow(hp, BOSS_GROWTH_EXPONENT)})
	return out
