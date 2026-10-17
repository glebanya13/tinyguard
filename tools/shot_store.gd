extends SceneTree
## Google Play screenshots: real game scenes on a desktop window, deterministic
## (--fixed-fps 60, fixed levels/towers/frames). Needs a window, not --headless:
## godot --path . --rendering-driver opengl3 --fixed-fps 60 --resolution 1920x1080 \
##   --script res://tools/shot_store.gd
## Env: SHOT_DIR (default assets/store), SHOT_PREFIX (default "shot"),
## SHOT_ONLY (comma list of shot names). The HUD is built in its phone layout.

const SAVE := "user://shot_store_progress.cfg"
const SESSION := "user://shot_store_session.dat"
const MAIN_SCENE := "res://scenes/main.tscn"
## Tower types by BuildManager.tower_types index, in slot order.
const PLAN := [0, 1, 2, 3, 1, 0, 2, 3, 1]
## Enemy kinds (resources/enemies/*.tres) that walk in the battle shots.
const CROWD := ["slime", "slime_fast", "slime_tank", "slime_bat", "slime", "slime_shield"]
const CAMERA_SIZE := 11.5

var _dir: String = ""
var _prefix: String = "shot"
var _only: PackedStringArray = []
var _index: int = 0


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	SessionStore.path = SESSION
	LevelCatalog.erase_all()
	SessionStore.clear()
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("res://assets/store")
	DirAccess.make_dir_recursive_absolute(_dir)
	if OS.get_environment("SHOT_PREFIX") != "":
		_prefix = OS.get_environment("SHOT_PREFIX")
	if OS.get_environment("SHOT_ONLY") != "":
		_only = OS.get_environment("SHOT_ONLY").split(",")
	_run.call_deferred()


func _run() -> void:
	var online: Node = root.get_node("Online")
	online.setup("", "", HttpTransport.new())
	Onboarding.set_local_nickname("Сэр Ёжик", "сэр ёжик", false)
	for id in [1, 2, 3, 4]:
		LevelCatalog.complete(id, [3, 2, 3, 3][id - 1])
	LevelCatalog.complete(5, 1)

	await _map_shot()
	await _battle("level_1_valley", 1, 6, 6)
	await _battle("level_4_snow", 4, 6, 6)
	await _battle("level_5_autumn", 5, 6, 6)
	await _battle("level_6_desert", 6, 6, 6, true)
	await _upgrade_shot()
	await _tutorial_shot()
	await _treasury_shot()
	await _profile_shot()
	LevelCatalog.erase_all()
	SessionStore.clear()
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _want(name: String) -> bool:
	return _only.is_empty() or name in _only


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_index += 1
	var path: String = _dir.path_join("%s_%02d_%s.png" % [_prefix, _index, name])
	var img: Image = root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(path)
	print("saved ", path, " ", img.get_width(), "x", img.get_height())


func _swap_scene(scene: Node) -> void:
	if current_scene:
		var old: Node = current_scene
		root.remove_child(old)
		old.free()
	root.add_child(scene)
	current_scene = scene
	paused = false


func _map_shot() -> void:
	if not _want("map"):
		_index += 1
		return
	LevelCatalog.selected_id = 5
	change_scene_to_file("res://scenes/level_select.tscn")
	await _frames(60)
	for toast in get_nodes_in_group(Toast.GROUP):
		toast.queue_free()  # the visit's reward toasts cover the island
	await _frames(4)
	await _shot("map")


## Loads a level with its HUD in the phone layout.
func _load_level(id: int) -> Node:
	LevelCatalog.selected_id = id
	LevelCatalog.endless = false
	LevelCatalog.tutorial = false
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.get_node("HUD").set("_touch", true)
	_swap_scene(main)
	return main


