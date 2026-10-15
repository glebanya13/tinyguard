extends SceneTree
## Screenshots of the UI screens for the theme review (needs a window, NOT --headless):
## SHOT_DIR=<dir> SHOT_PREFIX=after godot --path . --rendering-driver opengl3 \
##   --fixed-fps 60 --resolution 1920x1080 --script res://tools/shot_ui.gd
## Writes <dir>/<prefix>_<screen>.png: map with the settings panel, treasury, pause menu,
## victory screen, co-op lobby. Scratch save files only.

const Fake := preload("res://tests/fake_rtdb.gd")
const SAVE := "user://shot_ui_progress.cfg"
const SETTINGS := "user://shot_ui_settings.cfg"
const MAIN_SCENE := "res://scenes/main.tscn"

var _dir: String = ""
var _prefix: String = "ui"


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	GameSettings.config_path = SETTINGS
	LevelCatalog.erase_all()
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("user://")
	if OS.get_environment("SHOT_PREFIX") != "":
		_prefix = OS.get_environment("SHOT_PREFIX")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(_dir.path_join("%s_%s.png" % [_prefix, name]))
	print("saved ", name, " ", img.get_width(), "x", img.get_height())


func _swap(scene: Node) -> void:
	if current_scene != null:
		current_scene.queue_free()
	root.add_child(scene)
	current_scene = scene


func _run() -> void:
	GameSettings.set_language("ru")
	for id in [1, 2, 3, 4]:
		LevelCatalog.complete(id, [3, 2, 3, 1][id - 1])
	LevelCatalog.selected_id = 4
	LevelCatalog.tutorial = false
	var online: Node = root.get_node("Online")
	online.setup("", "", HttpTransport.new())
	Onboarding.set_local_nickname("Сэр Ёжик", "сэр ёжик", false)

	change_scene_to_file(Onboarding.MAP_SCENE)
	await _frames(60)
	await _shot("map")
	current_scene.call("_open_treasury")
	await _frames(20)
	await _shot("treasury")
	var settings: Node = current_scene.get("_settings")
	if settings != null:
		current_scene.get("_treasury").hide()
		settings.call("open")
		await _frames(20)
		await _shot("settings")

	LevelCatalog.selected_id = 2
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.get_node("HUD").set("_touch", true)
	_swap(main)
	await _frames(60)
	var hud: Node = main.get_node("HUD")
	hud.call("show_pause_menu")
	await _frames(20)
	await _shot("pause")
	hud.call("hide_pause_menu")
	hud.call("show_end_screen", "Победа!", true, 3, "Волн: 15\nУбито: 214")
	await _frames(20)
	await _shot("victory")
	hud.call("show_end_screen", "Поражение", false, 0, "Волн: 7")
	await _frames(20)
	await _shot("defeat")

	var server := Fake.FakeServer.new()
	var net := Fake.FakeTransport.new()
	net.server = server
	net.user_id = "uidHost"
	server.clients.append(net)
	var lobby: Control = (load("res://scenes/coop_lobby.tscn") as PackedScene).instantiate()
	lobby.set("transport", net)
	lobby.set("nickname", "Ёжик")
	lobby.set("auto_load", false)
	_swap(lobby)
	await _frames(15)
	await _shot("lobby")
	LevelCatalog.erase_all()
	quit()
