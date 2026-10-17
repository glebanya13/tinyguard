extends SceneTree
## Screenshots of the gem shop, the map hooks and a battle in skins (needs a window,
## NOT --headless):
## SHOT_DIR=<dir> godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##   --resolution 1280x720 --script res://tools/shot_shop.gd
## Writes <dir>/shop_<name>.png. Scratch save files only.

const SAVE := "user://shot_shop_progress.cfg"
const SETTINGS := "user://shot_shop_settings.cfg"

var _dir: String = ""


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	GameSettings.config_path = SETTINGS
	LevelCatalog.erase_all()
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("user://")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(_dir.path_join("shop_%s.png" % name))
	print("saved ", name, " ", img.get_width(), "x", img.get_height())


func _swap(scene: Node) -> void:
	if current_scene != null:
		current_scene.queue_free()
	root.add_child(scene)
	current_scene = scene


func _give(amount: int, key: String) -> void:
	var p: Dictionary = PlayerProfile.local()
	Wallet.claim(p["wallet"], key, amount)
	PlayerProfile.save_local(p)


func _run() -> void:
	GameSettings.set_language(
		OS.get_environment("SHOT_LANG") if OS.get_environment("SHOT_LANG") != "" else "ru"
	)
	for id in [1, 2, 3]:
		LevelCatalog.complete(id, 3)
	var online: Node = root.get_node("Online")
	online.setup("", "", HttpTransport.new())
	Onboarding.set_local_nickname("Сэр Ёжик", "сэр ёжик", false)
	_give(900, "shot_start")
	Shop.buy("hero_ember")
	Shop.buy("tower_forest")
	Shop.buy("flag_violet")
	Shop.buy("fx_azure")
	if Shop.buy("hero_frost"):
		Shop.equip("hero_frost")

	# The map: gem chip, Shop button, streak plaque, the visit's toast.
	LevelCatalog.selected_id = 3
	change_scene_to_file(Onboarding.MAP_SCENE)
	await _frames(70)
	await _shot("map")
	await _frames(300)  # the visit's toasts fade out
	current_scene.get("_gems").call("panel").call("open")
	await _frames(15)
	await _shot("streak")
	current_scene.get("_gems").call("close_panel")

	# The shop, one tab at a time.
	for category in ["hero", "tower", "flag", "fx"]:
		var shop: ShopScreen = (
			(load("res://scenes/shop.tscn") as PackedScene).instantiate() as ShopScreen
		)
		shop.auto_leave = false
		_swap(shop)
		await _frames(10)
		shop.select_category(category)
		if category == "hero":
			shop.select_item("hero_royal")
		elif category == "tower":
			shop.select_item("tower_fire")
		elif category == "flag":
			shop.select_item("flag_midnight")
		else:
			shop.select_item("fx_pink")
		await _frames(50)
		await _shot(category)
		if category == "hero":
			shop.press_action()  # Buy asks first
			await _frames(10)
			await _shot("confirm")

	# A battle in skins: the knight, four towers, the castle banner.
	Shop.equip("tower_forest")
	Shop.equip("flag_violet")
	LevelCatalog.selected_id = 2
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_swap(main)
	await _frames(40)
	var sim: Sim = main.get_node("Sim")
	var commands: GameCommands = main.get_node("GameCommands")
	var bm: BuildManager = main.get_node("BuildManager")
	(main.get_node("GameState") as GameState).gold = 5000
	var built := 0
	for slot in commands.slots:
		if built >= 4:
			break
		if slot.is_free() and bm.can_build(slot, bm.tower_types[built % bm.tower_types.size()]):
			commands.submit(GameCommand.build(slot.slot_id, built % bm.tower_types.size()))
			built += 1
			await _frames(3)
	await _frames(90)
	print("ticks ", sim.tick)
	await _shot("battle")
	LevelCatalog.erase_all()
	quit()
