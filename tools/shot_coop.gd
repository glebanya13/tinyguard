extends SceneTree
## Screenshots of the co-op lobby (menu, code entry, room) in one language, on an
## in-memory database (no network). Needs a display.
## SHOT_LANG=en SHOT_DIR=docs/screenshots godot --path . --resolution 1280x720 \
##   --rendering-driver opengl3 --script res://tools/shot_coop.gd
## Writes <SHOT_DIR>/coop_<lang>_<screen>.png; uses scratch save files only.

const Fake := preload("res://tests/fake_rtdb.gd")
const SAVE := "user://shot_coop_progress.cfg"
const SETTINGS := "user://shot_coop_settings.cfg"

var _dir: String = ""
var _lang: String = "en"


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	GameSettings.config_path = SETTINGS
	LevelCatalog.erase_all()
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("user://")
	_lang = OS.get_environment("SHOT_LANG") if OS.get_environment("SHOT_LANG") != "" else "en"
	_run.call_deferred()


func _net(server: Fake.FakeServer, uid: String) -> Fake.FakeTransport:
	var net := Fake.FakeTransport.new()
	net.server = server
	net.user_id = uid
	server.clients.append(net)
	return net


func _screen(net: Fake.FakeTransport, nick: String) -> Control:
	var screen: Control = (load("res://scenes/coop_lobby.tscn") as PackedScene).instantiate()
	screen.set("transport", net)
	screen.set("nickname", nick)
	screen.set("auto_load", false)
	return screen


func _press(screen: Node, text: String) -> void:
	for node in screen.find_children("*", "Button", true, false):
		if (node as Button).text == text and (node as Button).is_visible_in_tree():
			(node as Button).pressed.emit()
			return
	push_error("no button " + text)


func _run() -> void:
	GameSettings.set_language(_lang)
	LevelCatalog.complete(1, 3)
	LevelCatalog.complete(2, 2)
	LevelCatalog.selected_id = 2
	var server := Fake.FakeServer.new()
	var host: Control = _screen(_net(server, "uidHost"), "Ёжик" if _lang == "ru" else "Hedgehog")
	root.add_child(host)
	await _frames(10)
	await _shot("menu")
	_press(host, "Создать комнату" if _lang == "ru" else "Create a room")
	await _frames(10)
	await _shot("room_waiting")

	var guest: Control = _screen(_net(server, "uidGuest"), "Барсик" if _lang == "ru" else "Badger")
	root.remove_child(host)
	root.add_child(guest)
	await _frames(5)
	_press(guest, "Войти по коду" if _lang == "ru" else "Join with a code")
	var code: String = str(host.get("lobby").code)
	for letter in code.substr(0, 3):
		_press(guest, letter)
	await _frames(5)
	await _shot("join")
	for letter in code.substr(3):
		_press(guest, letter)
	_press(guest, "Войти" if _lang == "ru" else "Join")
	await _frames(10)
	_press(guest, "Готов" if _lang == "ru" else "Ready")
	await _frames(10)
	await _shot("room_guest")
	root.remove_child(guest)
	root.add_child(host)
	await _frames(10)
	await _shot("room_host")
	quit(0)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _shot(name: String) -> void:
	await _frames(2)
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = "%s/coop_%s_%s.png" % [_dir, _lang, name]
	image.save_png(path)
	print("saved ", path)
