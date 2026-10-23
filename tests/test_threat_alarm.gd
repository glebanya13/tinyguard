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

	hud.set_threat_danger(0.75)
	_ok(vignette.visible, "ThreatVignette visible when threat danger is 0.75")
	_ok(
		vignette.color.a > 0.1,
		"ThreatVignette alpha > 0.1 on danger (actual: %.2f)" % vignette.color.a
	)

	hud.set_threat_danger(0.0)
	_ok(not vignette.visible, "ThreatVignette hidden when threat danger is 0.0")

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
