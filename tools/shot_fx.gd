extends SceneTree
## Screenshots of the battle effects (needs a window, NOT --headless).
## LEVEL=<id> OUT=<dir> godot --path . --resolution 1280x720 --script res://tools/shot_fx.gd
## Writes fx_battle.png, fx_upgrade.png, fx_hit.png, fx_victory.png into OUT.

var _out: String = OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "user://"


func _initialize() -> void:
	LevelCatalog.save_path = "user://shot_fx.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LevelCatalog.save_path))
	var level: String = OS.get_environment("LEVEL")
	LevelCatalog.selected_id = int(level) if level != "" else 1
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func _shot(shot_name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	await _frames(12)
	var main: Node = current_scene
	var gs: GameState = main.get_node("GameState")
	var wm: WaveManager = main.get_node("WaveManager")
	var bm: BuildManager = main.get_node("BuildManager")
	gs.add_gold(100000)
	gs.add_wood(100000)
	var kind := 0
	var slots: Array[TowerSlot] = []
	for node: Node in get_nodes_in_group(TowerSlot.GROUP):
		slots.append(node as TowerSlot)
	for slot in slots:
		bm.build_on(slot, bm.tower_types[kind % bm.tower_types.size()])
		kind += 1
	gs.lives = 100000
	gs.lives_changed.emit(gs.lives)
	# Look at the slot farthest from the castle (where the enemies arrive first).
	var castle: Vector3 = main.get_node("Fx")._castle.global_position
	slots.sort_custom(
		func(a: TowerSlot, b: TowerSlot) -> bool:
			return a.global_position.distance_to(castle) > b.global_position.distance_to(castle)
	)
	var hero: Hero = main.get_node("Level/Hero")
	hero.global_position = slots[0].global_position + Vector3(1.5, 0, 1.5)
	(main.get_node("Camera") as CameraFollow).snap()
	bm.select_slot(slots[0])
	await _frames(20)
	Engine.time_scale = 3.0
	wm.start_next_wave()
	await _frames(int(OS.get_environment("WAIT")) if OS.get_environment("WAIT") != "" else 150)
	for i in 12:
		await _frames(8)
		await _shot("fx_battle_%d" % i)
	var victims: Array[Node] = get_nodes_in_group(Enemy.GROUP)
	if not victims.is_empty():
		for victim in victims:
			(victim as Enemy).hit_flash = 1.0
		Engine.time_scale = 0.05
		await _frames(2)
		await _shot("fx_flash")
	Engine.time_scale = 3.0
	bm.upgrade(slots[1])
	await _frames(6)
	await _shot("fx_upgrade")
	await _frames(60)
	gs.lose_lives(1)
	await _frames(5)
	await _shot("fx_hit")
	main.get_node("Fx")._on_victory()
	await _frames(70)
	await _shot("fx_victory")
	quit()
