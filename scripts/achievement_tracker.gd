class_name AchievementTracker
extends Node
## Listens to the signals of a battle, counts what achievements need (kills, towers,
## upgrades, wood) and unlocks achievements. Counters are kept in memory and written
## once per wave and at the end of the battle (no disk write per kill). The battle
## knows nothing about achievements except for connecting this node.

## An achievement was just earned (`def` is its entry of resources/achievements.json).
signal unlocked(def: Dictionary)

var _pending: Dictionary = {}
var _dirty: bool = false


## Subscribes to the systems of a battle.
func attach(
	waves: WaveManager, builds: BuildManager, state: GameState, hero: Hero
) -> void:
	waves.enemy_killed.connect(func(_reward: int) -> void: _count("kills_total"))
	waves.wave_cleared.connect(func(_wave: int) -> void: flush())
	waves.all_waves_cleared.connect(flush, CONNECT_DEFERRED)
	builds.tower_built.connect(func(_slot: TowerSlot, _tower: Tower) -> void: _count("towers_built_total"))
	builds.tower_upgraded.connect(func(_slot: TowerSlot, _tower: Tower) -> void: _count("upgrades_total"))
	hero.wood_gathered.connect(func(amount: int, _at: Vector3) -> void: _count("wood_total", amount))
	state.defeated.connect(flush, CONNECT_DEFERRED)


func _exit_tree() -> void:
	if _dirty:
		flush()


## Writes the counters and unlocks what they (and the rest of the save) earn.
func flush() -> void:
	if _dirty:
		for name: String in _pending:
			Achievements.add_stat(name, int(_pending[name]))
		_pending.clear()
		_dirty = false
		LevelCatalog.commit()
	for def in Achievements.check():
		unlocked.emit(def)


func _count(name: String, amount: int = 1) -> void:
	_pending[name] = int(_pending.get(name, 0)) + amount
	_dirty = true
