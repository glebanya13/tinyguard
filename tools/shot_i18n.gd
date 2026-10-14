extends SceneTree
## Screenshots of the key screens in one language (ru or en) for docs/screenshots
## and for checking that texts fit buttons and panels. Needs a display.
## SHOT_LANG=en SHOT_DIR=docs/screenshots godot --path . --resolution 1280x720 \
##   --rendering-driver opengl3 --script res://tools/shot_i18n.gd
## Writes <SHOT_DIR>/i18n_<lang>_<screen>.png; uses scratch save files only.

const SAVE := "user://shot_i18n_progress.cfg"
const SESSION := "user://shot_i18n_session.dat"
const SETTINGS := "user://shot_i18n_settings.cfg"

var _dir: String = ""
var _lang: String = "en"


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	SessionStore.path = SESSION
	GameSettings.config_path = SETTINGS
	LevelCatalog.erase_all()
	SessionStore.clear()
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("user://")
	_lang = OS.get_environment("SHOT_LANG") if OS.get_environment("SHOT_LANG") != "" else "en"
	_run.call_deferred()


func _run() -> void:
	GameSettings.set_language(_lang)
	Onboarding.set_local_nickname("Ёжик" if _lang == "ru" else "Hedgehog", "x", false)
	# Some progress so the map shows stars and the treasury has something to buy.
	LevelCatalog.complete(1, 3)
	LevelCatalog.complete(2, 2)

	change_scene_to_file("res://scenes/level_select.tscn")
	await _frames(30)
	await _shot("map")
	current_scene.call("_open_treasury")
	await _frames(10)
	await _shot("treasury")
	current_scene.get_node("UI/Root/Treasury").hide()
	current_scene.get("_settings").open()
	await _frames(10)
	await _shot("settings")
	current_scene.get("_settings").close()
	current_scene.get("_account").open()
	await _frames(10)
	await _shot("profile")

	change_scene_to_file(Onboarding.NICKNAME_SCENE)
	await _frames(20)
	await _shot("nickname")

	LevelCatalog.selected_id = 1
	LevelCatalog.endless = false
	LevelCatalog.tutorial = true
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(40)
	await _shot("tutorial_welcome")

	LevelCatalog.tutorial = false
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(40)
	await _shot("battle_banner")
	var main: Node = current_scene
	main.get("_wave_manager").start_next_wave()
	await _frames(60)
	await _shot("wave_banner")
	await _frames(300)
	var slots: Array[Node] = get_nodes_in_group(TowerSlot.GROUP)
	if not slots.is_empty():
		var slot: Node = slots[0]
		main.get("_build_manager").select_slot(slot)
		await _frames(10)
		await _shot("build_card")
	main.get("_hud").show_pause_menu()
	await _frames(10)
	await _shot("pause")
	main.get("_hud").hide_pause_menu()
	main.call("_on_defeated")
	await _frames(20)
	await _shot("defeat")
	quit(0)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _shot(name: String) -> void:
	await _frames(2)
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = "%s/i18n_%s_%s.png" % [_dir, _lang, name]
	image.save_png(path)
	print("saved ", path)
