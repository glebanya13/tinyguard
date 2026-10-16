extends SceneTree
## Screenshots of the build / upgrade command cards in battle (needs a window, NOT --headless):
## SHOT_DIR=<dir> SHOT_LANG=ru|en godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##   --resolution 1280x720 --script res://tools/shot_cards.gd
## Writes <dir>/cards_<lang>_<w>x<h>_build.png and ..._upgrade.png. Scratch save only.

const MAIN_SCENE := "res://scenes/main.tscn"

var _dir: String = ""


func _initialize() -> void:
	LevelCatalog.save_path = "user://shot_cards.cfg"
	LevelCatalog.erase_all()
	GameSettings.config_path = "user://shot_cards_settings.cfg"
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("user://")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var lang: String = (
		OS.get_environment("SHOT_LANG") if OS.get_environment("SHOT_LANG") != "" else "ru"
	)
	var file := "cards_%s_%dx%d_%s.png" % [lang, img.get_width(), img.get_height(), shot_name]
	img.save_png(_dir.path_join(file))
	print("saved ", file)


func _run() -> void:
	var lang: String = (
		OS.get_environment("SHOT_LANG") if OS.get_environment("SHOT_LANG") != "" else "ru"
	)
	GameSettings.set_language(lang)
	LevelCatalog.complete(1, 3)
	LevelCatalog.selected_id = 2
	LevelCatalog.tutorial = false
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.get_node("HUD").set("_touch", true)
	root.add_child(main)
	current_scene = main
	await _frames(60)
	var bm: BuildManager = main.get_node("BuildManager")
	var gs: GameState = main.get_node("GameState")
	gs.add_gold(1000)
	gs.add_wood(1000)
	var slot := get_nodes_in_group(TowerSlot.GROUP)[0] as TowerSlot
	bm.select_slot(slot)
	await _frames(30)
	await _shot("build")
	bm.build_on(slot, bm.tower_types[0])
	bm.select_slot(slot)
	await _frames(30)
	await _shot("upgrade")
	quit()
