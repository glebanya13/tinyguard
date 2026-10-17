extends SceneTree
## Protection against a weak phone: the step budget of the clock (no spiral of death),
## the clock forgetting the time spent in the background, the quality guard lowering only
## visual settings, the crash note and the diagnostics overlay text.
## godot --headless --path . --script res://tests/test_quality_guard.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	GameSettings.config_path = "user://test_guard_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.config_path))
	GameSettings._forced = -1  # ignore BIMBLEGUARD_FX
	_run.call_deferred()


func _run() -> void:
	_test_budget()
	_test_lifecycle()
	_test_guard()
	_test_tiers()
	_test_trace_and_overlay()
	_test_ladder()
	_test_crash_penalty()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _slow_sim() -> Sim:
	var sim := Sim.new()
	root.add_child(sim)
	sim.running = true
	return sim


func _test_budget() -> void:
	# Every step takes 30 ms: far over the 22 ms budget of a frame.
	var sim: Sim = _slow_sim()
	for at in 12:
		sim.schedule_in(at, OS.delay_msec.bind(30))
	sim.advance(0.3)  # nine steps are owed
	check(sim.tick < Sim.MAX_STEPS_PER_FRAME, "slow steps: the frame stops early (%d)" % sim.tick)
	check(sim.tick >= 1, "slow steps: at least one step is always done")
	check(sim.over_budget_frames == 1 and sim.dropped_steps > 0, "slow steps: the debt is counted")
	check(sim.alpha() <= 1.0, "slow steps: the debt is dropped (alpha %.2f)" % sim.alpha())
	var before: int = sim.tick
	sim.advance(Sim.TICK_DT)
	check(sim.tick == before + 1, "after the drop the clock goes on one step per frame")
	sim.free()
	# Manual clock (tests): the budget does not apply, every owed step is done.
	var manual: Sim = _slow_sim()
	manual.manual = true
	for at in 4:
		manual.schedule_in(at, OS.delay_msec.bind(30))
	manual.advance(4.0 * Sim.TICK_DT)
	check(manual.tick == 4, "manual clock ignores the budget (%d steps)" % manual.tick)
	manual.free()


func _test_lifecycle() -> void:
	var sim: Sim = _slow_sim()
	sim.manual = true
	sim.advance(Sim.TICK_DT * 0.9)  # almost a step collected
	check(sim.alpha() > 0.8, "time is collected")
	sim.notification(NOTIFICATION_APPLICATION_PAUSED)
	check(sim.alpha() == 0.0, "going to the background empties the accumulator")
	sim.advance(Sim.TICK_DT * 0.5)
	sim.notification(NOTIFICATION_APPLICATION_RESUMED)
	check(sim.alpha() == 0.0, "returning empties the accumulator")
	sim.free()


func _test_guard() -> void:
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	var guard := QualityGuard.new()
	root.add_child(sun)
	root.add_child(guard)
	QualityGuard.session_level = 0
	GameSettings.cap_effects(GameSettings.FX_FULL)
	guard.setup(sun, root)
	# Quick frames never lower anything, however long they last.
	for i in 2000:
		guard.feed(16.0)
	check(guard.level == 0 and sun.shadow_enabled, "a steady 60 fps changes nothing")
	# Slow frames: one notch per judgement, with a cool-down in between.
	for i in 2000:
		guard.feed(50.0)
	check(guard.level >= 1 and not sun.shadow_enabled, "slow frames: shadows go first")
	for i in 4000:
		guard.feed(50.0)
	check(guard.level == QualityGuard.MAX_LEVEL, "it stops at the last notch (%d)" % guard.level)
	check(GameSettings.effects_now() == GameSettings.FX_OFF, "last notch: no effects")
	check(root.msaa_3d == Viewport.MSAA_DISABLED, "MSAA is switched off")
	# The player's own choice is untouched and the notch is remembered for the session.
	GameSettings.set_effects(GameSettings.FX_FULL)
	check(GameSettings.effects() == GameSettings.FX_FULL, "the saved choice stays what it was")
	check(QualityGuard.session_level == QualityGuard.MAX_LEVEL, "the next battle starts lowered")
	var again := QualityGuard.new()
	var sun2 := DirectionalLight3D.new()
	sun2.shadow_enabled = true
	root.add_child(sun2)
	root.add_child(again)
	again.setup(sun2, root)
	check(not sun2.shadow_enabled and again.level == QualityGuard.MAX_LEVEL, "restored at start")
	# Back to normal for whatever runs next.
	QualityGuard.session_level = 0
	GameSettings.cap_effects(GameSettings.FX_FULL)
	root.msaa_3d = Viewport.MSAA_DISABLED
	for node: Node in [sun, sun2, guard, again]:
		node.free()


