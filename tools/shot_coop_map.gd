extends SceneTree
## Screenshot of the world map with and without the "Co-op" button (it needs a
## database): SHOT_COOP=1 shows it (a fake database), anything else hides it.
## SHOT_LANG=en SHOT_COOP=1 SHOT_DIR=docs/screenshots godot --path . --resolution 1280x720 \
##   --rendering-driver opengl3 --script res://tools/shot_coop_map.gd

const Fake := preload("res://tests/fake_rtdb.gd")


func _initialize() -> void:
	LevelCatalog.save_path = "user://shot_coop_map.cfg"
	GameSettings.config_path = "user://shot_coop_map_settings.cfg"
	LevelCatalog.erase_all()
	_run.call_deferred()


func _run() -> void:
	var lang: String = (
		OS.get_environment("SHOT_LANG") if OS.get_environment("SHOT_LANG") != "" else "en"
	)
	var with_coop: bool = OS.get_environment("SHOT_COOP") == "1"
	GameSettings.set_language(lang)
	LevelCatalog.complete(1, 3)
	if with_coop:
		var net := Fake.FakeTransport.new()
		net.server = Fake.FakeServer.new()
		net.user_id = "u"
		(load("res://scripts/coop_run.gd") as GDScript).set("transport_override", net)
	change_scene_to_file("res://scenes/level_select.tscn")
	for i in 40:
		await process_frame
	var dir: String = (
		OS.get_environment("SHOT_DIR") if OS.get_environment("SHOT_DIR") != "" else "user://"
	)
	var path: String = (
		"%s/coop_%s_map_%s.png" % [dir, lang, "with_button" if with_coop else "no_button"]
	)
	root.get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
	quit(0)
