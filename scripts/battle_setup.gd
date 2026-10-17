class_name BattleSetup
extends RefCounted
## Pure rules for starting a battle, split from main.gd: what the replay journal header
## says, which difficulty and perks apply, and the starting resources. No nodes, no
## state: everything comes in as arguments, so a replay and a live battle compute the
## same numbers.


## What a replay needs to know about the battle it reproduces. `coop_config` is empty
## outside co-op; `daily_key` is "" outside the daily challenge.
static func journal_header(
	level: Dictionary,
	endless: bool,
	seed_value: int,
	perks: Dictionary,
	difficulty: int,
	record: bool,
	daily_key: String,
	coop_config: Dictionary
) -> Dictionary:
	var header := {
		"sim_version": Sim.VERSION,
		"tick_rate": Sim.TICK_RATE,
		"level": int(level["id"]),
		"endless": endless,
		"seed": seed_value,
		"perks": perks,
	}
	if difficulty > 0:
		header["difficulty"] = difficulty
	if record:
		header["record"] = 1
	if daily_key != "":
		header["daily"] = daily_key
	if not coop_config.is_empty():
		header["coop"] = 1
		header["delay"] = int(coop_config["delay"])
	return header


## Difficulty of a battle: the player's choice on the map; co-op takes the host's choice
## from the room; the record run and the daily challenge are always Normal.
static func chosen_difficulty(coop_config: Dictionary, endless: bool, chosen: int) -> int:
	if not coop_config.is_empty():
		return int(coop_config.get("difficulty", 0))
	if endless:
		return 0
	return chosen


## The player's permanent perks by name. Co-op is an even start: nobody brings perks.
static func current_perks(keys: Array[StringName], coop: bool) -> Dictionary:
	var out := {}
	for key: StringName in keys:
		out[String(key)] = 0 if coop else Perks.value(key)
	return out


## Starting resources of a level with the difficulty's lives and the bonuses of `perks`
## (gold_start, wood_start, walls); fed to GameState.configure().
static func start_resources(level: Dictionary, difficulty: int, perks: Dictionary) -> Dictionary:
	var start: Dictionary = level["start"].duplicate()
	start["lives"] = maxi(
		roundi(float(start["lives"]) * float(Balance.difficulty(difficulty)["lives"])), 1
	)
	start["gold"] = int(start["gold"]) + int(perks.get("gold_start", 0))
	start["wood"] = int(start["wood"]) + int(perks.get("wood_start", 0))
	start["lives"] = int(start["lives"]) + int(perks.get("walls", 0))
	return start