func _test_tiers() -> void:
	var low: int = GameSettings.GFX_LOW
	var mid: int = GameSettings.GFX_MEDIUM
	var high: int = GameSettings.GFX_HIGH
	check(GameSettings.classify_device(2048, "Mali-G52 MC2", true) == low, "2 GB phone: low")
	check(GameSettings.classify_device(2800, "Adreno (TM) 619", true) == low, "3 GB phone: low")
	check(
		GameSettings.classify_device(8000, "Mali-G52 MC2", true) == low,
		"weak GPU: low even with RAM"
	)
	check(GameSettings.classify_device(8000, "Adreno (TM) 506", true) == low, "Adreno 5xx: low")
	check(GameSettings.classify_device(8000, "Adreno (TM) 612", true) == low, "Adreno 612: low")
	check(GameSettings.classify_device(8000, "PowerVR Rogue GE8320", true) == low, "PowerVR: low")
	check(GameSettings.classify_device(3700, "Mali-G57 MC2", true) == low, "4 GB phone: low")
	check(GameSettings.classify_device(4700, "Mali-G57 MC2", true) == mid, "5 GB phone: medium")
	# Redmi Note 12: 4G (Snapdragon 685, Adreno 610) and 5G (Snapdragon 4 Gen 1, Adreno 619).
	check(GameSettings.classify_device(7400, "Adreno (TM) 610", true) == low, "Note 12 4G, 8 GB")
	check(GameSettings.classify_device(3800, "Adreno (TM) 610", true) == low, "Note 12 4G, 4 GB")
	check(GameSettings.classify_device(7400, "Adreno (TM) 619", true) == low, "Note 12 5G, 8 GB")
	check(GameSettings.classify_device(3800, "Adreno (TM) 619", true) == low, "Note 12 5G, 4 GB")
	check(GameSettings.classify_device(5600, "Mali-G68 MC4", true) == high, "Note 12 Pro: high")
	check(GameSettings.classify_device(5600, "Adreno (TM) 618", true) == high, "6 GB mid GPU: high")
	check(GameSettings.classify_device(11000, "Adreno (TM) 740", true) == high, "flagship: high")
	check(GameSettings.classify_device(-1, "", true) == mid, "unknown device: medium")
	check(GameSettings.classify_device(1000, "Mali-400", false) == high, "desktop never lowered")
	# The choice is saved; "auto" follows the detected tier, a manual choice wins.
	check(GameSettings.graphics() == GameSettings.GFX_AUTO, "default is auto")
	GameSettings.set_graphics(GameSettings.GFX_LOW)
	check(GameSettings.graphics() == GameSettings.GFX_LOW, "choice is saved")
	check(GameSettings.graphics_tier() == low, "manual low wins")
	GameSettings.set_graphics(99)
	check(GameSettings.graphics() == GameSettings.GFX_HIGH, "out-of-range choice is clamped")
	GameSettings.set_graphics(GameSettings.GFX_AUTO)
	GameSettings._detected = mid
	check(GameSettings.graphics_tier() == mid, "auto follows the detected tier")
	# A battle on the low tier starts with shadows, MSAA and part of the effects off.
	GameSettings.set_graphics(GameSettings.GFX_LOW)
	QualityGuard.session_level = 0
	GameSettings.cap_effects(GameSettings.FX_FULL)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	var guard := QualityGuard.new()
	root.add_child(sun)
	root.add_child(guard)
	guard.setup(sun, root)
	check(guard.level == 3 and not sun.shadow_enabled, "low tier: starts lowered (shadows off)")
	check(GameSettings.effects_now() == GameSettings.FX_MIN, "low tier: fewer effects")
	check(GameSettings.effects() == GameSettings.FX_FULL, "the saved effects choice is untouched")
	# The high tier starts untouched, and a change of choice resets the guard.
	QualityGuard.session_level = 4
	QualityGuard.reset_session()
	check(
		QualityGuard.session_level == 0 and GameSettings.effects_now() == GameSettings.FX_FULL,
		"reset"
	)
	GameSettings.set_graphics(GameSettings.GFX_HIGH)
	var sun2 := DirectionalLight3D.new()
	sun2.shadow_enabled = true
	var guard2 := QualityGuard.new()
	root.add_child(sun2)
	root.add_child(guard2)
	guard2.setup(sun2, root)
	check(guard2.level == 0 and sun2.shadow_enabled, "high tier: nothing lowered")
	GameSettings.set_graphics(GameSettings.GFX_MEDIUM)
	var sun3 := DirectionalLight3D.new()
	sun3.shadow_enabled = true
	var guard3 := QualityGuard.new()
	root.add_child(sun3)
	root.add_child(guard3)
	guard3.setup(sun3, root)
	check(guard3.level == 0 and sun3.shadow_enabled, "medium tier: shadows stay (smaller map)")
	check(
		ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d.mobile", 9) == 0,
		"MSAA is off by default on phones (Godot issues 97967 / 124258)"
	)
	sun3.free()
	guard3.free()
	GameSettings.set_graphics(GameSettings.GFX_AUTO)
	GameSettings._detected = 0
	QualityGuard.reset_session()
	root.msaa_3d = Viewport.MSAA_DISABLED
	for node: Node in [sun, sun2, guard, guard2]:
		node.free()


