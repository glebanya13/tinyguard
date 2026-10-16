extends SceneTree
## Victory -> "To the map" -> level -> victory ..., many times, on different levels and
## difficulties, with every side system switched on as on a phone: the online layer on a
## fake server (cloud save by the debounce timer), the "do not lose progress" reminder, the
## achievement toast, the difficulty crown, the model prefetch of the map, full effects.
## The run must not print a single engine error (tests/run_all.sh fails on ERROR:).
## godot --headless --fixed-fps 60 --path . --script res://tests/test_end_to_map.gd

const SAVE := "user://test_end_to_map.cfg"
const SESSION := "user://test_end_to_map_session.dat"
const Fakes := preload("res://tests/fakes.gd")
const ROUNDS := 20

var fails := 0
var _online_on: bool = true
var _fake: Fakes.FakeFirebase = null


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	SessionStore.path = SESSION
	LevelCatalog.erase_all()
	SessionStore.clear()
	GameSettings.set_effects(GameSettings.FX_FULL)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _configure_online() -> void:
	_fake = Fakes.FakeFirebase.new()
	var online: Node = root.get_node("Online")
	var t := Fakes.FakeTransport.new()
	t.handler = _fake.handle
	online.setup("test-key", "test-project", t)
	online.auth.backoff_scale = 0.0
	online.firestore.backoff_scale = 0.0
	online.auto_sync = true
	online.sync_debounce = 0.05
	online.sync_min_gap = 0.0
	await online.start()


## Opens level `id` from the map like the Play button does.
func _play_from_map(id: int, difficulty: int) -> Node:
	LevelCatalog.selected_id = id
	LevelCatalog.endless = false
	LevelCatalog.difficulty = difficulty
	LevelCatalog.tutorial = false
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(12)
	return current_scene


## Wins the battle fast: one real wave is on the field, then the last one is "cleared".
func _win(main: Node) -> void:
	var wm: WaveManager = main.get_node("WaveManager")
	wm.start_next_wave()
	await _frames(40)
	wm.current_wave = wm.plan.wave_count
	wm.all_waves_cleared.emit()
	await _frames(6)


func _to_map(main: Node) -> void:
	var hud: Hud = main.get_node("HUD")
	hud._map_button.pressed.emit()  # the real button
	await _frames(30)


## The first launch: the tutorial level, "To the map" on its closing card (or the skip).
func _tutorial_to_map(skip: bool) -> void:
	LevelCatalog.selected_id = 1
	LevelCatalog.endless = false
	LevelCatalog.difficulty = 0
	LevelCatalog.tutorial = true
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(12)
	var main := current_scene
	var tutorial: Tutorial = main.guide.tutorial
	check(tutorial != null, "the tutorial is running")
	OS.delay_msec(Tutorial.MODAL_GUARD_MS + 100)
	if skip:
		tutorial.press_secondary()  # "Skip" asks first
		OS.delay_msec(Tutorial.MODAL_GUARD_MS + 100)
		tutorial.press_primary()
	else:
		tutorial._enter(Tutorial.Step.DONE)
		OS.delay_msec(Tutorial.MODAL_GUARD_MS + 100)
		tutorial.press_primary()
	await _frames(30)
	var scene := current_scene
	check(scene != null and scene.has_method("_select"), "tutorial (skip=%s) -> map" % skip)
	paused = false
	await _frames(10)


func _run() -> void:
	if _online_on:
		await _configure_online()
	await _tutorial_to_map(false)
	await _tutorial_to_map(true)
	var done: int = 0
	for round_index in ROUNDS:
		var id: int = 1 + round_index % 6
		var difficulty: int = 0 if id == 1 else (round_index / 6) % 3
		LevelCatalog.data().set_value("progress", "unlocked", 6)
		for d in difficulty:
			LevelCatalog.data().set_value("progress", "crown_%d" % id, d)
		var main: Node = await _play_from_map(id, difficulty)
		if main == null or not main.has_method("_on_map_pressed"):
			check(false, "round %d: level %d did not load" % [round_index, id])
			break
		await _win(main)
		if not main.battle_end.ended:
			check(false, "round %d: no end screen" % round_index)
			break
		await _to_map(main)
		var scene := current_scene
		if scene == null or not scene.has_method("_select"):
			check(false, "round %d: map did not open" % round_index)
			break
		paused = false
		await _frames(10)
		if round_index == 0:
			var reminder: Control = scene._reminder
			check(reminder.visible, "the first win shows the 'do not lose progress' card")
		done += 1
		# Alternate: leave the map at once, or let the prefetch finish first.
		if round_index % 2 == 1:
			await _frames(40)
	check(done == ROUNDS, "%d / %d victory -> map -> level cycles survived" % [done, ROUNDS])
	check(LevelCatalog.stars(1) >= 1, "level 1 was booked as won")
	await _frames(60)  # the debounced cloud save fires on the map
	LevelCatalog.erase_all()
	SessionStore.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
