extends SceneTree
## The hero reaches every tower slot of the level (walk grid, A*).
## LEVEL=<id> godot --headless --fixed-fps 60 --path . --script res://tests/test_walk.gd


func _initialize() -> void:
	# Never touch the developer's real save (perks would change the numbers).
	LevelCatalog.save_path = "user://test_walk.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	LevelCatalog.selected_id = (
		int(OS.get_environment("LEVEL")) if OS.get_environment("LEVEL") != "" else 1
	)
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func _run() -> void:
	for i in 5:
		await process_frame
	for i in 3:
		await physics_frame
	var hero: Hero = current_scene.get_node("Level/Hero")
	hero.auto_action = false
	# Walking to every slot takes longer than the first waves need to beat the castle.
	(current_scene.get_node("WaveManager") as WaveManager).stop()
	var slots: Array[Node] = get_nodes_in_group(TowerSlot.GROUP)
	var reached: int = 0
	for slot: Node in slots:
		var arrived := [false]
		hero.move_to((slot as Node3D).global_position, 1.25, func() -> void: arrived[0] = true)
		for i in 1800:
			await physics_frame
			if not hero.has_order():
				break
		if arrived[0]:
			reached += 1
		else:
			print(
				"  FAIL slot ",
				(slot as Node3D).global_position,
				" hero stopped at ",
				hero.global_position
			)
	print(
		(
			"RESULT: %s (reached %d/%d slots)"
			% ["PASS" if reached == slots.size() else "FAIL", reached, slots.size()]
		)
	)
	quit(0 if reached == slots.size() else 1)
