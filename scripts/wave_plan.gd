class_name WavePlan
extends RefCounted
## Turns a level's "waves" block (resources/levels.json) into concrete spawn
## lists. Wave numbers are 1-based. Every wave adds enemies and multiplies
## their health; other kinds replace plain slimes from their "<kind>_from"
## wave (see "mix" in resources/balance.json), bosses close every boss_every-th wave
## and the last one.
## Record run (`record_run`): a free mode where every wave is harder than the last. Health and
## the number of enemies grow geometrically, kinds come in at wave thresholds, elites and
## bosses get more frequent and "surprise waves" (swarm, armour, flyers from every side) come
## on a schedule; all numbers are the "record" block of resources/balance.json.

## Enemy data is loaded when a plan is made, not preloaded in constants: a
## preload here runs while EnemyData (which references itself for splitting
## slimes) is still compiling and breaks the resources.
const ENEMY_PATH := "res://resources/enemies/%s.tres"
## Wave number used when a level has no "<kind>_from" key (never).
const NEVER := 100000

## Enemy file of the scouts that walk their own paths (see "scout_paths").
const SCOUT := "slime_fast"
## Endless siege: waves never run out, no "last wave" boss.
const ENDLESS_WAVES := 9999

var wave_count: int = 1
var endless: bool = false
## Record run rules (see the header); needs `endless`.
var record_run: bool = false
var first_delay: float = 30.0
## Daily challenge: multiplies every wave's health (see set_time_scale for the clock).
var hp_scale: float = 1.0
## Difficulty ("Hard", "Nightmare"): multiplies the number of enemies of every wave.
var count_scale: float = 1.0
## Difficulty index in force (set_difficulty); 0 = Normal.
var difficulty: int = 0
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
## Who replaces a plain slime in the line-up, checked in this order:
## [level key, enemy file, every Nth slot, at offset]. Unlocked from wave "<key>".
## Numbers come from resources/balance.json ("waves").
var _mix: Array = []
## Bosses grow slower than the crowd (exponent on the wave health factor).
var _boss_growth_exponent: float = 1.0
## One more boss per this many waves.
var _boss_per_waves: int = 30
## "record" block of resources/balance.json (empty outside the record run) and its data.
var _rec: Dictionary = {}
var _rec_mix_data: Array[EnemyData] = []
var _rec_surprise_data: Array[EnemyData] = []


func _init(waves: Dictionary, endless_siege: bool = false, record: bool = false) -> void:
	_w = waves
	endless = endless_siege
	record_run = record and endless_siege
	wave_count = ENDLESS_WAVES if endless else int(waves["count"])
	_slime = load(ENEMY_PATH % "slime")
	_boss = load(ENEMY_PATH % "slime_king")
	var rules: Dictionary = Balance.waves()
	_mix = rules["mix"]
	_boss_growth_exponent = float(rules["boss_growth_exponent"])
	_boss_per_waves = int(rules["boss_per_waves"])
	for mix: Array in _mix:
		_mix_data.append(load(ENEMY_PATH % mix[1]))
	_lanes = waves.get("lanes", {})
	_elite = waves.get("elite", {})
	if record_run:
		_rec = Balance.record()
		_elite = _rec["elite"]
		for row: Array in _rec["mix"]:
			_rec_mix_data.append(load(ENEMY_PATH % row[1]))
		for surprise: Dictionary in _rec["surprises"]:
			_rec_surprise_data.append(load(ENEMY_PATH % surprise["kind"]))
	if not _elite.is_empty():
		_elite_data = load(ENEMY_PATH % _elite["kind"])
	first_delay = float(waves["first_delay"])
	wave_duration = float(waves.get("wave_duration", wave_duration))
	spawn_window = float(waves.get("spawn_window", spawn_window))
	_base_times = [first_delay, wave_duration, spawn_window]


## Campaign difficulty `index` (rows of "difficulty" in resources/balance.json): health and
## number of enemies of every wave. Absolute, like set_time_scale. The castle lives and the
## kill gold of the difficulty are applied by the level (see reward_scale, Main).
func set_difficulty(index: int) -> void:
	var row: Dictionary = Balance.difficulty(index)
	difficulty = clampi(index, 0, Balance.difficulty_count() - 1)
	hp_scale = float(row["hp"])
	count_scale = float(row["count"])


## Multiplier of the gold of every kill: the level's own "reward_mult", the record run's and
## the difficulty's.
func reward_scale(index: int) -> float:
	var scale: float = float(_w.get("reward_mult", 1.0))
	if record_run:
		scale *= float(_rec["reward_mult"])
	return scale * float(Balance.difficulty(index)["reward"])


## Daily challenge: all waves faster (< 1) or slower (> 1) than the level says. Absolute,
## measured from the level's own numbers.
func set_time_scale(scale: float) -> void:
	first_delay = _base_times[0] * scale
	wave_duration = _base_times[1] * scale
	spawn_window = _base_times[2] * scale


