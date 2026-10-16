class_name BattleEnd
extends RefCounted
## Statistics of a battle and its end: victory (stars), defeat (siege record, tips),
## or a co-op match that ended another way. Shows the end screen and pauses the tree.

## The end screen is up (victory, defeat or a closed co-op match).
signal finished(victory: bool, stars: int)

const DEFEAT_TIPS: Array[String] = [
	"TIP_FROST", "TIP_SWORD", "TIP_STARS", "TIP_WOOD", "TIP_LOOP", "TIP_LANES"
]

var ended: bool = false
var waves_cleared: int = 0
## Battle summary for the end screen.
var stats := {"kills": 0, "gold": 0, "wood": 0, "towers": 0, "time": 0.0}
## Set by Main when this is a co-op match.
var coop: CoopBattle = null

var _tree: SceneTree = null
var _sim: Sim = null
var _commands: GameCommands = null
## Date of the daily challenge being played ("" = a normal battle).
var _daily_key: String = ""
var _level: Dictionary = {}
var _endless: bool = false
var _game_state: GameState = null
var _wave_manager: WaveManager = null
var _build_manager: BuildManager = null
var _hero: Hero = null
var _hud: Hud = null
var _victory_sound: AudioStreamPlayer = null
var _defeat_sound: AudioStreamPlayer = null
## Siege record of the level when the run began (the end screen compares with it, because
## the record is saved after every wave, not only at the end).
var _record_at_start: int = 0
## Highest wave already sent to the online table by flush_progress().
var _submitted_wave: int = 0


## `commands` already knows the game state, build manager, hero and sim (wired by Main).
func setup(
	tree: SceneTree,
	level: Dictionary,
	endless: bool,
	commands: GameCommands,
	wave_manager: WaveManager,
	hud: Hud,
	victory_sound: AudioStreamPlayer,
	defeat_sound: AudioStreamPlayer,
	daily_key: String
) -> void:
	_tree = tree
	_sim = commands.sim
	_commands = commands
	_daily_key = daily_key
	_level = level
	_endless = endless
	_game_state = commands.game_state
	_wave_manager = wave_manager
	_build_manager = commands.build_manager
	_hero = commands.hero
	_hud = hud
	_victory_sound = victory_sound
	_defeat_sound = defeat_sound
	if endless and daily_key == "":
		_record_at_start = LevelCatalog.endless_record(int(level["id"]))
	wave_manager.wave_cleared.connect(_on_wave_cleared)
	wave_manager.enemy_killed.connect(count_kill)
	# Deferred: the last enemy may leak in the same emission chain (it still has to
	# take its lives), so the stars are counted after the lives are final.
	wave_manager.all_waves_cleared.connect(on_all_waves_cleared, CONNECT_DEFERRED)
	_game_state.defeated.connect(on_defeated)


## Every cleared wave of a siege saves the record at once: a killed app or a dead phone
## keeps what was reached.
func _on_wave_cleared(wave: int) -> void:
	waves_cleared = maxi(waves_cleared, wave)
	if _endless and _daily_key == "":
		LevelCatalog.save_endless(int(_level["id"]), waves_cleared)


## The app goes to the background or closes: writes the save and sends a siege record that
## is higher than the old one (the online table keeps only higher ones).
func flush_progress() -> void:
	if _endless and _daily_key == "" and not ended and waves_cleared > 0:
		LevelCatalog.save_endless(int(_level["id"]), waves_cleared)
		if waves_cleared > _record_at_start and waves_cleared > _submitted_wave:
			_submitted_wave = waves_cleared
			Online.submit_record(int(_level["id"]), waves_cleared)
	LevelCatalog.flush()


func count_kill(reward: int) -> void:
	stats["kills"] += 1
	stats["gold"] += reward


func count_wood(amount: int) -> void:
	stats["wood"] += amount


func count_tower() -> void:
	stats["towers"] += 1


