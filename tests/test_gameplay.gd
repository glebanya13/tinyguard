extends SceneTree
## Level build, chopping (auto and by tap), 3 tower types for gold + wood,
## upgrade, bosses in the plan, sword damage.
## LEVEL=<id> godot --headless --fixed-fps 60 --path . --script res://tests/test_gameplay.gd

var _failures := 0


func _initialize() -> void:
	# Never touch the developer's real save (perks would change the numbers).
	LevelCatalog.save_path = "user://test_gameplay.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	LevelCatalog.selected_id = (
		int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	)
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


func _all_paths_seen(used: Dictionary, paths: Array[Path3D]) -> bool:
	for path in paths:
		if not used.has(path):
			return false
	return true


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
	var start: Dictionary = level["start"]
	check(
		gs.gold == int(start["gold"]) and gs.wood == int(start["wood"]),
		"start with the level's gold / wood (%d/%d)" % [gs.gold, gs.wood]
	)
	check(
		get_nodes_in_group(TowerSlot.GROUP).size() == level["slots"].size(),
		"slots built: %d" % level["slots"].size()
	)
	check(
		get_nodes_in_group(WoodTree.GROUP).size() >= level["trees"].size() + 10,
		"trees built: %d" % get_nodes_in_group(WoodTree.GROUP).size()
	)
	var routes: Array[PackedVector2Array] = LevelCatalog.routes(level)
	var paths: Array[Path3D] = wm.get_paths()
	check(routes.size() >= 4 and paths.size() == routes.size(), "paths built: %d" % paths.size())
	var castle := Vector2(float(level["castle"][0]), float(level["castle"][1]))
	for i in paths.size():
		var curve: Curve3D = paths[i].curve
		var end: Vector3 = curve.get_point_position(curve.point_count - 1)
		check(
			(
				curve.point_count == routes[i].size()
				and LevelCatalog.is_gate(Vector2(end.x, end.z), castle)
			),
			"path %d ends at a castle gate" % i
		)
	# Enemies come from all four sides of the castle: the approaches (last segments of
	# the castle paths) lie in the four screen quadrants, portals in 4+ screen directions.
	var quadrants := {}
	for i in 4:
		var r: PackedVector2Array = routes[i]
		var out: Vector2 = r[r.size() - 2] - r[r.size() - 1]
		var qx: int = signi(roundi(out.dot(LevelCatalog.SCREEN_RIGHT) * 100.0))
		var qy: int = signi(roundi(out.dot(LevelCatalog.SCREEN_UP) * 100.0))
		quadrants[Vector2i(qx, qy)] = true
	check(quadrants.size() == 4, "approaches cover all 4 screen quadrants: %s" % [quadrants.keys()])
	var dirs := {}
	for route: PackedVector2Array in routes:
		dirs[LevelCatalog.screen_direction(route[0] - castle)] = true
	check(dirs.size() >= 4, "portals in %d screen directions" % dirs.size())
	var portals: int = 0
	for node: Node in main.get_node("Level").get_children():
		if node.scene_file_path == "res://assets/models/spawn_portal.glb":
			portals += 1
	check(portals == routes.size(), "a portal per path: %d" % portals)
	check(wm.get_total_waves() == int(level["waves"]["count"]), "waves: %d" % wm.get_total_waves())

	# Chop a tree: standing next to it is enough (auto action).
	# Trees grow in groves: take the one with the fewest neighbours within 4 m and stand on its
	# far side from them, so it is the nearest tree to the knight (a swing chops only that one).
	var tree: WoodTree = null
	var away := Vector3.RIGHT
	var fewest: int = 1000
	for node: Node in get_nodes_in_group(WoodTree.GROUP):
		var here: Vector3 = (node as Node3D).global_position
		var count: int = 0
		var centre := Vector3.ZERO
		for other: Node in get_nodes_in_group(WoodTree.GROUP):
			var there: Vector3 = (other as Node3D).global_position
			if other != node and here.distance_to(there) < 4.0:
				count += 1
				centre += there
		if count < fewest:
			fewest = count
			tree = node as WoodTree
			away = Vector3.RIGHT if count == 0 else (here - centre / count)
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.RIGHT
	check(tree != null, "a tree to chop (%d neighbours within 4 m)" % fewest)
	# A swing starts where the knight stands (the hit lands 0.2 s later at that
	# spot): let one begun at his spawn point finish before teleporting him.
	hero.auto_action = false
	await frames(40)
	hero.auto_action = true
	gs.wood = 0
	gs.wood_changed.emit(0)
	hero.global_position = tree.global_position + away * 0.9
	await wait_until(func() -> bool: return gs.wood > 0, 120)
	# 3 from the tree (a thicket tree in the same swing cone may add its own wood).
	check(gs.wood >= 3, "auto chop gives wood: %d" % gs.wood)
	await wait_until(func() -> bool: return not tree.is_choppable(), 400)
	await frames(30)
	# At least the tree's 12 wood: a thicket tree in the same swing cone gives wood too.
	check(gs.wood >= 12 and not tree.is_choppable(), "tree exhausted after 12 wood (%d)" % gs.wood)
	check(hero.get_focus_target() != tree, "fallen tree is not a target")
	# Tap on another tree: hero walks there and chops.
	var far: WoodTree = null
	for node: Node in get_nodes_in_group(WoodTree.GROUP):
		var d: float = (node as Node3D).global_position.distance_to(hero.global_position)
		if d > 3.0 and d < 7.0:
			far = node
			break
	if far:
		main.cards.on_ground_tapped(far.global_position + Vector3(0.3, 0, 0))
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
	var gold_start: int = gs.gold
	gs.add_gold(200)
	gs.add_wood(200)
	await tap_key(KEY_2)
	await wait_until(func() -> bool: return not slot.is_free(), 600)
	check(
		not slot.is_free() and slot.tower.data.display_name == "TOWER_CANNON_NAME", "cannon built"
	)
	var cannon: TowerData = slot.tower.data
	check(
		gs.gold == gold_start + 200 - cannon.cost_gold and gs.wood >= 200 - cannon.cost_wood,
		"paid %d gold + %d wood (%d/%d)" % [cannon.cost_gold, cannon.cost_wood, gs.gold, gs.wood]
	)
	await frames(30)
	bm.select_slot(slot)
	await frames(5)
	await tap_key(KEY_U)
	await wait_until(func() -> bool: return slot.tower != null and slot.tower.level == 1, 120)
	check(slot.tower != null and slot.tower.level == 1, "upgraded")

	# Sell: 70% of the build + first upgrade gold back.
	var gold_before: int = gs.gold
	var refund: int = cannon.sell_value(1).x
	bm.select_slot(slot)
	await frames(5)
	await tap_key(KEY_X)
	await wait_until(func() -> bool: return slot.is_free(), 120)
	check(
		slot.is_free() and gs.gold == gold_before + refund,
		"sold for 70%% (+%d gold)" % (gs.gold - gold_before)
	)
	# Forge: sword upgrade and castle repair.
	gs.add_gold(300)
	gs.add_wood(300)
	main.cards.toggle_forge()
	await frames(2)
	await tap_key(KEY_U)
	check(
		hero.sword_level == 1 and is_equal_approx(hero.attack_damage, hero.sword_damage_levels[1]),
		"sword upgraded"
	)
	gs.lose_lives(5)
	var lives: int = gs.lives
	main.cards.on_command_pressed(&"repair")
	check(gs.lives == lives + 2, "castle repaired (+2 lives)")
	main.cards.on_command_pressed(&"cancel")

	# Bosses in the plan.
	# The first boss wave comes from the level's boss_every (6, 8 or 10 waves).
	var boss_wave: int = 1
	while boss_wave < wm.plan.wave_count and not wm.plan.is_boss_wave(boss_wave):
		boss_wave += 1
	check(
		boss_wave >= 6 and wm.plan.spawns(boss_wave)[-1]["data"].is_boss,
		"boss on wave %d" % boss_wave
	)
	check(not wm.plan.is_boss_wave(boss_wave - 1), "no boss on wave %d" % (boss_wave - 1))

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
	check(
		not is_instance_valid(enemy) or enemy.health < hp,
		(
			"sword hurts enemy (hp %s -> %s, dist %.2f)"
			% [
				hp,
				enemy.health if is_instance_valid(enemy) else -1.0,
				(
					hero.global_position.distance_to(enemy.global_position)
					if is_instance_valid(enemy)
					else -1.0
				)
			]
		)
	)

	# Whirlwind hits everything around, then cools down.
	var e := (load("res://scenes/enemy.tscn") as PackedScene).instantiate() as Enemy
	e.setup(load("res://resources/enemies/slime.tres"), 10.0)
	main.get_node("Level/EnemyPath").add_child(e)
	await frames(30)  # attack cooldown from the previous swing
	hero.global_position = Vector3(e.global_position.x + 1.5, 0, e.global_position.z)
	var before: float = e.health
	check(hero.try_spin(), "whirlwind")
	check(e.health < before, "whirlwind damages an enemy 1.5 m away")
	check(not hero.try_spin() and hero.spin_cooldown_left() > 10.0, "whirlwind cooldown")

	# Lane plan: every path is used by some wave, scouts and bosses keep to their own
	# paths, elites appear, flyers get an air path to the castle gate.
	var lanes: Dictionary = level["waves"]["lanes"]
	check(wm.plan.lane_count() == paths.size(), "lane patterns fit %d paths" % paths.size())
	check(wm.air_paths.size() == paths.size(), "an air path per path")
	for i in paths.size():
		var curve: Curve3D = paths[i].curve
		var gate: Vector3 = curve.get_point_position(curve.point_count - 1)
		var air: Path3D = wm.air_paths[i]
		var air_end: Vector3 = air.curve.get_point_position(1)
		check(air.curve.point_count == 2 and air_end.is_equal_approx(gate), "air path to the gate")
	var planned := {}
	var scouts_ok: bool = true
	var bosses_ok: bool = true
	var elites: int = 0
	for wave in range(1, mini(wm.get_total_waves(), 40) + 1):
		for entry: Dictionary in wm.plan.spawns(wave):
			planned[int(entry["lane"])] = true
			var data: EnemyData = entry["data"]
			if data.resource_path.ends_with("slime_fast.tres"):
				scouts_ok = scouts_ok and (lanes["scout_paths"] as Array).has(float(entry["lane"]))
			if data.is_boss:
				bosses_ok = bosses_ok and (lanes["boss_paths"] as Array).has(float(entry["lane"]))
			if entry["elite"]:
				elites += 1
	check(planned.size() == paths.size(), "waves use all %d paths" % planned.size())
	check(scouts_ok and bosses_ok, "scouts and bosses keep to their paths")
	check(
		elites > 0 or wm.get_total_waves() < int(level["waves"]["elite"]["from"]), "elites planned"
	)
	var lanes_w1: Array = wm.lanes_of(wm.plan.spawns(1))
	check(lanes_w1.size() < paths.size(), "wave 1 does not use every path: %s" % [lanes_w1])
	check(
		LevelCatalog.direction_text(level, [0, 1, 2, 3, 4, 5].slice(0, paths.size())) != "",
		"direction text: %s" % LevelCatalog.direction_text(level, [0])
	)

	# Spawned enemies appear on every path (waves started one after another).
	var used := {}
	var flyer_on_air := true
	var all_used := func() -> bool:
		for node: Node in get_nodes_in_group(Enemy.GROUP):
			used[node.get_parent()] = true
			var e2 := node as Enemy
			if e2.is_flying() and e2.get_parent() not in wm.air_paths:
				flyer_on_air = false
		return (
			used.size() == paths.size() + (1 if used.has(main.get_node("Level/EnemyPath")) else 0)
		)
	Engine.time_scale = 4.0
	var guard: int = 0
	while guard < 24 and not _all_paths_seen(used, paths):
		gs.lives = 999  # nothing defends the castle here: the walk must not end in defeat
		wm.start_next_wave()
		for i in 25:
			await frames(20)
			all_used.call()
		guard += 1
	Engine.time_scale = 1.0
	check(_all_paths_seen(used, paths), "enemies spawn on all %d paths" % paths.size())
	check(flyer_on_air, "flyers use the air paths")

	print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(_failures)
