extends SceneTree
## Tutorial on level 1, advanced by the real game actions (wood from the hero,
## gold from kills, selecting a slot and building through BuildManager, walking,
## the whirlwind, a real wave, an upgrade) and the wave clock it holds.
## A normal level 1 has no tutorial and keeps its first delay.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_tutorial.gd

const SAVE := "user://test_tutorial.cfg"

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	LevelCatalog.erase_all()
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	Onboarding.set_local_nickname("Тестер", "тестер", false)
	check(Onboarding.route(PlayerProfile.local()) == Onboarding.Route.TUTORIAL, "route: tutorial")
	Onboarding.start_tutorial(self)
	await _frames(10)
	var main: Node = current_scene
	var tutorial := main.get_node_or_null("Tutorial") as Tutorial
	check(tutorial != null, "tutorial overlay on level 1 in tutorial mode")
	if tutorial == null:
		_finish()
		return
	var gs: GameState = main.get_node("GameState")
	var wm: WaveManager = main.get_node("WaveManager")
	var bm: BuildManager = main.get_node("BuildManager")
	var hero: Hero = main.get_node("Level/Hero")
	check(tutorial.current_step() == Tutorial.Step.WELCOME, "starts with the welcome")
	check(wm.time_to_next_wave() > 1000.0 and wm.current_wave == 0, "wave clock held")

	tutorial.press_primary()
	check(
		tutorial.current_step() == Tutorial.Step.WELCOME, "an instant (accidental) tap is ignored"
	)
	OS.delay_msec(Tutorial.MODAL_GUARD_MS + 50)
	tutorial.press_primary()
	check(tutorial.current_step() == Tutorial.Step.CHOP, "welcome -> chop")
	await _frames(120)
	check(tutorial.current_step() == Tutorial.Step.CHOP, "no progress without an action")

	hero.wood_gathered.emit(6, hero.global_position)
	check(tutorial.current_step() == Tutorial.Step.CHOP, "not enough wood yet")
	hero.wood_gathered.emit(6, hero.global_position)
	check(tutorial.current_step() == Tutorial.Step.SLIMES, "wood chopped -> slimes")
	check(wm.current_wave == 1, "the first slimes come")
	check(wm.time_to_next_wave() > 1000.0, "next wave still held")

	wm.enemy_killed.emit(15)  # the reward main adds as gold
	check(tutorial.current_step() == Tutorial.Step.SELECT, "gold earned -> select a slot")
	var slot: TowerSlot = null
	for node in get_nodes_in_group(TowerSlot.GROUP):
		if (node as TowerSlot).is_free():
			slot = node
			break
	bm.select_slot(slot)
	check(tutorial.current_step() == Tutorial.Step.BUILD, "slot selected -> build")
	bm.clear_selection()
	check(tutorial.current_step() == Tutorial.Step.SELECT, "deselected -> back to select")
	bm.select_slot(slot)
	check(bm.build_on(slot, bm.tower_types[0]), "tower built through BuildManager")
	check(tutorial.current_step() == Tutorial.Step.MOVE, "built -> move the hero")

	await _frames(5)
	check(tutorial.current_step() == Tutorial.Step.MOVE, "standing still does not count")
	hero.global_position += Vector3(Tutorial.MOVE_DISTANCE + 0.5, 0.0, 0.0)
	await _frames(2)
	check(tutorial.current_step() == Tutorial.Step.SPIN, "walked -> whirlwind")
	check(hero.try_spin(), "whirlwind used")
	await _frames(2)
	check(tutorial.current_step() == Tutorial.Step.WAVE, "whirlwind -> real wave")
	check(wm.time_to_next_wave() <= Tutorial.WAVE_DELAY + 0.1, "real wave released")
	var waited: int = 0
	while wm.current_wave < 2 and waited < 600:
		await process_frame
		waited += 1
	check(wm.current_wave == 2, "the wave starts on its own")
	check(
		absf(wm.time_to_next_wave() - wm.plan.wave_duration) < 1.0,
		"normal 30 s clock from now on (%.1f)" % wm.time_to_next_wave()
	)
	wm.wave_cleared.emit(2)
	check(tutorial.current_step() == Tutorial.Step.UPGRADE, "wave cleared -> upgrade")
	gs.add_gold(200)
	gs.add_wood(200)
	check(bm.upgrade(slot), "tower upgraded through BuildManager")
	check(tutorial.current_step() == Tutorial.Step.DONE, "upgraded -> done")
	var p: Dictionary = PlayerProfile.local()
	check(
		p["tutorialVersionCompleted"] == Onboarding.TUTORIAL_VERSION and p["onboardingCompleted"],
		"completion saved"
	)
	check(Onboarding.route(p) == Onboarding.Route.MAP, "next launch -> map")

	LevelCatalog.tutorial = false
	paused = false
	await _frames(90)  # let the build/upgrade effects finish before the scene goes
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(10)
	var normal: Node = current_scene
	var normal_waves: WaveManager = normal.get_node("WaveManager")
	check(normal.get_node_or_null("Tutorial") == null, "normal level 1: no tutorial")
	check(
		absf(normal_waves.time_to_next_wave() - normal_waves.plan.first_delay) < 1.0,
		"normal level keeps its first delay"
	)
	_finish()


func _finish() -> void:
	LevelCatalog.erase_all()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
