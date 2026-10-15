class_name DailyRun
extends RefCounted
## The daily challenge inside a battle: applies the day's modifiers to the wave plan,
## the wave manager and the build manager, and files the result at the end.
## main.gd calls these from a few lines; replays call apply() again from the journal
## header, so the modifiers are part of what a journal reproduces.

## Journal of the best run of the day (the base of a later replay check).
const JOURNAL_PATH := "user://daily_best.json"


## Starts the challenge of `key` from the map: the level and the endless rules.
static func select(key: String) -> void:
	LevelCatalog.daily_key = key
	LevelCatalog.selected_id = Daily.level_for(key)
	LevelCatalog.endless = true


## The seed of the day's battle (the same for every player).
static func seed_of(key: String) -> int:
	return Daily.seed_for(key)


## Sets the modifiers of day `key` (absolute values: calling it twice is harmless).
static func apply(key: String, plan: WavePlan, waves: WaveManager, builds: BuildManager) -> void:
	var preset: Dictionary = Daily.preset_for(key)
	plan.hp_scale = float(preset["hp_mult"])
	plan.set_time_scale(float(preset["wave_duration_mult"]))
	waves.reward_scale = float(preset["reward_mult"])
	builds.allowed_towers = allowed_names(preset)


## Resource names of the towers the day allows (empty = all of them).
static func allowed_names(preset: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for name: Variant in preset["towers"]:
		out.append(str(name))
	return out


## Files the result of a finished run locally (journal of a new best included); the
## caller sends it online (Online is an autoload, not visible to this script's tests).
## Returns Daily.record_result()'s dictionary.
static func finish(key: String, waves_cleared: int, ticks: int, journal: CommandLog) -> Dictionary:
	var seconds: int = int(ticks / float(Sim.TICK_RATE))
	var result: Dictionary = Daily.record_result(key, waves_cleared, seconds)
	if result["new_best"] and journal != null:
		journal.save(JOURNAL_PATH)
	return result
