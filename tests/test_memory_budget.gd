extends SceneTree
## Memory budget of the daily challenge around wave 10 (the first boss and the armoured
## surprise wave), on the highest and on the lowest quality notch: object and node counts,
## static memory and orphan nodes stay under limits taken from desktop measurements
## (tools/soak_test.gd, docs/SOAK_REPORT.md) with headroom. Video memory is not measured here
## (the headless renderer has none): see tools/soak_test.gd and tools/probe_tex.gd.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_memory_budget.gd

## Measured at wave 8-12: ~4200-4450 objects, ~1100-1210 nodes, ~71-72 MB static (high notch).
const MAX_OBJECTS := 6000
const MAX_NODES := 1700
const MAX_STATIC_MB := 110.0
const DAY := "2026-08-27"
const WAVES := 12

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_memory_budget.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	node_added.connect(
		func(node: Node) -> void:
			if node is Hero:
				(node as Hero).auto_action = false
	)
	_run.call_deferred()


func _run() -> void:
	for notch in [0, QualityGuard.MAX_LEVEL]:
		await _scenario(notch)
	QualityGuard.reset_session()
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)


func _scenario(notch: int) -> void:
	QualityGuard.reset_session()
	QualityGuard.session_level = notch
	paused = false
	DailyRun.select(DAY)
	var old_scene: Node = current_scene
	change_scene_to_file("res://scenes/main.tscn")
	var sim: Sim = null
	while sim == null:
		await process_frame
		if current_scene != null and current_scene != old_scene and current_scene.has_node("Sim"):
			sim = current_scene.get_node("Sim")
	sim.manual = true
	for i in 200:
		if sim.running:
			break
		await process_frame
	var main: Node = current_scene
	var gs: GameState = main.get_node("GameState")
	var wm: WaveManager = main.get_node("WaveManager")
	var guard: QualityGuard = main.get_node("QualityGuard")
	var peak_objects := 0.0
	var peak_nodes := 0.0
	var peak_static := 0.0
	var peak_enemies := 0
	var ticks := 0
	while wm.current_wave < WAVES and ticks < 30 * 60 * 20:
		gs.lives = 1000
		if ticks % (4 * Sim.TICK_RATE) == 0:
			wm.start_next_wave()  # overlapping waves: the worst case of the trial
		sim.step()
		ticks += 1
		if ticks % 30 == 0:
			await process_frame
			peak_enemies = maxi(peak_enemies, sim.enemies.size())
			peak_objects = maxf(peak_objects, Performance.get_monitor(Performance.OBJECT_COUNT))
			peak_nodes = maxf(peak_nodes, Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			peak_static = maxf(peak_static, Performance.get_monitor(Performance.MEMORY_STATIC))
	var label: String = "notch %d" % notch
	print(
		(
			"  %s: wave %d, enemies peak %d, objects %d, nodes %d, static %.1f MB"
			% [
				label,
				wm.current_wave,
				peak_enemies,
				peak_objects,
				peak_nodes,
				peak_static / 1048576.0
			]
		)
	)
	check(guard.level >= notch, "%s: guard level kept (%d)" % [label, guard.level])
	check(wm.current_wave >= WAVES, "%s: reached wave %d" % [label, WAVES])
	check(peak_objects <= MAX_OBJECTS, "%s: objects <= %d" % [label, MAX_OBJECTS])
	check(peak_nodes <= MAX_NODES, "%s: nodes <= %d" % [label, MAX_NODES])
	check(
		peak_static / 1048576.0 <= MAX_STATIC_MB,
		"%s: static memory <= %d MB" % [label, MAX_STATIC_MB]
	)
	check(
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == 0.0,
		"%s: no orphan nodes" % label
	)