func _test_trace_and_overlay() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CrashTrace.PATH))
	CrashTrace._read = false
	CrashTrace.previous = {}
	check(CrashTrace.previous_text() == "", "no note, nothing to report")
	CrashTrace.write("battle", {"level": 3, "wave": 41, "enemies": 220, "mem_mb": 300, "fps": 12})
	CrashTrace._read = false
	var note: Dictionary = CrashTrace.read_previous()
	check(str(note.get("state")) == "battle" and int(note.get("wave")) == 41, "note is read back")
	check("wave 41" in CrashTrace.previous_text(), "note text: %s" % CrashTrace.previous_text())
	CrashTrace.write("map")
	CrashTrace._read = false
	CrashTrace.previous = {}
	check(CrashTrace.read_previous().is_empty(), "an orderly exit leaves no complaint")

	_reset_crash()
	check(not GameSettings.diagnostics(), "diagnostics are hidden by default")
	GameSettings.set_diagnostics(true)
	check(GameSettings.diagnostics(), "diagnostics can be switched on")
	var overlay := DiagOverlay.new()
	root.add_child(overlay)
	var sim := _slow_sim()
	overlay.setup(sim, null, 2, null)
	var text: String = overlay.text()
	check("FPS" in text and "enemies 0" in text and "mem " in text, "overlay text: %s" % text)
	overlay.free()
	sim.free()
	GameSettings.set_diagnostics(false)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CrashTrace.PATH))


func _reset_crash() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CrashTrace.PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CrashTrace.COUNT_PATH))
	CrashTrace._read = false
	CrashTrace.previous = {}
	CrashTrace._count = 0
	CrashTrace._count_wave = 0
	CrashTrace._notice_pending = false


