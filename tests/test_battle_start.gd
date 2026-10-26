extends SceneTree
## The start of a battle: the map inspection before "To battle!" (free camera, the knight and
## the battle clock wait, no wood), the first wave on the timer shown, the early wave call only
## on a clear field, the daily challenge's timer, and a checkpoint resumed with the knight's
## place and the wave clock as they were.
## Run with: godot --headless --fixed-fps 60 --path . --script res://tests/test_battle_start.gd

const MAIN_SCENE := "res://scenes/main.tscn"

var _failures: int = 0


func _ok(condition: bool, text: String) -> void:
	if condition:
		print("  ok   %s" % text)
	else:
		_failures += 1
		print("  FAIL %s" % text)


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_battle_start.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	_run.call_deferred()


## Loads the level as the map screen starts it and waits until it is built.
func _load(inspect: bool) -> Node:
	paused = false
	LevelCatalog.inspect_map = inspect
	var old_scene: Node = current_scene
	change_scene_to_file(MAIN_SCENE)
	while current_scene == null or current_scene == old_scene or not current_scene.has_node("Sim"):
		await process_frame
	var main: Node = current_scene
	var hero: Hero = main.get_node("Level/Hero")
	(main.get_node("Sim") as Sim).manual = true  # the test drives the clock
	for i in 200:
		if hero.walk_grid != null:
			break
		await process_frame
	for i in 3:
		await process_frame
	return main


func _steps(sim: Sim, count: int) -> void:
	for i in count:
		sim.step()


func _visible(hud: Node, path: String) -> bool:
	var node: CanvasItem = hud.get_node_or_null(path) as CanvasItem
	return node != null and node.is_visible_in_tree()


