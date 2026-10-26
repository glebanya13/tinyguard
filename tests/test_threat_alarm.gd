extends SceneTree
## Tests Castle Threat Alarm, Leak Flash, and Manual Tower Slot Distance Auto-Deselect.
## Run with: godot --headless --fixed-fps 60 --path . --script res://tests/test_threat_alarm.gd

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
	print("-- 1. HUD Threat Alarm & Leak Flash")
	LevelCatalog.selected_id = 1
	change_scene_to_file("res://scenes/main.tscn")

	for i in 6:
		await process_frame
	for i in 6:
		await physics_frame

	var main_node = current_scene
	var hud: Hud = main_node.get_node("HUD")
	var vignette: ColorRect = hud.find_child("ThreatVignette", true, false)

	_ok(vignette != null, "HUD contains ThreatVignette")
	_ok(not vignette.visible, "ThreatVignette initially hidden")

	print("-- 1b. Castle alarm: a '!' over an enemy that will reach the castle, not a dark screen")
	var sim: Sim = main_node.get_node("Sim")
	var wm: WaveManager = main_node.get_node("WaveManager")
	sim.manual = true
	wm.start_next_wave()
	for i in 30:
		sim.step()
	var walker: Enemy = sim.enemies[0]
	var length: float = walker.path.curve.get_baked_length()
	walker.place(length - walker.speed * 6.0)  # six seconds from the gate
	var far: Enemy = sim.enemies[1] if sim.enemies.size() > 1 else null
	if far != null:
		far.place(0.0)
	var threats: Array[Enemy] = CastleThreat.find(sim.enemies, sim.towers)
	_ok(threats.has(walker), "an enemy six seconds from the castle with no towers is announced")
	_ok(far == null or not threats.has(far), "an enemy at its portal is not")
	_ok(CastleThreat.WARN_SECONDS >= 12.0, "the alarm comes early enough to run to the castle")
	walker.health = 1.0
	var tower_scene: PackedScene = load("res://scenes/towers/tower_archer.tscn")
	var tower: Tower = tower_scene.instantiate()
	main_node.add_child(tower)
	tower.global_position = walker.sim_position()
	tower.apply_level(load("res://resources/towers/archer.tres"), 0)
	var guarded: Array[Tower] = [tower]
	_ok(
		not CastleThreat.find(sim.enemies, guarded).has(walker),
		"an enemy the towers on its road will kill is not announced"
	)
	tower.queue_free()
	main_node._threat_timer = 0.0
	main_node._process(0.016)
	var hint: LaneHint = main_node._lane_hint
	_ok(hint.threats().has(walker), "the battle hands the alarm to the screen")
	_ok(not vignette.visible, "the screen is not darkened by enemies near the castle")
	main_node.battle_end.on_all_waves_cleared()
	_ok(hint.threats().is_empty(), "no alarm once the battle is over")

	hud.flash_leak()
	_ok(vignette.visible, "ThreatVignette visible on flash_leak")
	_ok(
		vignette.color.a >= 0.4,
		"ThreatVignette alpha >= 0.4 on leak flash (actual: %.2f)" % vignette.color.a
	)

	print("-- 2. Manual Tower Slot Selection Distance Auto-Deselect")
	var bm: BuildManager = main_node.get_node("BuildManager")
	var cards: CardController = main_node.cards
	var hero: Hero = main_node.get_node("Level/Hero")
	var commands: GameCommands = main_node.get_node("GameCommands")
	var slot0: TowerSlot = commands.slots[0]

	bm.select_slot(slot0)
	_ok(bm.selected_slot == slot0, "Slot 0 selected manually")

	# Position hero close to slot 0
	hero.global_position = slot0.global_position + Vector3(1.0, 0.0, 0.0)
	cards.update()
	_ok(bm.selected_slot == slot0, "Slot 0 remains selected while hero is close (1.0m)")

	# Move hero far away (> 5.5m)
	hero.global_position = slot0.global_position + Vector3(7.0, 0.0, 0.0)
	cards.update()
	_ok(bm.selected_slot == null, "Slot selection auto-cleared when hero moves away (> 5.5m)")

	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
