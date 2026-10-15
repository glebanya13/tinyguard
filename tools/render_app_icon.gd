extends SceneTree
## SUPERSEDED: since 2026-10-14 icon.png and ui/app/*.png come from assets/brand/logo.png via
## tools/make_logo_assets.py; running this script would overwrite the logo.
## Renders the Android launcher icons and the boot splash from the game models:
##   icon.png (192, rounded square), ui/app/icon_foreground.png and
##   ui/app/icon_background.png (432, adaptive icon), ui/app/splash.png (1280x720).
## Needs a GPU/OpenGL context:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/render_app_icon.gd

const OUT_DIR := "res://ui/app"
const BG_TOP := Color(0.36, 0.62, 0.95)
const BG_BOTTOM := Color(0.2, 0.36, 0.78)
const TITLE_COLOR := Color(0.98, 0.8, 0.4)
const OUTLINE := Color(0.09, 0.07, 0.16)

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
	var castle: Node3D = (load("res://assets/models/castle.glb") as PackedScene).instantiate()
	castle.position = Vector3(0.55, 0.0, -1.4)
	castle.rotation_degrees.y = -20.0
	castle.scale = Vector3.ONE * 0.75
	_scene.add_child(castle)
	var hero: Node3D = (load("res://assets/models/hero_knight.glb") as PackedScene).instantiate()
	hero.rotation_degrees.y = 18.0
	hero.scale = Vector3.ONE * 1.35
	_scene.add_child(hero)
	var slime: Node3D = (load("res://assets/models/slime_king.glb") as PackedScene).instantiate()
	slime.position = Vector3(-1.0, 0.0, -0.3)
	slime.rotation_degrees.y = 35.0
	slime.scale = Vector3.ONE * 0.75
	_scene.add_child(slime)
	var player := hero.find_child("AnimationPlayer") as AnimationPlayer
	if player and player.has_animation(&"attack"):
		player.play(&"attack")
		player.seek(0.18, true)
		player.pause()


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_capture()
		return false
	match _step:
		0:
			_frame(Vector2i(432, 432), Vector3(0.1, 0.85, -0.5), 4.8)
		1:
			_frame(Vector2i(1280, 720), Vector3(-0.15, 0.25, -0.4), 6.6)
			_add_title()
		_:
			print("render_app_icon: done")
			return true
	_wait = 5
	return false


func _frame(size: Vector2i, target: Vector3, distance: float) -> void:
	_viewport.size = size
	var dir := Vector3(0.25, 0.35, 1.0).normalized()
	_camera.look_at_from_position(target + dir * distance, target)


## Game title over the splash scene (2D on top of the 3D view).
func _add_title() -> void:
	var title := Label.new()
	title.text = "Bimbleguard"
	title.add_theme_font_size_override("font_size", 120)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_color_override("font_outline_color", OUTLINE)
	title.add_theme_constant_override("outline_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 520)
	title.size = Vector2(1280, 180)
	_viewport.add_child(title)


func _capture() -> void:
	var img: Image = _viewport.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	if _step == 0:
		_save_icons(img)
	else:
		_save_splash(img)
	_step += 1


func _save_icons(foreground: Image) -> void:
	# Adaptive icon: the art sits inside the central 66% safe zone.
	var fg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	var art: Image = foreground.duplicate()
	art.resize(320, 320, Image.INTERPOLATE_LANCZOS)
	fg.blend_rect(art, Rect2i(0, 0, 320, 320), Vector2i(56, 56))
	fg.save_png(ProjectSettings.globalize_path(OUT_DIR + "/icon_foreground.png"))
	var bg := _gradient(432, 432)
	bg.save_png(ProjectSettings.globalize_path(OUT_DIR + "/icon_background.png"))
	# Legacy 192 px icon: background + art in a rounded square.
	var full := _gradient(432, 432)
	full.blend_rect(fg, Rect2i(0, 0, 432, 432), Vector2i.ZERO)
	_round_corners(full, 80)
	full.resize(192, 192, Image.INTERPOLATE_LANCZOS)
	full.save_png(ProjectSettings.globalize_path("res://icon.png"))
	print("render_app_icon: icons")


func _save_splash(scene: Image) -> void:
	var out := _gradient(1280, 720)
	out.blend_rect(scene, Rect2i(0, 0, 1280, 720), Vector2i.ZERO)
	out.save_png(ProjectSettings.globalize_path(OUT_DIR + "/splash.png"))
	print("render_app_icon: splash")


func _gradient(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var c: Color = BG_TOP.lerp(BG_BOTTOM, float(y) / (h - 1))
		img.fill_rect(Rect2i(0, y, w, 1), c)
	return img


func _round_corners(img: Image, radius: int) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	for y in radius:
		for x in radius:
			var d: float = Vector2(radius - x - 0.5, radius - y - 0.5).length()
			if d > radius:
				for p in [
					Vector2i(x, y),
					Vector2i(w - 1 - x, y),
					Vector2i(x, h - 1 - y),
					Vector2i(w - 1 - x, h - 1 - y)
				]:
					img.set_pixelv(p, Color(0, 0, 0, 0))
