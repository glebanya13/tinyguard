extends SceneTree
## Screenshots of the map and the battle HUD for the theme-3 review (needs a window, NOT
## --headless). One size and one language per run:
## SHOT_DIR=<dir> SHOT_PREFIX=after SHOT_LANG=en godot --path . --rendering-driver opengl3 \
##   --fixed-fps 60 --resolution 1280x720 --script res://tools/shot_map.gd
## Writes <dir>/<prefix>_<lang>_<WxH>_{map,hud}.png. Scratch save files only.

const SAVE := "user://shot_map_progress.cfg"
const SETTINGS := "user://shot_map_settings.cfg"
const MAIN_SCENE := "res://scenes/main.tscn"

var _dir: String = ""
var _prefix: String = "map"
var _lang: String = "en"


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	GameSettings.config_path = SETTINGS
	LevelCatalog.erase_all()
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("user://")
	if OS.get_environment("SHOT_PREFIX") != "":
		_prefix = OS.get_environment("SHOT_PREFIX")
	if OS.get_environment("SHOT_LANG") != "":
		_lang = OS.get_environment("SHOT_LANG")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var size: Vector2i = img.get_size()
	img.save_png(_dir.path_join("%s_%s_%dx%d_%s.png" % [_prefix, _lang, size.x, size.y, name]))
	print("saved ", name, " ", size.x, "x", size.y)


func _swap(scene: Node) -> void:
	if current_scene != null:
		current_scene.queue_free()
	root.add_child(scene)
	current_scene = scene


func _run() -> void:
	GameSettings.set_language(_lang)
	for id in [1, 2, 3, 4, 5]:
		LevelCatalog.complete(id, [3, 2, 3, 1, 2][id - 1])
	LevelCatalog.selected_id = 5
	LevelCatalog.tutorial = false
	var online: Node = root.get_node("Online")
	online.setup("", "", HttpTransport.new())
	Onboarding.set_local_nickname("Sir Hedgehog", "sir hedgehog", false)
	change_scene_to_file(Onboarding.MAP_SCENE)
	await _frames(60)
	for toast in get_nodes_in_group(Toast.GROUP):
		toast.queue_free()
	await _frames(4)
	await _shot("map")
	if OS.get_environment("SHOT_ONLY_MAP") != "":
		LevelCatalog.erase_all()
		quit()
		return
	LevelCatalog.selected_id = 2
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	_swap(main)
	await _frames(60)
	await _shot("hud")
	LevelCatalog.erase_all()
	quit()
