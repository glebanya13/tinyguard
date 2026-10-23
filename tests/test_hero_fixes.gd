extends SceneTree
## Verifies hero fixes:
## 1. WoodTree $Shape collision is disabled when felled and re-enabled on regrow.
## 2. Tapping an enemy initiates pursuit by the knight and maintains attack distance.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_hero_fixes.gd

var fails := 0


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_hero_fixes.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	LevelCatalog.selected_id = 1
	LevelCatalog.endless = false
	LevelCatalog.tutorial = false
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func _spawn_enemy(progress: float, speed: float = 0.0) -> Enemy:
	var e := (load("res://scenes/enemy.tscn") as PackedScene).instantiate() as Enemy
	e.setup(load("res://resources/enemies/slime.tres"), 50.0)
	e.speed = speed
	current_scene.get_node("Level/EnemyPath").add_child(e)
	e.place(progress)
	return e


func _run() -> void:
	for i in 8:
		await process_frame
	for i in 3:
		await physics_frame

	var main = current_scene
	var hero: Hero = main.get_node("Level/Hero")
	var sim: Sim = main.get_node("Sim")
	(main.get_node("WaveManager") as WaveManager).stop()

	print("-- WoodTree collision disabling and regrow")
	var tree: WoodTree = null
	for t in sim.trees:
		if t.is_choppable() and t.has_node("Shape"):
			tree = t
			break

	check(tree != null, "found a choppable WoodTree with Shape")
	var shape: CollisionShape3D = tree.get_node("Shape") as CollisionShape3D
	check(not shape.disabled, "tree collision shape is initially enabled")

	# Fell the tree
	while tree.is_choppable():
		tree.chop(tree.global_position + Vector3.FORWARD)

	# Await deferred update
	await process_frame
	await physics_frame

	check(shape.disabled, "felled tree has $Shape collision disabled")

	# Regrow the tree
	tree._regrow()
	await process_frame
	await physics_frame

	check(not shape.disabled, "regrown tree has $Shape collision re-enabled")

	print("-- Enemy tap pursuit and holding attack distance")
	# Spawn an enemy along the enemy path
	var enemy := _spawn_enemy(10.0, 0.0)
	await process_frame

	# Move hero away from enemy so there is space to pursue
	hero.global_position = enemy.global_position + Vector3(5.0, 0.0, 0.0)
	check(hero.target_enemy == null, "hero initially has no target enemy")

	# Tap near the enemy (within ENEMY_TAP_REACH ~ 1.8m)
	var tap_point: Vector3 = enemy.global_position + Vector3(0.5, 0.0, 0.0)
	main.cards.on_ground_tapped(tap_point)

	check(hero.target_enemy == enemy, "tapping enemy sets hero.target_enemy")
	check(hero.is_chasing(), "hero.is_chasing() is true")

	var initial_dist: float = hero.global_position.distance_to(enemy.global_position)
	for i in 30:
		await physics_frame
		await process_frame

	var mid_dist: float = hero.global_position.distance_to(enemy.global_position)
	check(
		mid_dist < initial_dist - 0.5,
		"hero moves toward pursued enemy (%.2f -> %.2f)" % [initial_dist, mid_dist]
	)

	# Let hero reach attack range
	for i in 120:
		await physics_frame
		await process_frame
		if hero.global_position.distance_to(enemy.global_position) <= hero.attack_range:
			break

	var final_dist: float = hero.global_position.distance_to(enemy.global_position)
	check(
		final_dist <= hero.attack_range + 0.1,
		"hero reaches and holds attack range (%.2f <= %.2f)" % [final_dist, hero.attack_range]
	)

	# Moving enemy pursuit: make enemy walk along path and verify hero chases
	enemy.speed = 1.0
	for i in 60:
		await physics_frame
		await process_frame

	check(hero.target_enemy == enemy, "hero continues pursuing while enemy moves and lives")
	check(
		hero.global_position.distance_to(enemy.global_position) <= hero.attack_range + 0.5,
		"hero stays close to moving enemy"
	)

	# When enemy dies, target_enemy is cleared
	enemy.take_damage(999999.0)
	await process_frame
	await physics_frame

	check(hero.target_enemy == null, "target_enemy is cleared when enemy dies")
	check(not hero.is_chasing(), "hero is no longer chasing after enemy dies")

	# Tap on ground far from any enemy cancels chase if set
	var enemy2 := _spawn_enemy(15.0, 0.0)
	await process_frame
	hero.chase_enemy(enemy2)
	check(hero.target_enemy == enemy2, "chase_enemy sets target_enemy")
	main.cards.on_ground_tapped(Vector3(100.0, 0.0, 100.0))
	check(hero.target_enemy == null, "tapping ground far from enemies cancels chase")

	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