func is_boss_wave(wave: int) -> bool:
	if record_run:
		var entry: Array = _boss_schedule(wave)
		return not entry.is_empty() and (wave - int(entry[0])) % int(entry[1]) == 0
	var last: bool = not endless and bool(_w["boss_last"]) and wave == wave_count
	return wave % int(_w["boss_every"]) == 0 or last


func health_factor(wave: int) -> float:
	if record_run:
		var growth: float = pow(float(_rec["hp_growth"]), wave - 1)
		return hp_scale * float(_w["hp_mult"]) * minf(growth, float(_rec["hp_cap"]))
	return hp_scale * float(_w["hp_mult"]) * pow(float(_w["hp_growth"]), wave - 1)


## Number of enemies of a wave before bosses and elites (difficulty included).
func count_for(wave: int) -> int:
	var n: float = float(_w["count_base"]) + float(_w["count_step"]) * (wave - 1)
	if record_run:
		n = float(_w["count_base"]) * pow(float(_rec["count_growth"]), wave - 1)
		var surprise: int = surprise_index(wave)
		if surprise >= 0:
			n *= float((_rec["surprises"][surprise] as Dictionary)["count"])
		n = minf(n, float(_rec["count_cap"]))
	return maxi(roundi(n * count_scale), 1)


## Seconds over which a wave's enemies come out: the record run stretches it towards the
## whole wave_duration (no pauses between waves any more).
func window_for(wave: int) -> float:
	if not record_run:
		return spawn_window
	var ramp: Dictionary = _rec["window_ramp"]
	var span: float = float(ramp["to"]) - float(ramp["from"])
	var t: float = clampf((wave - float(ramp["from"])) / span, 0.0, 1.0)
	return lerpf(spawn_window, wave_duration, t)


## Index of the surprise wave `wave` is (record run), -1 for an ordinary wave.
func surprise_index(wave: int) -> int:
	if not record_run:
		return -1
	var list: Array = _rec["surprises"]
	for i in list.size():
		var s: Dictionary = list[i]
		if wave >= int(s["from"]) and (wave - int(s["from"])) % int(s["every"]) == 0:
			return i
	return -1


## Translation key of the surprise wave's name ("" for an ordinary wave).
func surprise_key(wave: int) -> String:
	var index: int = surprise_index(wave)
	return "" if index < 0 else str((_rec["surprises"][index] as Dictionary)["name"])


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
	var count: int = count_for(wave)
	var surprise: int = surprise_index(wave)
	var weights: Array = lane_weights(wave)
	if surprise >= 0 and not weights.is_empty():
		weights = _flags(range(weights.size()), weights.size())  # from every side
	var dealt: Dictionary = {}  # kind -> enemies dealt to every lane so far
	for i in count:
		var data: EnemyData = _slime
		var entry_hp: float = hp
		if surprise >= 0:
			var s: Dictionary = _rec["surprises"][surprise]
			data = _rec_surprise_data[surprise]
			entry_hp = hp * float(s["hp"])
		elif record_run:
			data = _record_kind(wave, i)
		else:
			for k in _mix.size():
				var mix: Array = _mix[k]
				if wave >= int(_w.get(mix[0], NEVER)) and i % int(mix[2]) == int(mix[3]):
					data = _mix_data[k]
					break
		var entry := {"data": data, "hp": entry_hp, "elite": false}
		if not weights.is_empty():
			var use: Array = weights
			if surprise < 0 and data.resource_path.ends_with("/%s.tres" % SCOUT):
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
		var bosses: int = 1 + floori(float(wave) / _boss_per_waves)
		var boss_hp: float = pow(hp, _boss_growth_exponent) * float(_w.get("boss_hp_mult", 1.0))
		if record_run:
			var rb: Dictionary = _rec["boss"]
			bosses = 1 + floori(float(wave) / float(rb["per_waves"]))
			boss_hp = pow(hp, float(rb["hp_exponent"])) * float(rb["hp_mult"])
		for i in bosses:
			var entry := {"data": _boss, "hp": boss_hp, "elite": false}
			if not weights.is_empty():
				var paths: Array = _lanes["boss_paths"]
				entry["lane"] = int(paths[(wave + i) % paths.size()])
			out.append(entry)
	return out


## Record run: the enemy in slot `i` of `wave` (plain slime unless a kind's row claims it).
func _record_kind(wave: int, i: int) -> EnemyData:
	var late: bool = wave >= int(_rec["late_from"])
	for k in _rec_mix_data.size():
		var row: Array = _rec["mix"][k]
		var every: int = int(row[4]) if late else int(row[2])
		if wave >= int(row[0]) and i % every == int(row[3]) % every:
			return _rec_mix_data[k]
	return _slime


## The boss schedule row [from wave, every Nth] in force at `wave`; empty before the first.
func _boss_schedule(wave: int) -> Array:
	var found: Array = []
	for row: Array in _rec["boss"]["schedule"]:
		if wave >= int(row[0]):
			found = row
	return found


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