func _run() -> void:
	BattleCheckpoint.clear_checkpoint()
	await _test_inspection_and_start()
	await _test_daily_timer()
	await _test_checkpoint_resume()
	BattleCheckpoint.clear_checkpoint()
	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _test_inspection_and_start() -> void:
	print("-- 1. Map inspection before 'To battle!'")
	LevelCatalog.selected_id = 1
	LevelCatalog.daily_key = ""
	LevelCatalog.endless = false
	var main: Node = await _load(true)
	var sim: Sim = main.get_node("Sim")
	var hero: Hero = main.get_node("Level/Hero")
	var hud: Hud = main.get_node("HUD")
	var wm: WaveManager = main.get_node("WaveManager")
	var gs: GameState = main.get_node("GameState")
	var cam: CameraFollow = main.get_node("Camera")
	var plan_delay: float = wm.plan.first_delay
	_ok(not LevelCatalog.inspect_map, "the inspection request is used once")
	_ok(not sim.running and sim.tick == 0, "the battle clock stands during the inspection")
	_ok(hero.controls_locked, "the knight is locked")
	_ok(cam.free_look, "the camera is free (no scripted flight)")
	_ok(_visible(hud, "Root/StartBattleButton"), "'To battle!' is shown")
	_ok(not _visible(hud, "Root/TopBar/CallWaveButton"), "no early wave call yet")
	_ok(not _visible(hud, "Root/TopBar/WaveTimerPill"), "no running wave timer yet")
	_ok(not _visible(hud, "Root/AttackButton"), "the sword button is hidden")
	var start_pos: Vector3 = hero.global_position
	hero.move_to(start_pos + Vector3(3.0, 0.0, 0.0))
	hero.joystick_vector = Vector2(1.0, 0.0)
	for i in 30:
		await physics_frame
	_ok(hero.global_position.distance_to(start_pos) < 0.05, "the knight does not walk")
	_ok(not hero.has_order(), "the knight takes no orders")
	_ok(not hero.can_attack() and not hero.try_attack(), "the knight cannot swing (no wood)")
	var wood: int = gs.wood
	for i in 30:
		await process_frame
	_ok(gs.wood == wood and sim.tick == 0, "no resources come in before the battle")
	var cam_before: Vector3 = cam.global_position
	cam.pan_by(Vector3(-2.0, 0.0, 1.0))
	_ok(cam.global_position != cam_before, "the player pans the camera over the map")
	var normal_size: float = cam._default_size
	cam.zoom_by(1.6)
	_ok(cam._target_size > normal_size * 1.2, "the player zooms the map out to look around")

	print("-- 2. 'To battle!' starts the clock once; the timer is the real one")
	(hud.get_node("Root/StartBattleButton") as Button).pressed.emit()
	_ok(sim.running, "the battle clock runs")
	_ok(not hero.controls_locked and not cam.free_look, "the knight is free, the camera on him")
	_ok(
		is_equal_approx(cam._target_size, normal_size),
		"the camera goes back to the normal zoom (%.1f / %.1f)" % [cam._target_size, normal_size]
	)
	_ok(not _visible(hud, "Root/StartBattleButton"), "'To battle!' is gone")
	_ok(wm.current_wave == 0, "no wave at once")
	_ok(is_equal_approx(wm.time_to_next_wave(), plan_delay), "the first wave after first_delay")
	await process_frame
	_ok(_visible(hud, "Root/TopBar/WaveTimerPill"), "the wave timer is on screen")
	var label: Label = hud.find_child("WaveTimerLabel", true, false) as Label
	var secs: int = ceili(plan_delay)
	_ok(
		label != null and label.text == "%d:%02d" % [secs / 60, secs % 60],
		"the timer shows the real delay (%s)" % (label.text if label else "?")
	)
	main.call("_begin_battle")  # a second press changes nothing
	_ok(wm.current_wave == 0, "a second 'To battle!' starts nothing")
	_steps(sim, Sim.ticks(plan_delay) - 2)
	_ok(wm.current_wave == 0, "no wave before the timer runs out")
	_steps(sim, 3)
	_ok(wm.current_wave == 1, "wave 1 when the timer runs out")

	print("-- 3. The early call needs a clear field")
	await process_frame
	_ok(wm.is_wave_active(), "wave 1 is on the field")
	_ok(not _visible(hud, "Root/TopBar/CallWaveButton"), "no early call while enemies are about")
	_ok(_visible(hud, "Root/TopBar/WaveTimerPill"), "the timer still counts down")
	var gold: int = gs.gold
	(hud.get_node("Root/TopBar/CallWaveButton") as Button).pressed.emit()
	_ok(wm.current_wave == 1 and gs.gold == gold, "pressing it anyway skips nothing")
	for enemy: Enemy in sim.enemies.duplicate():
		enemy.take_damage(100000.0)
	_steps(sim, Sim.ticks(wm.plan.spawn_window) + 30)
	for enemy: Enemy in sim.enemies.duplicate():
		enemy.take_damage(100000.0)
	_steps(sim, 2)
	if wm.current_wave == 1 and not wm.is_wave_active() and wm.time_to_next_wave() > 0.0:
		await process_frame
		_ok(_visible(hud, "Root/TopBar/CallWaveButton"), "a clear field: the early call is offered")
		gold = gs.gold
		(hud.get_node("Root/TopBar/CallWaveButton") as Button).pressed.emit()
		_ok(wm.current_wave == 2 and gs.gold > gold, "the early call starts wave 2 with a bonus")
		(hud.get_node("Root/TopBar/CallWaveButton") as Button).pressed.emit()
		_ok(wm.current_wave == 2, "and cannot call wave 3 right after it")
	else:
		_ok(false, "could not clear wave 1 (wave %d)" % wm.current_wave)


