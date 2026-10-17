extends SceneTree
## Screenshots of the villager trade card (needs a window, NOT --headless):
## SHOT_DIR=<dir> SHOT_LANG=ru|en godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##   --resolution 1280x720 --script res://tools/shot_trade.gd
## Writes <dir>/trade_<lang>_<w>x<h>_{card,hired,record}.png. Scratch save only.

const MAIN_SCENE := "res://scenes/main.tscn"

var _dir: String = ""
var _lang: String = "ru"


func _initialize() -> void:
	LevelCatalog.save_path = "user://shot_trade.cfg"
	LevelCatalog.erase_all()
	GameSettings.config_path = "user://shot_trade_settings.cfg"
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("user://")
	if OS.get_environment("SHOT_LANG") != "":
		_lang = OS.get_environment("SHOT_LANG")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var file := "trade_%s_%dx%d_%s.png" % [_lang, img.get_width(), img.get_height(), shot_name]
	img.save_png(_dir.path_join(file))
	print("saved ", file)


func _start(record: bool) -> Node:
	LevelCatalog.endless = record
	LevelCatalog.selected_id = 1
	LevelCatalog.tutorial = false
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.get_node("HUD").set("_touch", true)
	root.add_child(main)
	current_scene = main
	await _frames(60)
	var gs: GameState = main.get_node("GameState")
	gs.add_gold(100)
	gs.add_wood(40)
	var list: Array[Villager] = main.villagers.get_villagers()
	var hero: Hero = main.get_node("Level/Hero")
	hero.global_position = list[0].global_position + Vector3(0.8, 0.0, 0.0)
	await _frames(40)
	return main


func _run() -> void:
	GameSettings.set_language(_lang)
	var main: Node = await _start(false)
	await _shot("card")
	var list: Array[Villager] = main.villagers.get_villagers()
	main.cards.on_command_pressed(&"buy_lot")
	main.cards.on_command_pressed(&"hire")
	await _frames(50)
	await _shot("hired")
	# Where is the hired one: look at him from the camera
	print("hired at ", list[0].global_position, " lumberjack ", list[0].is_lumberjack())
	main.queue_free()
	await _frames(5)
	main = await _start(true)
	await _shot("record")
	quit()
