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

## Enemy file of the scouts that walk their own paths (see "scout_paths").
const SCOUT := "slime_fast"
## Endless siege: waves never run out, no "last wave" boss.
const ENDLESS_WAVES := 9999

var wave_count: int = 1
var endless: bool = false
var first_delay: float = 30.0
## Daily challenge: multiplies every wave's health (see set_time_scale for the clock).
var hp_scale: float = 1.0
## Every wave lasts this long; then the next one starts.
var wave_duration: float = 30.0
## Its enemies come out evenly during the first spawn_window seconds.
var spawn_window: float = 24.0

var _w: Dictionary = {}
var _base_times: Array[float] = []
## "lanes" block: weights per path and wave, scout and boss paths (may be empty).
var _lanes: Dictionary = {}
## "elite" block: rare tougher enemies (may be empty).
var _elite: Dictionary = {}
var _elite_data: EnemyData
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
	_lanes = waves.get("lanes", {})
	_elite = waves.get("elite", {})
	if not _elite.is_empty():
		_elite_data = load(ENEMY_PATH % _elite["kind"])
	first_delay = float(waves["first_delay"])
	wave_duration = float(waves.get("wave_duration", wave_duration))
	spawn_window = float(waves.get("spawn_window", spawn_window))
	_base_times = [first_delay, wave_duration, spawn_window]


## Daily challenge: all waves faster (< 1) or slower (> 1) than the level says. Absolute,
## measured from the level's own numbers.
func set_time_scale(scale: float) -> void:
	first_delay = _base_times[0] * scale
	wave_duration = _base_times[1] * scale
	spawn_window = _base_times[2] * scale


func is_boss_wave(wave: int) -> bool:
	var last: bool = not endless and bool(_w["boss_last"]) and wave == wave_count
	return wave % int(_w["boss_every"]) == 0 or last


func health_factor(wave: int) -> float:
	return hp_scale * float(_w["hp_mult"]) * pow(float(_w["hp_growth"]), wave - 1)


## Number of paths the "lanes" block plans for (0 = no lane plan: the wave
## manager deals paths out in turn).
func lane_count() -> int:
	var patterns: Array = _lanes.get("patterns", [])
	return 0 if patterns.is_empty() else (patterns[0] as Array).size()


## Weight of every path in `wave` (0 = unused); empty without a lane plan.
func lane_weights(wave: int) -> Array:
	var patterns: Array = _lanes.get("patterns", [])
	if patterns.is_empty():
		return []
	return patterns[(wave - 1) % patterns.size()]


func is_elite_wave(wave: int) -> bool:
	if _elite.is_empty() or wave < int(_elite["from"]):
		return false
	return (wave - int(_elite["from"])) % int(_elite["every"]) == 0


## Ordered spawn list: [{"data": EnemyData, "hp": float, "lane": int, "elite": bool}, ...].
## "lane" (index into the level's paths) is missing without a lane plan.
func spawns(wave: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var hp: float = health_factor(wave)
	var count: int = roundi(float(_w["count_base"]) + float(_w["count_step"]) * (wave - 1))
	var weights: Array = lane_weights(wave)
	var dealt: Dictionary = {}  # kind -> enemies dealt to every lane so far
	for i in count:
		var data: EnemyData = _slime
		for k in MIX.size():
			var mix: Array = MIX[k]
			if wave >= int(_w.get(mix[0], NEVER)) and i % int(mix[2]) == int(mix[3]):
				data = _mix_data[k]
				break
		var entry := {"data": data, "hp": hp, "elite": false}
		if not weights.is_empty():
			var use: Array = weights
			if data.resource_path.ends_with("/%s.tres" % SCOUT):
				use = _flags(_lanes["scout_paths"], weights.size())
			entry["lane"] = _deal(dealt, data, use, wave)
		out.append(entry)
	if is_elite_wave(wave):
		var elites: int = 1 + floori((wave - int(_elite["from"])) / float(_elite["step"]))
		for e in elites:
			var entry := {
				"data": _elite_data,
				"hp": hp * float(_elite["hp"]),
				"elite": true,
				"reward_mult": float(_elite["reward"]),
				"scale": float(_elite["scale"]),
			}
			if not weights.is_empty():
				entry["lane"] = _deal(dealt, _elite_data, weights, wave + e)
			out.insert(roundi(out.size() * (e + 1.0) / (elites + 1.0)), entry)
	if is_boss_wave(wave):
		var bosses: int = 1 + floori(wave / 30.0)
		for i in bosses:
			var entry := {"data": _boss, "hp": pow(hp, BOSS_GROWTH_EXPONENT), "elite": false}
			if not weights.is_empty():
				var paths: Array = _lanes["boss_paths"]
				entry["lane"] = int(paths[(wave + i) % paths.size()])
			out.append(entry)
	return out


## 1 for every path in `lanes`, 0 for the rest.
func _flags(lanes: Array, size: int) -> Array:
	var out: Array = []
	out.resize(size)
	out.fill(0)
	for lane: Variant in lanes:  # JSON numbers are floats
		out[int(lane)] = 1
	return out


## Next path for an enemy of `data`: the largest weight / (already dealt + 1).
## The search starts at a different path every wave, so ties do not always go to path 0.
func _deal(dealt: Dictionary, data: EnemyData, weights: Array, wave: int) -> int:
	var counts: Array = dealt.get(data, [])
	if counts.is_empty():
		counts.resize(weights.size())
		counts.fill(0)
		dealt[data] = counts
	var best: int = -1
	var best_score: float = -1.0
	for step in weights.size():
		var k: int = (wave + step) % weights.size()
		var score: float = float(weights[k]) / (int(counts[k]) + 1.0)
		if score > best_score:
			best_score = score
			best = k
	counts[best] = int(counts[best]) + 1
	return best
