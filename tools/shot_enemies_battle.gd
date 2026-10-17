extends SceneTree
## Battle screenshots with every enemy kind walking past the towers, a hit-flash frame and
## a death frame (needs a window, NOT --headless):
## SHOT_DIR=<dir> SHOT_PREFIX=enemies2_after LEVELS=1,4,6 godot --path . \
##   --rendering-driver opengl3 \
##   --fixed-fps 60 --resolution 1920x1080 --script res://tools/shot_enemies_battle.gd

const SAVE := "user://shot_enemies_progress.cfg"
const SESSION := "user://shot_enemies_session.dat"
const MAIN_SCENE := "res://scenes/main.tscn"
const PLAN := [0, 1, 2, 3, 1, 0, 2, 3, 1]
const CROWD := [
	"slime",
	"slime_fast",
	"slime",
	"slime_tank",
	"slime_bat",
	"slime_shield",
	"slime_splitter",
	"slime_mini",
	"slime_healer",
	"slime",
	"slime_fast",
	"slime_king",
	"slime_mini",
	"slime_splitter",
	"slime_bat",
	"slime_shield",
	"slime",
	"slime_tank",
]

var _dir: String = ""
var _prefix: String = "enemies2_after"


func _initialize() -> void:
	LevelCatalog.save_path = SAVE
	SessionStore.path = SESSION
	LevelCatalog.erase_all()
	SessionStore.clear()
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
	print("saved ", name)


func _run() -> void:
	var online: Node = root.get_node("Online")
	online.setup("", "", HttpTransport.new())
	Onboarding.set_local_nickname("Test", "test", false)
	for id in [1, 2, 3, 4, 5]:
		LevelCatalog.complete(id, 3)
	var ids: PackedStringArray = (
		(OS.get_environment("LEVELS") if OS.get_environment("LEVELS") != "" else "1,4,6").split(",")
	)
	for id_s in ids:
		await _battle(int(id_s))
	LevelCatalog.erase_all()
	SessionStore.clear()
	quit()


func _battle(id: int) -> void:
	LevelCatalog.selected_id = id
	LevelCatalog.endless = false
	LevelCatalog.tutorial = false
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.get_node("HUD").set("_touch", true)
	if current_scene:
		var old: Node = current_scene
		root.remove_child(old)
		old.free()
	root.add_child(main)
	current_scene = main
	paused = false
	await _frames(10)
	var gs: GameState = main.get_node("GameState")
	var wm: WaveManager = main.get_node("WaveManager")
	var bm: BuildManager = main.get_node("BuildManager")
	var hero: Hero = main.get_node("Level/Hero")
	var cam: CameraFollow = main.get_node("Camera")
	var route: Curve3D = wm.get_paths()[0].curve
	var ratio := 0.5
	var focus: Vector3 = route.sample_baked(route.get_baked_length() * ratio)
	var slots: Array = get_nodes_in_group(TowerSlot.GROUP)
	slots.sort_custom(
		func(a: Node3D, b: Node3D) -> bool:
			return a.global_position.distance_to(focus) < b.global_position.distance_to(focus)
	)
	gs.add_gold(2000)
	gs.add_wood(2000)
	for i in mini(6, slots.size()):
		bm.build_on(slots[i], bm.tower_types[PLAN[i % PLAN.size()]])
	wm.start_next_wave()
	hero.global_position = (slots[0] as Node3D).global_position + Vector3(1.3, 0.0, 1.8)
	cam.size = 11.5
	cam.snap()
	await _frames(240)
	for i in CROWD.size():
		var data: EnemyData = load("res://resources/enemies/%s.tres" % CROWD[i])
		var at: float = route.get_baked_length() * ratio - 7.0 + i * 0.9
		wm.spawn_extra(data, 1.0, at, 1, wm.get_paths()[0])
	bm.clear_selection()
	await _frames(40)
	await _shot("level%d_walk" % id)
	for node in get_nodes_in_group("enemies"):
		(node as Enemy).hit_flash = 1.0
	await _frames(2)
	await _shot("level%d_flash" % id)
	await _frames(240)
	await _shot("level%d_later" % id)