func _test_ladder() -> void:
	_reset_crash()
	var low: int = GameSettings.GFX_LOW
	check(QualityGuard.start_level_for(GameSettings.GFX_HIGH) == 0, "high tier starts at 0")
	check(QualityGuard.start_level_for(low) == 3, "low tier starts at 3")
	check(QualityGuard.start_level_for(low, 2800) == 4, "a 3 GB phone starts at 4")
	check(QualityGuard.start_level_for(low, 3800) == 3, "a 4 GB phone starts at 3")
	check(QualityGuard.start_level_for(low, 2800, 2) == 6, "after crashes it starts lower still")
	check(QualityGuard.start_level_for(GameSettings.GFX_HIGH, 8000, 1) == 1, "penalty on high")
	check(QualityGuard.start_level_for(low, 2000, 2) == QualityGuard.MAX_LEVEL, "clamped")
	check(
		(
			MemoryWatch.parse_kb_line(
				"MemTotal: 3000 kB\nMemAvailable:  409600 kB\n", "MemAvailable"
			)
			== 400
		),
		"meminfo parse"
	)
	check(MemoryWatch.parse_kb_line("x: 1 kB", "MemAvailable") == -1, "missing key")
	check(MemoryWatch.pressure(-1) == 0 and MemoryWatch.pressure(2000) == 0, "plenty of memory")
	check(MemoryWatch.pressure(MemoryWatch.LOW_AVAILABLE_MB - 1) == 1, "low memory")
	check(MemoryWatch.pressure(MemoryWatch.CRITICAL_AVAILABLE_MB - 1) == 2, "critical memory")
	GameSettings.set_graphics(GameSettings.GFX_HIGH)
	QualityGuard.reset_session()
	var sun := DirectionalLight3D.new()
	var forest := Node3D.new()
	forest.add_to_group(&"qg_forest")
	var decor := Node3D.new()
	decor.add_to_group(&"qg_decor")
	var viewport := SubViewport.new()
	var guard := QualityGuard.new()
	for node: Node in [sun, forest, decor, viewport, guard]:
		root.add_child(node)
	guard.setup(sun, viewport)
	guard.check_memory(1000)
	check(guard.level == 0, "enough memory: nothing")
	guard.check_memory(MemoryWatch.LOW_AVAILABLE_MB - 10)
	check(guard.level == 1, "low memory: one notch")
	guard.check_memory(MemoryWatch.LOW_AVAILABLE_MB - 10)
	check(guard.level == 1, "cool-down holds the second notch back")
	guard.lower()
	guard.lower()
	check(
		viewport.scaling_3d_scale < 1.0 and viewport.msaa_3d == Viewport.MSAA_DISABLED, "3D scale"
	)
	guard.check_memory(MemoryWatch.CRITICAL_AVAILABLE_MB - 10)
	check(guard.level == QualityGuard.MAX_LEVEL, "critical memory: the last notch")
	check(not forest.visible and not decor.visible, "forest and decor hidden")
	check(is_equal_approx(viewport.scaling_3d_scale, 0.6), "minimum resolution scale")
	check(GameSettings.effects_now() == GameSettings.FX_OFF, "no effects")
	QualityGuard.reset_session()
	GameSettings.set_graphics(GameSettings.GFX_AUTO)
	for node: Node in [sun, forest, decor, viewport, guard]:
		node.free()


func _test_crash_penalty() -> void:
	_reset_crash()
	check(CrashTrace.penalty() == 0 and not CrashTrace.take_notice(), "clean start: no penalty")
	CrashTrace.write("battle", {"level": 2, "wave": 10, "avail_mb": 120, "rss_mb": 900})
	CrashTrace._read = false
	CrashTrace.previous = {}
	check(CrashTrace.penalty() == 1, "died in a battle: one notch")
	check("avail 120 MB" in CrashTrace.previous_text(), "memory is in the note")
	check(CrashTrace.take_notice() and not CrashTrace.take_notice(), "the message is shown once")
	check(
		QualityGuard.start_level_for(GameSettings.GFX_HIGH, 8000, CrashTrace.penalty()) == 1,
		"starts lower"
	)
	CrashTrace.write("battle", {"level": 2, "wave": 10})
	CrashTrace._read = false
	CrashTrace.previous = {}
	CrashTrace.penalty()
	CrashTrace.write("battle", {"level": 2, "wave": 12})
	CrashTrace._read = false
	CrashTrace.previous = {}
	check(CrashTrace.penalty() == 2, "twice in a row: two notches")
	CrashTrace.write("battle", {"level": 2, "wave": 12})
	CrashTrace._read = false
	CrashTrace.previous = {}
	check(CrashTrace.penalty() == CrashTrace.MAX_PENALTY, "the penalty is capped")
	CrashTrace.write("map", {"level": 2, "wave": 3})
	check(
		CrashTrace.penalty() == CrashTrace.MAX_PENALTY, "a short orderly battle does not clear it"
	)
	CrashTrace.write("map", {"level": 2, "wave": 13})
	check(CrashTrace.penalty() == 0, "an orderly end past the death wave clears it")
	_reset_crash()
