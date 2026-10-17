extends SceneTree
## Renders HUD icons from 3D models into ui/icons/<name>.png: transparent,
## 256 px, fitted to the silhouette, with a dark outline and a soft drop shadow
## so they read on any background and at small sizes on a phone.
## NOTE: since the theme v2 redesign the UI glyph icons (coin, heart, star, sword, ...) are drawn
## by tools/make_ui_icons.py; running this script without names would overwrite them. Use it
## with names for the enemy portraits (slime*, boss, stone_golem) only.
## Needs a GPU/OpenGL context (not --headless):
##   godot --path . --script res://tools/render_icons.gd [-- name ...]
## Linux without a display: xvfb-run -a godot --path . --rendering-driver opengl3 --script ...

const RENDER := 512
const OUT_SIZE := 256
const OUT_DIR := "res://ui/icons"
## Space left around the silhouette for the outline and shadow (fraction of the size).
const MARGIN := 0.1
const OUTLINE_PX := 10
const OUTLINE_COLOR := Color(0.09, 0.07, 0.16, 1.0)
const SHADOW_OFFSET := Vector2i(0, 12)
const SHADOW_COLOR := Color(0.0, 0.0, 0.05, 0.35)
## Tower icons (tower_*.png) are drawn by tools/make_tower_icons.py instead.
## icon name -> [model, yaw degrees, pitch degrees, nodes to hide]
const ICONS := {
	"coin": ["res://assets/models/icon_coin.glb", 20.0, -8.0, []],
	"wood": ["res://assets/models/icon_wood.glb", 30.0, -25.0, []],
	"heart": ["res://assets/models/icon_heart.glb", 15.0, -5.0, []],
	"sword": ["res://assets/models/icon_sword.glb", 10.0, -5.0, []],
	"crown": ["res://assets/models/icon_crown.glb", 20.0, -22.0, []],
	"hourglass": ["res://assets/models/icon_hourglass.glb", 25.0, -12.0, []],
	"flag": ["res://assets/models/icon_flag.glb", 20.0, -8.0, []],
	"upgrade": ["res://assets/models/icon_upgrade.glb", 20.0, -8.0, []],
	"lock": ["res://assets/models/icon_lock.glb", 20.0, -12.0, []],
	"star": ["res://assets/models/icon_star.glb", 12.0, -6.0, []],
	"cancel": ["res://assets/models/icon_cancel.glb", 15.0, -8.0, []],
	"slime_bat": ["res://assets/models/slime_bat.glb", 25.0, -12.0, []],
	"slime_shield": ["res://assets/models/slime_shield.glb", 25.0, -12.0, []],
	"slime_splitter": ["res://assets/models/slime_splitter.glb", 25.0, -12.0, []],
	"slime_healer": ["res://assets/models/slime_healer.glb", 25.0, -12.0, []],
	"stone_golem": ["res://assets/models/stone_golem.glb", 25.0, -10.0, []],
	"boss": ["res://assets/models/slime_king.glb", 25.0, -12.0, []],
	"slime": ["res://assets/models/slime.glb", 25.0, -12.0, []],
	"villager": ["res://assets/models/villager.glb", 25.0, -10.0, []],
	"axe": ["res://assets/models/icon_axe.glb", 10.0, -5.0, []],
	"whirl": ["res://assets/models/icon_whirl.glb", 10.0, -5.0, []],
	"hammer": ["res://assets/models/icon_hammer.glb", 25.0, -15.0, []],
	"sell": ["res://assets/models/icon_sell.glb", 20.0, -10.0, []],
	"pause": ["res://assets/models/icon_pause.glb", 10.0, -5.0, []],
	"speed": ["res://assets/models/icon_speed.glb", 10.0, -5.0, []],
	"chest": ["res://assets/models/icon_chest.glb", 30.0, -22.0, []],
	"sound_on": ["res://assets/models/icon_sound_on.glb", 15.0, -5.0, []],
	"sound_off": ["res://assets/models/icon_sound_off.glb", 15.0, -5.0, []],
	"play": ["res://assets/models/icon_play.glb", 10.0, -5.0, []],
	"map": ["res://assets/models/icon_map.glb", 20.0, -30.0, []],
	"restart": ["res://assets/models/icon_restart.glb", 10.0, -5.0, []],
}

