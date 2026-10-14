extends SceneTree
## The last enemy of the last wave leaks: the stars must count that lost life
## (and a lethal leak must be a defeat, not a victory first).
## godot --headless --fixed-fps 60 --path . --script res://tests/test_endgame.gd

const SAVE := "user://test_endgame.cfg"

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	LevelCatalog.selected_id = 1
	LevelCatalog.endless = false
	LevelCatalog.tutorial = false
	_run.call_deferred()


## Starts level 1, makes the next enemy that is gone the last one and lets one
## slime with `damage` lives of damage walk into the castle.
func _leak_last_enemy(damage: int) -> Dictionary:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 10:
		await process_frame
	var main := current_scene
	var gs: GameState = main.get_node("GameState")
	var wm: WaveManager = main.get_node("WaveManager")
	wm.stop()
	wm._stopped = false
	wm.current_wave = wm.plan.wave_count  # no more waves
	var slime: EnemyData = (load("res://resources/enemies/slime.tres") as EnemyData).duplicate()
	slime.base_damage = damage
	var path: Path3D = wm.get_paths()[0]
	wm.spawn_extra(slime, 1.0, path.curve.get_baked_length() - 0.05, wm.current_wave, path)
	for i in 30:
		await process_frame
	return {"main": main, "gs": gs}


func _run() -> void:
	var start: int = int(LevelCatalog.get_level(1)["start"]["lives"])
	var run: Dictionary = await _leak_last_enemy(1)
	var gs: GameState = run["gs"]
	check(gs.lives == start - 1, "the last slime took a life (%d)" % gs.lives)
	check(run["main"]._ended, "level ended")
	check(LevelCatalog.stars(1) == 2, "a leak at the very end costs the third star")
	paused = false
	run = await _leak_last_enemy(start)
	gs = run["gs"]
	check(gs.is_defeated, "a lethal last leak is a defeat")
	check(LevelCatalog.stars(1) == 2, "no second victory is booked")
	paused = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
