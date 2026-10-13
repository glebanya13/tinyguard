extends SceneTree
## Level build, chopping (auto and by tap), 3 tower types for gold + wood,
## upgrade, bosses in the plan, sword damage.
## LEVEL=<id> godot --headless --fixed-fps 60 --path . --script res://tests/test_gameplay.gd

var _failures := 0


func _initialize() -> void:
	LevelCatalog.selected_id = int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	print("  ok   " if cond else "  FAIL ", what)
	if not cond:
		_failures += 1


func frames(n: int) -> void:
	for i in n:
		await process_frame


func wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await process_frame
	return cond.call()


func tap_key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		root.push_input(ev)
		await process_frame


func _run() -> void:
	await frames(5)
	var main: Node = current_scene
	var gs: GameState = main.get_node("GameState")
	var wm: WaveManager = main.get_node("WaveManager")
	var bm: BuildManager = main.get_node("BuildManager")
	var hero: Hero = main.get_node("Level/Hero")
	var level: Dictionary = main.level
	check(gs.gold == 0 and gs.wood == 0, "start with 0 gold / 0 wood")
	check(get_nodes_in_group(TowerSlot.GROUP).size() == level["slots"].size(), "slots built: %d" % level["slots"].size())
	check(get_nodes_in_group(WoodTree.GROUP).size() >= level["trees"].size() + 10, "trees built: %d" % get_nodes_in_group(WoodTree.GROUP).size())
	check((main.get_node("Level/EnemyPath") as Path3D).curve.point_count == level["path"].size(), "path built")
	check(wm.get_total_waves() == int(level["waves"]["count"]), "waves: %d" % wm.get_total_waves())

	# Chop a tree: standing next to it is enough (auto action).
	var tree: WoodTree = get_nodes_in_group(WoodTree.GROUP)[0]
	hero.global_position = tree.global_position + Vector3(1.0, 0, 0)
	await wait_until(func() -> bool: return gs.wood > 0, 120)
	check(gs.wood == 3, "auto chop gives wood: %d" % gs.wood)
	await wait_until(func() -> bool: return not tree.is_choppable(), 400)
	await frames(30)
	check(gs.wood == 12 and not tree.is_choppable(), "tree exhausted after 12 wood (%d)" % gs.wood)
	check(hero.get_focus_target() != tree, "fallen tree is not a target")
	# Tap on another tree: hero walks there and chops.
	var far: WoodTree = null
	for node: Node in get_nodes_in_group(WoodTree.GROUP):
		var d: float = (node as Node3D).global_position.distance_to(hero.global_position)
		if d > 3.0 and d < 7.0:
			far = node
			break
	if far:
		main._on_ground_tapped(far.global_position + Vector3(0.3, 0, 0))
		await wait_until(func() -> bool: return far.hits_left() < far.hits, 600)
		check(far.hits_left() < far.hits, "tap on tree: hero walked and chopped")
	gs.wood = 0
	gs.wood_changed.emit(0)

	# Build a cannon (key 2) on a slot.
	var slot: TowerSlot = get_nodes_in_group(TowerSlot.GROUP)[0]
	bm.select_slot(slot)
	await frames(2)
	await tap_key(KEY_2)
	await frames(5)
	check(slot.is_free(), "cannot build without gold")
	gs.add_gold(200)
	gs.add_wood(200)
	await tap_key(KEY_2)
	await wait_until(func() -> bool: return not slot.is_free(), 600)
	check(not slot.is_free() and slot.tower.data.display_name == "Пушка", "cannon built")
	check(gs.gold == 160 and gs.wood >= 170, "paid 40 gold + 30 wood (%d/%d)" % [gs.gold, gs.wood])
	await frames(30)
	await tap_key(KEY_U)
	await frames(5)
	check(slot.tower.level == 1, "upgraded")

	# Bosses in the plan.
	check(wm.plan.is_boss_wave(10) and wm.plan.spawns(10)[-1]["data"].is_boss, "boss on wave 10")
	check(not wm.plan.is_boss_wave(9), "no boss on wave 9")

	# Hero hits an enemy.
	wm.start_next_wave()
	await wait_until(func() -> bool: return get_nodes_in_group(Enemy.GROUP).size() > 0, 120)
	var enemy: Enemy = get_nodes_in_group(Enemy.GROUP)[0]
	await frames(5)
	hero.global_position = enemy.global_position + Vector3(0.6, 0, 0)
	hero.global_position.y = 0
	var hp: float = enemy.health
	await frames(1)
	hero.try_attack()
	await frames(60)
	check(not is_instance_valid(enemy) or enemy.health < hp, "sword hurts enemy (hp %s -> %s, dist %.2f)" % [hp, enemy.health if is_instance_valid(enemy) else -1.0, hero.global_position.distance_to(enemy.global_position) if is_instance_valid(enemy) else -1.0])

	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(_failures)
