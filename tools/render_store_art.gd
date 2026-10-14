extends SceneTree
## Google Play art from the game models, deterministic:
##   assets/store/icon_512.png         512x512, full square (Play rounds it), RGBA but opaque
##   assets/store/feature_1024x500.png 1024x500, RGB (no alpha)
## Needs a GPU/OpenGL context (a window, not --headless):
##   godot --path . --rendering-driver opengl3 --script res://tools/render_store_art.gd

const OUT_DIR := "res://assets/store"
const BG_TOP := Color(0.36, 0.62, 0.95)
const BG_BOTTOM := Color(0.2, 0.36, 0.78)
const GRASS := Color(0.16, 0.42, 0.14)
const TITLE_COLOR := Color(0.98, 0.8, 0.4)
const OUTLINE := Color(0.09, 0.07, 0.16)
const SUPERSAMPLE := 2

var _viewport: SubViewport
var _camera: Camera3D
var _scene: Node3D
var _step: int = 0
var _wait: int = 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.55, 0.72, 1.0)
	sky_material.sky_horizon_color = Color(1.0, 0.95, 0.85)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.2
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	_viewport.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 160, 0)
	rim.light_energy = 0.7
	_viewport.add_child(rim)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_viewport.add_child(_camera)
	_scene = Node3D.new()
	_viewport.add_child(_scene)


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_capture()
		return false
	match _step:
		0:
			_build_icon_scene()
			_viewport.size = Vector2i(512, 512)
			_look(Vector3(0.1, 0.85, -0.5), 4.8)
		1:
			_build_feature_scene()
			_viewport.size = Vector2i(1024, 500) * SUPERSAMPLE
			_look(Vector3(0.5, 1.9, -0.5), 13.5)
			_add_title()
		_:
			print("render_store_art: done")
			return true
	_wait = 6
	return false


func _clear() -> void:
	for child in _scene.get_children():
		child.free()


func _model(path: String, at: Vector3, yaw: float, size: float = 1.0) -> Node3D:
	var node: Node3D = (load(path) as PackedScene).instantiate()
	node.position = at
	node.rotation_degrees.y = yaw
	node.scale = Vector3.ONE * size
	_scene.add_child(node)
	return node


func _pose_hero(hero: Node3D) -> void:
	var player := hero.find_child("AnimationPlayer") as AnimationPlayer
	if player and player.has_animation(&"attack"):
		player.play(&"attack")
		player.seek(0.18, true)
		player.pause()


## Same composition as the launcher icon (tools/render_app_icon.gd).
func _build_icon_scene() -> void:
	_clear()
	_model("res://assets/models/castle.glb", Vector3(0.55, 0.0, -1.4), -20.0, 0.75)
	_pose_hero(_model("res://assets/models/hero_knight.glb", Vector3.ZERO, 18.0, 1.35))
	_model("res://assets/models/slime_king.glb", Vector3(-1.0, 0.0, -0.3), 35.0, 0.75)


func _build_feature_scene() -> void:
	_clear()
	var ground := MeshInstance3D.new()
	var disk := CylinderMesh.new()
	disk.top_radius = 20.0
	disk.bottom_radius = 20.0
	disk.height = 0.4
	var grass := StandardMaterial3D.new()
	grass.albedo_color = GRASS
	grass.roughness = 1.0
	disk.material = grass
	ground.mesh = disk
	ground.position = Vector3(0.0, -0.2, 0.0)
	_scene.add_child(ground)
	_model("res://assets/models/castle.glb", Vector3(-5.2, 0.0, -2.6), 20.0, 0.9)
	_model("res://assets/models/tower_archer.glb", Vector3(-1.0, 0.0, -1.8), 10.0)
	_model("res://assets/models/tower_cannon.glb", Vector3(1.8, 0.0, -2.6), -10.0)
	_model("res://assets/models/tower_frost.glb", Vector3(4.2, 0.0, -1.6), -25.0)
	_model("res://assets/models/tower_lightning.glb", Vector3(6.6, 0.0, -2.6), -35.0)
	_model("res://assets/models/tree_pine.glb", Vector3(-8.0, 0.0, -0.6), 0.0, 1.2)
	_model("res://assets/models/tree_round.glb", Vector3(9.2, 0.0, -0.6), 40.0, 1.2)
	_pose_hero(_model("res://assets/models/hero_knight.glb", Vector3(-2.0, 0.0, 0.8), 25.0, 1.5))
	_model("res://assets/models/slime_king.glb", Vector3(5.0, 0.0, 0.5), -60.0, 0.8)
	_model("res://assets/models/slime.glb", Vector3(2.8, 0.0, 1.0), -70.0, 1.1)
	_model("res://assets/models/slime_tank.glb", Vector3(7.0, 0.0, 1.2), -50.0, 0.8)


func _look(target: Vector3, distance: float) -> void:
	var dir := Vector3(0.25, 0.35, 1.0).normalized()
	_camera.look_at_from_position(target + dir * distance, target)


## Game title over the 3D view (2D on top of it): top left of the wide banner.
func _add_title() -> void:
	var title := Label.new()
	title.text = "Bimbleguard"
	title.add_theme_font_size_override("font_size", 120 * SUPERSAMPLE)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_color_override("font_outline_color", OUTLINE)
	title.add_theme_constant_override("outline_size", 28 * SUPERSAMPLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 14 * SUPERSAMPLE)
	title.size = Vector2(1024 * SUPERSAMPLE, 160 * SUPERSAMPLE)
	title.name = "Title"
	_viewport.add_child(title)


func _capture() -> void:
	var img: Image = _viewport.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	if _step == 0:
		var out := _gradient(512, 512)
		out.blend_rect(_fit(img, 512), Rect2i(0, 0, 512, 512), Vector2i.ZERO)
		out.save_png(ProjectSettings.globalize_path(OUT_DIR + "/icon_512.png"))
		print("render_store_art: icon")
	else:
		var out := _gradient(1024 * SUPERSAMPLE, 500 * SUPERSAMPLE)
		out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i.ZERO)
		out.resize(1024, 500, Image.INTERPOLATE_LANCZOS)
		out.convert(Image.FORMAT_RGB8)
		out.save_png(ProjectSettings.globalize_path(OUT_DIR + "/feature_1024x500.png"))
		print("render_store_art: feature graphic")
		var title := _viewport.get_node_or_null("Title")
		if title:
			title.queue_free()
	_step += 1


## The icon art sits in the central 80% so Play's rounded mask never cuts it.
func _fit(img: Image, side: int) -> Image:
	var art: Image = img.duplicate()
	var inner: int = int(side * 0.8)
	art.resize(inner, inner, Image.INTERPOLATE_LANCZOS)
	var out := Image.create(side, side, false, Image.FORMAT_RGBA8)
	out.blend_rect(
		art, Rect2i(0, 0, inner, inner), Vector2i((side - inner) / 2, (side - inner) / 2)
	)
	return out


func _gradient(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var c: Color = BG_TOP.lerp(BG_BOTTOM, float(y) / (h - 1))
		img.fill_rect(Rect2i(0, y, w, 1), c)
	return img
