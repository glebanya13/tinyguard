extends SceneTree
## A checkpoint saved in the middle of a wave continues that wave: the enemies on the map come
## back where they were with their health, those still to come out still come, and felled
## trees stay felled until their own regrow time (playtest 2026-10-24: "the wave starts over",
## "felled trees are back").
## godot --headless --fixed-fps 60 --path . --script res://tests/test_checkpoint_wave.gd

var _failures: int = 0


func _ok(condition: bool, text: String) -> void:
	if condition:
		print("  ok   %s" % text)
	else:
		_failures += 1
		print("  FAIL %s" % text)


func _initialize() -> void:
	_run.call_deferred()


func _load_level(resume: bool) -> Node:
	LevelCatalog.selected_id = 1
	LevelCatalog.endless = false
	LevelCatalog.tutorial = false
	LevelCatalog.inspect_map = false
	LevelCatalog.resume_checkpoint = resume
	change_scene_to_file("res://scenes/main.tscn")
	for i in 6:
		await process_frame
	for i in 6:
		await physics_frame
	var main: Node = current_scene
	(main.get_node("Sim") as Sim).manual = true
	return main


func _run() -> void:
	BattleCheckpoint.clear_checkpoint()
	print("-- 1. A battle in the middle of wave 1, a tree felled")
	var main: Node = await _load_level(false)
	var sim: Sim = main.get_node("Sim")
	var wm: WaveManager = main.get_node("WaveManager")
	wm.start_next_wave()
	for i in 120:
		sim.step()
	var on_map: Array[Enemy] = sim.enemies.duplicate()
	_ok(not on_map.is_empty(), "enemies are on the map (%d)" % on_map.size())
	on_map[0].take_damage(3.0)
	var hurt_health: float = on_map[0].health
	var hurt_progress: float = on_map[0].sim_progress
	var to_come: int = 0
	for spawner: Dictionary in wm._spawners:
		to_come += (spawner["queue"] as Array).size() - int(spawner["index"])
	_ok(to_come > 0, "enemies of the wave are still to come (%d)" % to_come)
	var tree: WoodTree = null
	for candidate: WoodTree in sim.trees:
		if not candidate.is_thicket:
			tree = candidate
			break
	while tree.is_choppable():
		tree.chop(tree.global_position + Vector3.RIGHT)
	var regrow_in: int = tree.regrow_at() - sim.tick
	var tree_index: int = sim.trees.find(tree)
	var half: WoodTree = sim.trees[tree_index + 1]
	half.chop(half.global_position + Vector3.RIGHT)
	var half_hits: int = half.hits_left()
	main._save_checkpoint()
	var saved: Dictionary = BattleCheckpoint.load_checkpoint()
	_ok(int(saved.get("wave", 0)) == 1, "the checkpoint is on wave 1")
	_ok(saved.has("waves"), "the running waves are saved")

	print("-- 2. Continue")
	main = await _load_level(true)
	sim = main.get_node("Sim")
	wm = main.get_node("WaveManager")
	_ok(wm.current_wave == 1, "wave 1 is running again, not restarted (%d)" % wm.current_wave)
	_ok(
		sim.enemies.size() == on_map.size(),
		"the enemies on the map are back (%d / %d)" % [sim.enemies.size(), on_map.size()]
	)
	# The clock ran a few steps between the restore and this check: the enemies walked a bit.
	var walked: float = sim.tick * Sim.TICK_DT * 3.0 + 0.01
	var match_found: bool = false
	for enemy: Enemy in sim.enemies:
		if (
			absf(enemy.sim_progress - hurt_progress) < walked
			and absf(enemy.health - hurt_health) < 0.01
		):
			match_found = true
	_ok(match_found, "the hurt enemy is back where it was with its health")
	var still_to_come: int = 0
	for spawner: Dictionary in wm._spawners:
		still_to_come += (spawner["queue"] as Array).size() - int(spawner["index"])
	_ok(still_to_come == to_come, "the rest of the wave still comes (%d)" % still_to_come)
	_ok(wm.is_wave_active(), "the wave counts as running")
	var back: WoodTree = sim.trees[tree_index]
	_ok(not back.is_choppable(), "the felled tree is still down")
	_ok(
		absi(back.regrow_at() - regrow_in) <= 1,  # restored at step 0 of the new clock
		"it grows back on its own clock (%d / %d)" % [back.regrow_at(), regrow_in]
	)
	_ok(
		(sim.trees[tree_index + 1] as WoodTree).hits_left() == half_hits,
		"a half-chopped tree keeps its hits"
	)
	var before: int = sim.enemies.size() + still_to_come
	var gone: int = 0
	for i in 30 * 120:
		sim.step()
		if not wm._remaining.has(1):
			gone = 1
			break
	_ok(gone == 1, "the continued wave can be finished (%d enemies were left)" % before)

	BattleCheckpoint.clear_checkpoint()
	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
