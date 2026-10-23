extends SceneTree
## Tests BattleCheckpoint save/load/clear functionality and state restoration in Main.
## Run with: godot --headless --fixed-fps 60 --path . --script res://tests/test_checkpoint.gd

var _failures: int = 0


func _ok(condition: bool, text: String) -> void:
	if condition:
		print("  ok   %s" % text)
	else:
		_failures += 1
		print("  FAIL %s" % text)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("-- 1. BattleCheckpoint basic file operations")
	BattleCheckpoint.clear_checkpoint()
	_ok(not BattleCheckpoint.has_checkpoint(1), "no checkpoint initially")
	_ok(BattleCheckpoint.load_checkpoint().is_empty(), "load_checkpoint returns empty dict")

	var test_data: Dictionary = {
		"level_id": 1,
		"wave": 4,
		"gold": 250,
		"wood": 180,
		"castle_lives": 18,
		"castle_level": 1,
		"sword_level": 1,
		"difficulty": 0,
		"endless": false,
		"towers": [{"slot_id": 0, "type": "archer", "level": 1, "priority": 0}],
		"villagers": {"lots_sold": 2, "lots_bought": 1, "hired": [true, false]},
		"stats": {"kills": 15, "wood": 30, "towers": 1, "time": 45.0}
	}

	var saved: bool = BattleCheckpoint.save_checkpoint(test_data)
	_ok(saved, "save_checkpoint returns true")
	_ok(BattleCheckpoint.has_checkpoint(1), "has_checkpoint(1) returns true")
	_ok(not BattleCheckpoint.has_checkpoint(2), "has_checkpoint(2) returns false")

	var loaded: Dictionary = BattleCheckpoint.load_checkpoint()
	_ok(int(loaded.get("level_id", 0)) == 1, "loaded level_id is 1")
	_ok(int(loaded.get("wave", 0)) == 4, "loaded wave is 4")
	_ok(int(loaded.get("gold", 0)) == 250, "loaded gold is 250")
	_ok(int(loaded.get("wood", 0)) == 180, "loaded wood is 180")
	_ok(int(loaded.get("castle_lives", 0)) == 18, "loaded castle_lives is 18")

	print("-- 2. Main scene restoration from checkpoint")
	LevelCatalog.selected_id = 1
	LevelCatalog.resume_checkpoint = true
	change_scene_to_file("res://scenes/main.tscn")

	for i in 6:
		await process_frame
	for i in 6:
		await physics_frame

	var main_node = current_scene
	_ok(main_node != null, "main scene loaded")
	var gs: GameState = main_node.get_node("GameState")
	var wm: WaveManager = main_node.get_node("WaveManager")
	var hero: Hero = main_node.get_node("Level/Hero")
	var commands: GameCommands = main_node.get_node("GameCommands")

	_ok(gs.gold == 250, "restored GameState gold == 250 (actual: %d)" % gs.gold)
	_ok(gs.wood == 180, "restored GameState wood == 180 (actual: %d)" % gs.wood)
	_ok(gs.lives == 18, "restored GameState lives == 18 (actual: %d)" % gs.lives)
	_ok(gs.castle_level == 1, "restored GameState castle_level == 1 (actual: %d)" % gs.castle_level)
	_ok(hero.sword_level == 1, "restored Hero sword_level == 1 (actual: %d)" % hero.sword_level)
	_ok(wm.current_wave == 4, "restored WaveManager wave == 4 (actual: %d)" % wm.current_wave)

	var slot0: TowerSlot = commands.slots[0]
	_ok(not slot0.is_free(), "slot 0 has tower built")
	if slot0.tower != null:
		_ok(slot0.tower.level == 1, "tower level is 1 (actual: %d)" % slot0.tower.level)
		_ok(
			(
				slot0.tower.data != null
				and slot0.tower.data.resource_path.get_file().get_basename() == "archer"
			),
			"tower type is archer"
		)

	print("-- 3. Cleanup")
	BattleCheckpoint.clear_checkpoint()
	_ok(not BattleCheckpoint.has_checkpoint(1), "checkpoint cleared after cleanup")

	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
