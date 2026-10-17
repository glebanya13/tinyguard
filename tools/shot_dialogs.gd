extends SceneTree
## Screenshots of the dialogs for the eye: the end screen of a daily trial, the pause menu, the
## treasury, the records window (a table and a failed load), settings, profile, achievements. A
## display cutout is faked with SHOT_NOTCH="left,top,right,bottom" (canvas units). Needs a window.
## SHOT_DIR=<dir> SHOT_PREFIX=a SHOT_NOTCH=80,0,0,0 godot --path . --rendering-driver opengl3 \
##   --fixed-fps 60 --resolution 2000x900 --script res://tools/shot_dialogs.gd

var _dir: String = ""
var _prefix: String = "a"


func _initialize() -> void:
	LevelCatalog.save_path = "user://shot_dialogs.cfg"
	LevelCatalog.erase_all()
	GameSettings.config_path = "user://shot_dialogs_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameSettings.config_path))
	Onboarding.set_local_nickname("Фёдор", "федор", false)
	for id in [1, 2, 3]:
		LevelCatalog.complete(id, 3)
	_dir = OS.get_environment("SHOT_DIR")
	if OS.get_environment("SHOT_PREFIX") != "":
		_prefix = OS.get_environment("SHOT_PREFIX")
	var notch: PackedStringArray = OS.get_environment("SHOT_NOTCH").split(",")
	if notch.size() == 4:
		ScreenUtil.fake_margins = Vector4(
			float(notch[0]), float(notch[1]), float(notch[2]), float(notch[3])
		)
	GameSettings.set_language("ru")
	LevelCatalog.selected_id = 2
	change_scene_to_file("res://scenes/main.tscn")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(shot_name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(_dir.path_join("%s_%s.png" % [_prefix, shot_name]))
	print("saved ", shot_name)


func _run() -> void:
	await _frames(40)
	var main: Node = current_scene
	var hud: Hud = main.get_node("HUD")
	var safe: SafeArea = hud.get_node("Root/SafeArea")
	safe.apply()
	hud.show_end_screen(
		tr("DAILY_END_BEST"),
		true,
		0,
		(
			tr("DAILY_END_STATS") % [23, 23]
			+ "\n"
			+ tr("DAILY_END_STREAK") % 4
			+ "\n"
			+ tr("DAILY_END_STAR")
			+ "\n"
			+ tr("END_GEMS") % 12
			+ "\n"
			+ tr("END_STATS_1") % [412, 3000]
			+ "\n"
			+ tr("END_STATS_2") % [12, 7, 11, 5]
		)
	)
	await _shot("end_daily")
	hud.hide_pause_menu()
	hud.show_pause_menu()
	await _shot("pause")
	hud._settings_panel.open()
	await _shot("settings")
	hud._settings_panel.close()
	hud.hide_pause_menu()
	paused = false
	change_scene_to_file("res://scenes/level_select.tscn")
	await _frames(40)
	var map: Node = current_scene
	map.get_node("UI/Root/SafeArea").apply()
	map._open_treasury()
	await _shot("treasury")
	map._treasury.hide()
	var stub := RecordsStub.new()
	root.add_child(stub)
	var panel := RecordsPanel.new()
	panel.online = stub
	map.get_node("UI/Root").add_child(panel)
	await _frames(2)
	panel.open(3, "Зелёная долина")
	var entries: Array = []
	for i in 10:
		entries.append({"name": "Рыцарь Фёдор %d" % i, "wave": 40 - i})
	stub.leaderboard_loaded.emit(3, entries)
	await _shot("records")
	panel.request()
	await _shot("records_loading")
	stub.leaderboard_failed.emit(3, "timeout")
	await _shot("records_failed")
	panel.close()
	map._achievements.open()
	await _shot("achievements")
	map._achievements.close()
	map._account.open()
	await _shot("profile")
	map._account._ask_delete()
	await _shot("profile_delete")
	quit()


class RecordsStub:
	extends Node
	signal leaderboard_loaded(level_id: int, entries: Array)
	signal leaderboard_failed(level_id: int, reason: String)
	signal status_changed(text: String)

	func fetch_leaderboard(_level: int) -> void:
		pass

	func player_name() -> String:
		return "Рыцарь Фёдор"

	func cloud_save() -> void:
		pass

	func cloud_load() -> void:
		pass
