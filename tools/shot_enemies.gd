extends SceneTree
## Contact sheet of every enemy model (needs a window, NOT --headless):
## SHOT_DIR=<dir> TAG=before [ONLY=a,b YAW=25] godot --path . --resolution 1400x800 \
##   --script res://tools/shot_enemies.gd
## Writes enemies2_<TAG>_big.png (large, three-quarter view) and enemies2_<TAG>_small.png
## (the same sheet shrunk to roughly the size of an enemy on a phone screen, then enlarged 3x).

const ALL := [
	"slime",
	"slime_fast",
	"slime_tank",
	"slime_bat",
	"slime_shield",
	"slime_splitter",
	"slime_mini",
	"slime_healer",
	"slime_king",
	"stone_golem",
]
const SPACING := 1.4

var _dir: String = ""
var _tag: String = "after"


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("user://")
	if OS.get_environment("TAG") != "":
		_tag = OS.get_environment("TAG")
	_run.call_deferred()


func _run() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.7, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	root.add_child(sun)
	var names: Array = ALL
	var cols: int = 5
	var cam_z: float = 8.6
	if OS.get_environment("ONLY") != "":
		names = Array(OS.get_environment("ONLY").split(","))
		cols = names.size()
		cam_z = 2.0 + 1.0 * cols
	var count: int = names.size()
	for i in count:
		var col: int = i % cols
		var row: int = i / cols
		var model: Node3D = (
			(load("res://assets/models/%s.glb" % names[i]) as PackedScene).instantiate()
		)
		root.add_child(model)
		model.position = Vector3((col - (cols - 1) * 0.5) * SPACING, 0.0, 0.0)
		model.position.z = 0.0
		model.position.y = -1.3 * row
		model.rotation_degrees.y = (
			float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 25.0
		)
		if names[i] == "slime_bat":
			model.position.y += 0.35
	var cam := Camera3D.new()
	cam.fov = 30.0
	root.add_child(cam)
	cam.make_current()
	cam.position = Vector3(0, cam_z * 0.4, cam_z)
	cam.look_at(Vector3(0, -0.5 if cols > 3 else 0.1, 0))
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(_dir.path_join("enemies2_%s_big.png" % _tag))
	var small: Image = img.duplicate()
	small.resize(img.get_width() / 3, img.get_height() / 3, Image.INTERPOLATE_BILINEAR)
	small.resize(small.get_width() * 3, small.get_height() * 3, Image.INTERPOLATE_NEAREST)
	small.save_png(_dir.path_join("enemies2_%s_small.png" % _tag))
	quit()
