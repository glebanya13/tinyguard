extends SceneTree
## Enemy traits and tower kinds: flying enemies dodge cannons, shields resist
## arrows, lightning chains between enemies.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_combat.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	# Never touch the developer's real save (perks would change the numbers).
	LevelCatalog.save_path = "user://test_combat.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	LevelCatalog.selected_id = 1
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func spawn(path: String, progress: float) -> Enemy:
	var e := (load("res://scenes/enemy.tscn") as PackedScene).instantiate() as Enemy
	e.setup(load(path), 10.0)
	e.speed = 0.0
	current_scene.get_node("Level/EnemyPath").add_child(e)
	e.progress = progress
	return e


func build(kind: int, near: Vector3) -> Tower:
	var bm: BuildManager = current_scene.get_node("BuildManager")
	var gs: GameState = current_scene.get_node("GameState")
	gs.add_gold(1000)
	gs.add_wood(1000)
	var best: TowerSlot = null
	for node: Node in get_nodes_in_group(TowerSlot.GROUP):
		var slot := node as TowerSlot
		if (
			slot.is_free()
			and (
				best == null
				or slot.global_position.distance_to(near) < best.global_position.distance_to(near)
			)
		):
			best = slot
	bm.build_on(best, bm.tower_types[kind])
	return best.tower


func _run() -> void:
	for i in 10:
		await process_frame
	var bat := spawn("res://resources/enemies/slime_bat.tres", 6.0)
	await process_frame
	check(bat.is_flying() and bat.get_aim_point().y > 1.0, "bat flies above the path")
	var cannon := build(1, bat.global_position)
	cannon.range_m = 100.0
	check(cannon.find_nearest_enemy() == null, "cannon ignores flying enemies")
	var archer := build(0, bat.global_position)
	archer.range_m = 100.0
	check(archer.find_nearest_enemy() == bat, "archer targets flying enemies")
	bat.queue_free()

	var shield := spawn("res://resources/enemies/slime_shield.tres", 8.0)
	var hp: float = shield.health
	shield.take_damage(10.0, &"arrow")
	check(
		is_equal_approx(hp - shield.health, 3.5),
		"shield takes 35%% from arrows (%.1f)" % (hp - shield.health)
	)
	hp = shield.health
	shield.take_damage(10.0)
	check(is_equal_approx(hp - shield.health, 10.0), "shield takes full damage otherwise")
	shield.queue_free()
	await process_frame

	var group: Array[Enemy] = []
	for k in 4:
		group.append(spawn("res://resources/enemies/slime.tres", 10.0 + k * 1.2))
	await process_frame
	var bolt := build(3, group[0].global_position)
	bolt.range_m = 100.0
	var before: Array[float] = []
	for e in group:
		before.append(e.health)
	bolt._shoot(group[0])
	var hit: int = 0
	for k in group.size():
		if group[k].health < before[k]:
			hit += 1
	check(hit == 3, "lightning level 1 hits target + 2 jumps (%d)" % hit)
	await process_frame
	check(get_nodes_in_group(Enemy.GROUP).size() >= 4, "enemies alive after test")
	# Waves run on a 30 s clock and overlap.
	var wm: WaveManager = current_scene.get_node("WaveManager")
	wm.start_next_wave()
	check(absf(wm.time_to_next_wave() - wm.plan.wave_duration) < 0.1, "next wave in 30 s")
	wm.start_next_wave()
	check(wm.current_wave == 2, "a wave can start while the previous one runs")

	# Splitter: two minis join its wave when it dies.
	var splitter := spawn("res://resources/enemies/slime_splitter.tres", 12.0)
	splitter.wave = 1
	splitter.split.connect(wm._on_enemy_split)
	splitter.take_damage(99999.0)
	await process_frame
	var minis: int = 0
	for node: Node in get_nodes_in_group(Enemy.GROUP):
		if (node as Enemy).data.display_name == "Слизнёнок":
			minis += 1
	check(minis == 2, "splitter leaves two minis (%d)" % minis)

	# Healer mends a hurt neighbour.
	var hurt := spawn("res://resources/enemies/slime.tres", 14.0)
	var healer := spawn("res://resources/enemies/slime_healer.tres", 14.3)
	await process_frame
	hurt.take_damage(hurt.max_health * 0.5)
	var hp_hurt: float = hurt.health
	healer._heal_neighbours()
	check(hurt.health > hp_hurt, "healer heals neighbours")

	# Golem armour: -3 per hit, never below 1.
	var golem := spawn("res://resources/enemies/stone_golem.tres", 16.0)
	var hp_golem: float = golem.health
	golem.take_damage(10.0)
	check(is_equal_approx(hp_golem - golem.health, 7.0), "golem armour takes 3 off a hit")
	hp_golem = golem.health
	golem.take_damage(2.0)
	check(is_equal_approx(hp_golem - golem.health, 1.0), "at least 1 damage gets through")

	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
