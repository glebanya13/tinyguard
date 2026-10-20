extends SceneTree
## Contact sheet of the hero: the standard look and every hero skin, with a villager
## next to the standard one for scale (needs a window, NOT --headless):
## SHOT_DIR=<dir> godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##   --resolution 1280x720 --script res://tools/shot_hero_skins.gd
## Writes <dir>/hero_skins.png.

const HERO_SCENE := "res://scenes/hero.tscn"
const VILLAGER_SCENE := "res://scenes/villager.tscn"
const CELL := Vector2i(400, 460)
const COLS := 5

var _dir: String = ""
var _camera: Camera3D


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("user://")
	_run.call_deferred()


func _run() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.78, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(50, 50)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.7, 0.35)
	ground.material_override = mat
	root.add_child(ground)
	_camera = Camera3D.new()
	_camera.fov = 32.0
	root.add_child(_camera)
	_camera.make_current()
	var ids: Array[String] = [""]
	for item: Dictionary in Cosmetics.in_category(Cosmetics.HERO):
		ids.append(str(item["id"]))
	var sheet := Image.create(CELL.x * COLS, CELL.y * 2, false, Image.FORMAT_RGB8)
	for i in ids.size():
		var hero := (load(HERO_SCENE) as PackedScene).instantiate() as Hero
		hero.set_physics_process(false)
		hero.is_ghost = true
		hero.skin_id = ids[i]
		root.add_child(hero)
		hero.get_node("Model").rotation.y = deg_to_rad(-25)
		var vil: Node3D = null
		if i == 0:
			vil = (load(VILLAGER_SCENE) as PackedScene).instantiate()
			root.add_child(vil)
			vil.set_process(false)
			vil.position = Vector3(0.9, 0, 0.1)
		_camera.position = Vector3(0.35, 1.1, 5.6)
		_camera.look_at(Vector3(0.35, 0.72, 0))
		for f in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var s: Vector2i = img.get_size()
		var rect := Rect2i(s.x / 2 - CELL.x / 2, s.y / 2 - CELL.y / 2, CELL.x, CELL.y)
		sheet.blit_rect(img, rect, Vector2i((i % COLS) * CELL.x, (i / COLS) * CELL.y))
		hero.queue_free()
		if vil != null:
			vil.queue_free()
	sheet.save_png(_dir.path_join("hero_skins.png"))
	quit()