func _test_daily_timer() -> void:
	print("-- 4. The daily challenge has the same inspection and wave timer")
	DailyRun.select(Daily.today_key())
	var main: Node = await _load(true)
	var sim: Sim = main.get_node("Sim")
	var hud: Hud = main.get_node("HUD")
	var wm: WaveManager = main.get_node("WaveManager")
	_ok(not sim.running and _visible(hud, "Root/StartBattleButton"), "daily: inspection first")
	(hud.get_node("Root/StartBattleButton") as Button).pressed.emit()
	await process_frame
	_ok(wm.time_to_next_wave() > 0.0, "daily: the first wave is on the clock")
	_ok(_visible(hud, "Root/TopBar/WaveTimerPill"), "daily: the wave timer is on screen")
	_steps(sim, Sim.ticks(wm.plan.first_delay) + 1)
	await process_frame
	_ok(wm.current_wave == 1, "daily: wave 1 came on time")
	_ok(_visible(hud, "Root/TopBar/WaveTimerPill"), "daily: the timer counts to wave 2")
	LevelCatalog.daily_key = ""
	LevelCatalog.endless = false


func _test_checkpoint_resume() -> void:
	print("-- 5. 'Continue' restores the knight's place and the wave clock")
	LevelCatalog.selected_id = 1
	var main: Node = await _load(false)
	var sim: Sim = main.get_node("Sim")
	var hero: Hero = main.get_node("Level/Hero")
	var wm: WaveManager = main.get_node("WaveManager")
	_steps(sim, 3)
	wm.start_next_wave()
	wm.start_next_wave()
	for enemy: Enemy in sim.enemies.duplicate():
		enemy.take_damage(100000.0)
	_steps(sim, Sim.ticks(wm.plan.window_for(2)) + 30)
	for enemy: Enemy in sim.enemies.duplicate():
		enemy.take_damage(100000.0)
	_steps(sim, 2)
	var spot := Vector3(hero.global_position.x + 1.5, 0.0, hero.global_position.z - 1.0)
	hero.global_position = spot
	var clock: float = wm.time_to_next_wave()
	main.call("_save_checkpoint")
	var cp: Dictionary = BattleCheckpoint.load_checkpoint()
	_ok(int(cp.get("wave", -1)) == wm.cleared_through(), "saved the last cleared wave")
	_ok(absf(float(cp.get("next_wave_in", -1.0)) - clock) < 0.01, "saved the wave clock")
	_ok((cp.get("hero_pos", []) as Array).size() == 2, "saved the knight's place")
	var saved_wave: int = int(cp.get("wave", 0))

	LevelCatalog.resume_checkpoint = true
	main = await _load(true)
	sim = main.get_node("Sim")
	hero = main.get_node("Level/Hero")
	wm = main.get_node("WaveManager")
	var hud: Hud = main.get_node("HUD")
	_ok(wm.current_wave == saved_wave, "resumed at wave %d" % saved_wave)
	_ok(
		(
			Vector2(hero.global_position.x, hero.global_position.z).distance_to(
				Vector2(spot.x, spot.z)
			)
			< 0.05
		),
		"the knight stands where he was"
	)
	_ok(not sim.running and hero.controls_locked, "resume: the map inspection first")
	_ok(absf(wm.time_to_next_wave() - clock) < 0.05, "the wave clock is as it was, not 5 s")
	for i in 20:
		await process_frame
	_ok(absf(wm.time_to_next_wave() - clock) < 0.05, "the clock stands during the inspection")
	(hud.get_node("Root/StartBattleButton") as Button).pressed.emit()
	_steps(sim, Sim.ticks(clock) - 2)
	_ok(wm.current_wave == saved_wave, "no wave before the saved clock runs out")
	_steps(sim, 3)
	_ok(wm.current_wave == saved_wave + 1, "the next wave on the saved clock")

	print("-- 6. A wave still running is kept with its enemies (not played again)")
	_steps(sim, 3)
	_ok(wm.is_wave_active(), "a wave is on the field")
	main.call("_save_checkpoint")
	cp = BattleCheckpoint.load_checkpoint()
	_ok(int(cp.get("wave", -1)) == saved_wave + 1, "the running wave is the checkpoint's wave")
	_ok(int(cp.get("cleared", -1)) == saved_wave, "it is not counted as cleared")
	var waves: Dictionary = cp.get("waves", {})
	_ok(
		(
			not (waves.get("enemies", []) as Array).is_empty()
			or not (waves.get("spawners", []) as Array).is_empty()
		),
		"its enemies are saved"
	)
