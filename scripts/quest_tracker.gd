class_name QuestTracker
extends Node
## Feeds the daily quests from the signals of a battle (like AchievementTracker):
## counters in memory, written once per wave and at the end. The battle knows nothing
## about quests except for connecting this node; the simulation is never touched.

## A quest reached its target; `def` is the quest, `gems` what it paid.
signal quest_done(def: Dictionary, gems: int)

var _batch: Dictionary = {}


func attach(waves: WaveManager, builds: BuildManager, state: GameState) -> void:
	waves.enemy_killed.connect(func(_reward: int) -> void: _count("kills"))
	waves.wave_cleared.connect(_on_wave_cleared)
	waves.all_waves_cleared.connect(flush, CONNECT_DEFERRED)
	builds.tower_built.connect(func(_slot: TowerSlot, _tower: Tower) -> void: _count("towers"))
	builds.tower_upgraded.connect(func(_slot: TowerSlot, _tower: Tower) -> void: _count("upgrades"))
	state.defeated.connect(flush, CONNECT_DEFERRED)


func _exit_tree() -> void:
	flush()


func flush() -> void:
	if _batch.is_empty():
		return
	var batch: Dictionary = _batch
	_batch = {}
	for done in Quests.add(Daily.today_key(), batch):
		quest_done.emit(done["def"], int(done["gems"]))


func _on_wave_cleared(wave: int) -> void:
	_batch["wave"] = maxi(int(_batch.get("wave", 0)), wave)
	flush()


func _count(metric: String) -> void:
	_batch[metric] = int(_batch.get(metric, 0)) + 1
