extends SceneTree
## Renders HUD icons from 3D models into ui/icons/<name>.png (transparent, 128 px).
## Needs a GPU/OpenGL context (not --headless):
##   godot --path . --script res://tools/render_icons.gd
## Linux without a display: xvfb-run -a godot --path . --rendering-driver opengl3 --script ...

const SIZE := 256
const OUT_SIZE := 128
const OUT_DIR := "res://ui/icons"
## icon name -> [model, yaw degrees, pitch degrees]
const ICONS := {
	"coin": ["res://assets/models/icon_coin.glb", 25.0, -10.0],
	"wood": ["res://assets/models/log_pile.glb", 35.0, -25.0],
	"heart": ["res://assets/models/icon_heart.glb", 20.0, -5.0],
	"sword": ["res://assets/models/icon_sword.glb", 15.0, -5.0],
	"crown": ["res://assets/models/icon_crown.glb", 20.0, -25.0],
	"hourglass": ["res://assets/models/icon_hourglass.glb", 25.0, -15.0],
	"flag": ["res://assets/models/icon_flag.glb", 25.0, -10.0],
	"upgrade": ["res://assets/models/icon_upgrade.glb", 25.0, -10.0],
	"lock": ["res://assets/models/icon_lock.glb", 25.0, -15.0],
	"star": ["res://assets/models/icon_star.glb", 20.0, -10.0],
	"cancel": ["res://assets/models/icon_cancel.glb", 20.0, -10.0],
	"tower_archer": ["res://assets/models/tower_archer.glb", 30.0, -25.0],
	"tower_cannon": ["res://assets/models/tower_cannon.glb", 30.0, -25.0],
	"tower_frost": ["res://assets/models/tower_frost.glb", 30.0, -25.0],
	"boss": ["res://assets/models/slime_king.glb", 25.0, -15.0],
	"slime": ["res://assets/models/slime.glb", 25.0, -15.0],
	"axe": ["res://assets/models/tree_round.glb", 30.0, -20.0],
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
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.92, 1.0)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -40, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.15
	_viewport.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.45
	_viewport.add_child(rim)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_viewport.add_child(_camera)
	_holder = Node3D.new()
	_viewport.add_child(_holder)
	_queue = ICONS.keys()


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
	for hidden in ["Lv2", "Lv3"]:
		var node := model.find_child(hidden) as Node3D
		if node:
			node.visible = false
	model.rotation_degrees = Vector3(0.0, float(spec[1]), 0.0)
	var box := _bounds(model)
	var center: Vector3 = box.get_center()
	var radius: float = box.size.length() * 0.5
	var pitch: float = deg_to_rad(float(spec[2]))
	var dir := Vector3(0.0, -sin(pitch), cos(pitch)).normalized()
	var distance: float = radius / sin(deg_to_rad(_camera.fov * 0.5)) * 1.02
	_camera.look_at_from_position(center + dir * distance, center)


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
	img.resize(OUT_SIZE, OUT_SIZE, Image.INTERPOLATE_LANCZOS)
	var path := "%s/%s.png" % [OUT_DIR, _current]
	img.save_png(ProjectSettings.globalize_path(path))
	print("render_icons: ", path)
