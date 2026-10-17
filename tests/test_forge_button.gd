extends SceneTree
## Real mouse clicks on the real HUD tree: the pause menu's Forge button opens the forge
## card, the sword / repair / close buttons work, and every command card button (build,
## upgrade, priority, sell, trade, cancel) is the topmost control under its centre (no
## invisible Control covers it) and reacts to a click.
## LEVEL=<id> godot --headless --fixed-fps 60 --path . --script res://tests/test_forge_button.gd

var fails := 0
var main: Node
var hud: Hud


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_forge_button.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	LevelCatalog.selected_id = (
		int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	)
	LevelCatalog.endless = false
	LevelCatalog.tutorial = false
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


## True when `button` is what a finger on its centre hits.
func _topmost(button: Control) -> bool:
	var point: Vector2 = button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	await process_frame
	await process_frame
	return root.gui_get_hovered_control() == button


func _click(button: Control) -> void:
	var point: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = point
		ev.global_position = point
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(ev, true)
		await process_frame
	await process_frame


func _card_button(id: StringName) -> Button:
	var ids: Array = hud.get("_button_ids")
	var i: int = ids.find(id)
	if i < 0:
		return null
	return hud.get_node("Root/CommandCard/Content/Buttons").get_child(i) as Button


func _click_card(id: StringName) -> bool:
	var button: Button = _card_button(id)
	if button == null or not button.is_visible_in_tree():
		print("  FAIL button %s not on the card" % id)
		fails += 1
		return false
	if not await _topmost(button):
		print("  FAIL button %s is covered by %s" % [id, root.gui_get_hovered_control()])
		fails += 1
		return false
	await _click(button)
	return true


func _run() -> void:
	for i in 10:
		await process_frame
	main = current_scene
	hud = main.get_node("HUD")
	var gs: GameState = main.get("_game_state")
	var hero: Hero = main.get_node("Level/Hero")
	var bm: BuildManager = main.get_node("BuildManager")
	(main.get_node("WaveManager") as WaveManager).stop()
	gs.add_gold(2000)
	gs.add_wood(2000)

	# Pause menu -> Forge.
	var pause: Button = hud.get_node("Root/TopRight/PauseButton")
	check(await _topmost(pause), "pause button is under the finger")
	await _click(pause)
	check(paused, "click on Pause pauses")
	var forge: Button = hud.get_node("Root/EndScreen/EndPanel/Content/ForgeButton")
	check(forge.is_visible_in_tree(), "Forge button is shown in the pause menu")
	check(await _topmost(forge), "Forge button is under the finger (nothing covers it)")
	await _click(forge)
	check(not paused, "click on Forge resumes the game")
	check(main.cards.forge_open, "click on Forge opens the forge card")
	check(hud.get_node("Root/CommandCard").visible, "forge card is visible")

	# Sword and repair, by clicks.
	var damage: float = hero.attack_damage
	check(await _click_card(&"sword"), "sword button is clickable")
	check(hero.sword_level == 1 and hero.attack_damage > damage, "click on Sword upgrades it")
	gs.lose_lives(5)
	var lives: int = gs.lives
	check(await _click_card(&"repair"), "repair button is clickable")
	check(gs.lives > lives, "click on Repair mends the castle")
	check(main.cards.forge_open, "forge card stays open after a purchase")
	check(await _click_card(&"cancel"), "close button is clickable")
	check(not main.cards.forge_open, "click on Close closes the forge")

	# Forge again from the pause menu, then a second toggle closes it.
	await _click(pause)
	await _click(forge)
	check(main.cards.forge_open, "Forge opens again")
	main.cards.toggle_forge()
	await process_frame
	check(not main.cards.forge_open, "toggling closes the forge")

	# Slot cards: build / upgrade / priority / sell.
	var slot: TowerSlot = null
	for node: Node in get_nodes_in_group(TowerSlot.GROUP):
		slot = node as TowerSlot
		break
	hero.auto_action = false
	hero.global_position = slot.global_position + Vector3(0.5, 0.0, 0.0)
	bm.select_slot(slot)
	await process_frame
	check(await _click_card(&"build_0"), "build button is clickable")
	for i in 120:
		await process_frame
		if not slot.is_free():
			break
	check(not slot.is_free(), "click on Build builds a tower")
	bm.select_slot(slot)
	await process_frame
	check(await _click_card(&"priority"), "priority button is clickable")
	var level: int = slot.tower.level
	check(await _click_card(&"upgrade"), "upgrade button is clickable")
	for i in 120:
		await process_frame
		if slot.tower.level > level:
			break
	check(slot.tower.level > level, "click on Upgrade upgrades the tower")
	var gold: int = gs.gold
	check(await _click_card(&"sell"), "sell button is clickable")
	await process_frame
	check(slot.is_free() and gs.gold > gold, "click on Sell sells the tower")
	bm.select_slot(slot)
	await process_frame
	check(await _click_card(&"cancel"), "cancel button is clickable")
	check(bm.selected_slot == null, "click on Cancel drops the selection")

	# Forge while the knight is still moving next to a slot: the slot card must not push the
	# forge card out again.
	hero.global_position = slot.global_position + Vector3(1.4, 0.0, 0.0)
	hero.joystick_vector = Vector2(-1.0, 0.0)
	for i in 6:
		await physics_frame
	check(bm.selected_slot == slot, "walking up to the slot selects it")
	await _click(pause)
	await _click(forge)
	for i in 30:
		await physics_frame
	check(main.cards.forge_open, "forge stays open after pausing next to a slot")
	check(_card_button(&"sword") != null, "forge card shows the sword button")
	await _click_card(&"cancel")
	hero.joystick_vector = Vector2.ZERO

	# Trade buttons go through the same hit test.
	var villagers: Villagers = main.get("villagers")
	var near: Villager = (
		villagers.get_child(0) as Villager if villagers.get_child_count() > 0 else null
	)
	if near != null:
		hero.global_position = near.global_position + Vector3(0.5, 0.0, 0.0)
		for i in 20:
			await process_frame
		if main.cards.trade_with != null:
			check(await _click_card(&"trade_lot"), "trade button is clickable")
			check(await _click_card(&"cancel"), "trade close is clickable")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