## Towers on the slots nearest to the fight, enemies strung along the route past
## them, the hero beside the towers. Returns the slots, nearest first.
func _stage(main: Node, towers: int, upgrades: int, crowd: int, progress_ratio: float) -> Array:
	var gs: GameState = main.get_node("GameState")
	var wm: WaveManager = main.get_node("WaveManager")
	var bm: BuildManager = main.get_node("BuildManager")
	var hero: Hero = main.get_node("Level/Hero")
	var cam: CameraFollow = main.get_node("Camera")
	var route: Curve3D = wm.get_paths()[0].curve
	var focus: Vector3 = route.sample_baked(route.get_baked_length() * progress_ratio)
	var slots: Array = get_nodes_in_group(TowerSlot.GROUP)
	slots.sort_custom(
		func(a: Node3D, b: Node3D) -> bool:
			return a.global_position.distance_to(focus) < b.global_position.distance_to(focus)
	)
	gs.add_gold(2000)
	gs.add_wood(2000)
	for i in mini(towers, slots.size()):
		bm.build_on(slots[i], bm.tower_types[PLAN[i % PLAN.size()]])
	for i in upgrades:
		bm.upgrade(slots[i])
	wm.start_next_wave()
	hero.global_position = (slots[0] as Node3D).global_position + Vector3(1.3, 0.0, 1.8)
	cam.size = CAMERA_SIZE
	cam.snap()
	gs.add_gold(-gs.gold + 120)
	gs.add_wood(-gs.wood + 85)
	# The wave banner is gone by now; the crowd walks in the middle of the towers.
	await _frames(240)
	for i in crowd:
		var data: EnemyData = load("res://resources/enemies/%s.tres" % CROWD[i % CROWD.size()])
		var at: float = route.get_baked_length() * progress_ratio - 5.0 + i * 1.6
		wm.spawn_extra(data, 1.0, at, 1, wm.get_paths()[0])
	return slots


func _battle(name: String, id: int, towers: int, crowd: int, hero_fight: bool = false) -> void:
	if not _want(name):
		_index += 1
		return
	var main: Node = _load_level(id)
	await _frames(10)
	var hero: Hero = main.get_node("Level/Hero")
	await _stage(main, towers, 2, crowd, 0.5)
	main.get_node("BuildManager").clear_selection()
	await _frames(100)
	if hero_fight:
		hero.try_attack()
		await _frames(6)
	await _shot(name)


func _upgrade_shot() -> void:
	if not _want("upgrade"):
		_index += 1
		return
	var main: Node = _load_level(3)
	await _frames(10)
	var slots: Array = await _stage(main, 6, 1, 4, 0.45)
	await _frames(80)
	main.get_node("BuildManager").select_slot(slots[2])
	await _frames(20)
	await _shot("upgrade")


func _tutorial_shot() -> void:
	if not _want("tutorial"):
		_index += 1
		return
	LevelCatalog.erase_all()
	Onboarding.set_local_nickname("Сэр Ёжик", "сэр ёжик", false)
	Onboarding.start_tutorial(self)
	await _frames(60)
	var tutorial: Tutorial = current_scene.get_node("Tutorial")
	await create_timer(0.6).timeout
	tutorial.press_primary()
	await _frames(240)
	await _shot("tutorial")


func _treasury_shot() -> void:
	if not _want("treasury"):
		_index += 1
		return
	LevelCatalog.erase_all()
	for id in [1, 2, 3, 4, 5]:
		LevelCatalog.complete(id, [3, 2, 3, 3, 2][id - 1])
	LevelCatalog.selected_id = 4
	change_scene_to_file(Onboarding.MAP_SCENE)
	await _frames(60)
	for toast in get_nodes_in_group(Toast.GROUP):
		toast.queue_free()
	current_scene.call("_open_treasury")
	await _frames(20)
	await _shot("treasury")


## The offline profile panel: only on request (SHOT_ONLY=profile), it is plain.
func _profile_shot() -> void:
	if not _only.has("profile"):
		return
	LevelCatalog.erase_all()
	for id in [1, 2, 3]:
		LevelCatalog.complete(id, 3)
	LevelCatalog.tutorial = false
	paused = false
	Onboarding.set_local_nickname("Сэр Ёжик", "сэр ёжик", false)
	Onboarding.complete_tutorial()
	change_scene_to_file(Onboarding.MAP_SCENE)
	await _frames(60)
	current_scene.get("_account").open()
	await _frames(15)
	await _shot("profile")
