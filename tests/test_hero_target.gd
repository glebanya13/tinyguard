extends SceneTree
## What a swing hits: an enemy within reach always beats a tree; the swing turns to the
## thing the sword can really reach (a tree next to the knight is chopped even when an
## enemy walks by out of reach on the other side); the hero never loops on swings that
## hit nothing.
## godot --headless --fixed-fps 60 --path . --script res://tests/test_hero_target.gd

var fails := 0
var _hero: Hero
var _sim: Sim
var _tree_a: WoodTree


func check(c: bool, w: String) -> void:
	print("  ok   " if c else "  FAIL ", w)
	if not c:
		fails += 1


func _initialize() -> void:
	LevelCatalog.save_path = "user://test_hero_target.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	LevelCatalog.selected_id = 1
	LevelCatalog.endless = false
	LevelCatalog.tutorial = false
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func _spawn_enemy() -> Enemy:
	var e := (load("res://scenes/enemy.tscn") as PackedScene).instantiate() as Enemy
	e.setup(load("res://resources/enemies/slime.tres"), 20.0)
	e.speed = 0.0
	current_scene.get_node("Level/EnemyPath").add_child(e)
	e.place(6.0)
	return e


func _run() -> void:
	for i in 8:
		await process_frame
	for i in 3:
		await physics_frame
	_hero = current_scene.get_node("Level/Hero")
	_sim = current_scene.get_node("Sim")
	(current_scene.get_node("WaveManager") as WaveManager).stop()
	var choppable: Array[WoodTree] = []
	for t in _sim.trees:
		if t.is_choppable():
			choppable.append(t)
	_tree_a = choppable[0]
	# Everything else far away.
	for t in choppable:
		if t != _tree_a:
			t.global_position = Vector3(500.0, 0.0, 500.0 + t.id)
	for v in current_scene.villagers.get_children():
		if v is Node3D:
			(v as Node3D).global_position = Vector3(-500.0, 0.0, -500.0)
	var enemy := _spawn_enemy()
	var path: Path3D = enemy.get_parent()
	# A short straight path along z under the test spot: progress p is z = -20 + p.
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3(-20.0, 0.0, -20.0))
	path.curve.add_point(Vector3(-20.0, 0.0, 20.0))
	await process_frame
	var here := Vector3(-20.0, 0.0, 0.0)

	# A: the enemy 1.0 m away and a tree 0.8 m away in the SAME direction (both in the
	# cone of the swing): the enemy is hit, the tree is not chopped.
	_hero.auto_action = false
	_hero.global_position = here
	enemy.place(20.0 + 1.0)
	await process_frame
	var spot: Vector3 = enemy.global_position
	var toward: Vector3 = (spot - here).normalized()
	_tree_a.global_position = here + toward * 0.8
	var hp: float = enemy.health
	var hits: int = _tree_a.hits_left()
	_hero.auto_action = true
	for i in 60:
		await physics_frame
	check(enemy.health < hp, "enemy in reach is hit (%.1f -> %.1f)" % [hp, enemy.health])
	check(_tree_a.hits_left() == hits, "a tree in the same cone is not chopped meanwhile")

	# B: enemy out of sword reach (1.9 m) on one side, a tree 1.0 m on the other side:
	# the knight chops the tree instead of swinging at the enemy for nothing.
	_hero.auto_action = false
	enemy.health = enemy.max_health
	enemy.place(20.0 + 1.9)
	await process_frame
	spot = enemy.global_position
	_hero.global_position = here
	var away: Vector3 = here - spot
	away.y = 0.0
	_tree_a.global_position = here + away.normalized() * 1.0
	hits = _tree_a.hits_left()
	hp = enemy.health
	_hero.auto_action = true
	for i in 60:
		await physics_frame
	check(
		_tree_a.hits_left() < hits, "a tree in reach is chopped, not an empty swing at a far enemy"
	)
	check(is_equal_approx(enemy.health, hp), "the far enemy was out of reach")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	print("RESULT: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