## Real seconds of the battle, also at x2.
func add_time(delta: float) -> void:
	stats["time"] += delta / Engine.time_scale


func on_all_waves_cleared() -> void:
	if _game_state.is_defeated or ended:
		return
	var stars: int = LevelCatalog.stars_for(_game_state.lives, _game_state.starting_lives)
	var before: int = Perks.earned_stars()
	LevelCatalog.complete(int(_level["id"]), stars)
	var gained: int = Perks.earned_stars() - before
	_victory_sound.play()
	var line: String = tr("END_STARS_TOTAL") % [Perks.earned_stars(), Perks.max_stars()]
	if gained > 0:
		line = tr("END_STARS_NEW") % [gained, line]
	elif stars < 3:
		line += tr("END_STARS_HINT")
	end_game(tr("HUD_VICTORY"), true, stars, line + "\n")


func on_defeated() -> void:
	if ended:
		return
	_wave_manager.stop()
	_defeat_sound.play()
	if _daily_key != "":
		_end_daily()
		return
	if _endless:
		var id: int = int(_level["id"])
		var old_record: int = _record_at_start
		var record: bool = waves_cleared > old_record
		LevelCatalog.save_endless(id, waves_cleared)
		if record and waves_cleared > _submitted_wave:
			Online.submit_record(id, waves_cleared)
		var title := tr("END_NEW_RECORD") % waves_cleared if record else tr("END_SIEGE_OVER")
		var line := (
			tr("END_SIEGE_STATS")
			% [
				waves_cleared,
				maxi(old_record, waves_cleared),
				Perks.endless_stars(id),
				Perks.ENDLESS_MAX_STARS
			]
		)
		end_game(title, record, 0, line + "\n")
		return
	var tips: Array[String] = DEFEAT_TIPS.duplicate()
	tips.append(tr("TIP_REPAIR") % [_game_state.repair_lives, _game_state.repair_wood])
	end_game(tr("END_DEFEAT"), false, 0, tr("END_TIP") % tr(tips.pick_random()) + "\n")


## Daily challenge over: files the result, shows the day's summary.
func _end_daily() -> void:
	var result: Dictionary = DailyRun.finish(
		_daily_key, waves_cleared, _sim.tick, _commands.journal
	)
	Online.submit_daily(_daily_key, waves_cleared)
	var title: String = tr("DAILY_END_BEST") if result["new_best"] else tr("DAILY_END_OVER")
	var line: String = tr("DAILY_END_STATS") % [waves_cleared, Daily.best_wave(_daily_key)]
	line += "\n" + tr("DAILY_END_STREAK") % result["streak"]
	if result["star"]:
		line += "\n" + tr("DAILY_END_STAR")
	end_game(title, bool(result["new_best"]), 0, line + "\n")


## The co-op match is over for another reason than the battle's own victory or defeat.
func on_coop_match_over(reason: String) -> void:
	if ended:
		return
	var pair: Array = CoopBattle.end_texts(reason)
	_wave_manager.stop()
	end_game(tr(pair[0]), false, 0, tr(pair[1]) + "\n" + tr("COOP_END_NOT_SAVED") + "\n")


func end_game(message: String, victory: bool, stars: int = 0, prefix: String = "") -> void:
	ended = true
	if coop != null:
		_hud.hide_coop_notice()
		coop.leave_later()
	Engine.time_scale = 1.0
	_hero.cancel_order()
	_build_manager.clear_selection()
	_hud.show_end_screen(message, victory, stars, prefix + _stats_summary())
	_tree.paused = true
	finished.emit(victory, stars)


func _stats_summary() -> String:
	var t: int = int(stats["time"])
	var line_1 := tr("END_STATS_1") % [stats["kills"], stats["gold"]]
	var line_2 := tr("END_STATS_2") % [stats["wood"], stats["towers"], floori(t / 60.0), t % 60]
	return line_1 + "\n" + line_2