var _viewport: SubViewport
var _camera: Camera3D
var _holder: Node3D
var _queue: Array = []
var _wait: int = 0
var _current: String = ""


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RENDER, RENDER)
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.55, 0.72, 1.0)
	sky_material.sky_horizon_color = Color(1.0, 0.95, 0.85)
	sky_material.ground_bottom_color = Color(0.35, 0.3, 0.28)
	sky_material.ground_horizon_color = Color(0.9, 0.85, 0.75)
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
	env.adjustment_saturation = 1.25
	env.adjustment_contrast = 1.08
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.3
	_viewport.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 160, 0)
	rim.light_energy = 0.8
	rim.light_color = Color(0.8, 0.88, 1.0)
	_viewport.add_child(rim)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.far = 100.0
	_viewport.add_child(_camera)
	_holder = Node3D.new()
	_viewport.add_child(_holder)
	var only: PackedStringArray = OS.get_cmdline_user_args()
	for icon: String in ICONS:
		if only.is_empty() or icon in only:
			if ResourceLoader.exists(ICONS[icon][0]):
				_queue.append(icon)
			else:
				print("render_icons: skip ", icon, " (no model)")


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_save()
		return false
	if _queue.is_empty():
		print("render_icons: done")
		return true
	_current = _queue.pop_front()
	_stage(_current)
	_wait = 4
	return false


func _stage(icon: String) -> void:
	for child in _holder.get_children():
		child.queue_free()
	var spec: Array = ICONS[icon]
	var model: Node3D = (load(spec[0]) as PackedScene).instantiate()
	_holder.add_child(model)
	for hidden: String in spec[3]:
		var node := model.find_child(hidden) as Node3D
		if node:
			node.visible = false
	model.rotation_degrees = Vector3(0.0, float(spec[1]), 0.0)
	var pitch: float = deg_to_rad(float(spec[2]))
	var dir := Vector3(0.0, -sin(pitch), cos(pitch)).normalized()
	var box := _bounds(model)
	_camera.look_at_from_position(box.get_center() + dir * 30.0, box.get_center())
	# Fit the orthographic view to the projected box corners (silhouette fit).
	var inv: Transform3D = _camera.global_transform.affine_inverse()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p: Vector3 = inv * box.get_endpoint(i)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var center: Vector2 = (lo + hi) / 2.0
	_camera.global_position += _camera.global_basis * Vector3(center.x, center.y, 0.0)
	_camera.size = maxf(hi.x - lo.x, hi.y - lo.y) / (1.0 - 2.0 * MARGIN)


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree():
			continue
		var b: AABB = mesh.global_transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _save() -> void:
	var img: Image = _viewport.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var out := _decorate(img)
	out.resize(OUT_SIZE, OUT_SIZE, Image.INTERPOLATE_LANCZOS)
	var path := "%s/%s.png" % [OUT_DIR, _current]
	out.save_png(ProjectSettings.globalize_path(path))
	print("render_icons: ", path)


## Drop shadow + outline under the render: the silhouette (alpha) is stamped
## in a dark colour at offsets on a circle (dilation), the dilated shape is
## laid down once more, offset and translucent, as the shadow; the render goes on top.
func _decorate(img: Image) -> Image:
	var size: Vector2i = img.get_size()
	var rect := Rect2i(Vector2i.ZERO, size)
	var dark := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	dark.fill(OUTLINE_COLOR)
	var outline := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for r in [OUTLINE_PX * 0.35, OUTLINE_PX * 0.7, OUTLINE_PX]:
		for k in 32:
			var a: float = TAU * k / 32.0
			outline.blit_rect_mask(
				dark, img, rect, Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
			)
	var tint := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	tint.fill(SHADOW_COLOR)
	var out := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	out.blit_rect_mask(tint, outline, rect, SHADOW_OFFSET)
	out.blend_rect(outline, rect, Vector2i.ZERO)
	out.blend_rect(img, rect, Vector2i.ZERO)
	return out
