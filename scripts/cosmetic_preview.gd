class_name CosmeticPreview
extends SubViewportContainer
## A small turntable of a cosmetic for the shop: the real model (the knight, the four
## towers, the castle) wearing the skin, in its own 3D world. Nothing here touches a
## battle; it exists only while the shop is open.

const HERO_MODEL: PackedScene = preload("res://assets/models/hero_knight.glb")
const CASTLE_MODEL: PackedScene = preload("res://assets/models/castle.glb")
const TOWER_MODELS: Array[PackedScene] = [
	preload("res://assets/models/tower_archer.glb"),
	preload("res://assets/models/tower_cannon.glb"),
	preload("res://assets/models/tower_frost.glb"),
	preload("res://assets/models/tower_lightning.glb"),
]
const TURN_SPEED := 0.6
const SPARK_ICON: Texture2D = preload("res://ui/icons/star.png")

var _viewport: SubViewport = null
var _pivot: Node3D = null
var _camera: Camera3D = null
var _sparks: Control = null
var _category: String = ""


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(300, 300)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_camera = Camera3D.new()
	_camera.fov = 28.0
	_viewport.add_child(_camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 1.1
	_viewport.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.86, 0.9, 1.0)
	env.ambient_light_energy = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	_sparks = Control.new()
	_sparks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sparks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sparks)
	_sparks.hide()


func _process(delta: float) -> void:
	if _pivot.get_child_count() > 0:
		_pivot.rotate_y(TURN_SPEED * delta)


## Shows `item` (an entry of resources/shop.json) worn on its model.
func show_item(item: Dictionary) -> void:
	for child in _pivot.get_children():
		_pivot.remove_child(child)
		child.queue_free()
	_pivot.rotation = Vector3.ZERO
	_category = str(item.get("category", ""))
	var id: String = str(item.get("id", ""))
	_sparks.visible = _category == Cosmetics.FX
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_DISABLED if _sparks.visible else SubViewport.UPDATE_ALWAYS
	)
	if _sparks.visible:
		_show_sparks(item)
		return
	var set_root := Node3D.new()
	_pivot.add_child(set_root)
	match _category:
		Cosmetics.HERO:
			set_root.add_child(HERO_MODEL.instantiate())
		Cosmetics.FLAG:
			set_root.add_child(CASTLE_MODEL.instantiate())
		Cosmetics.TOWER:
			for i in TOWER_MODELS.size():
				var tower := TOWER_MODELS[i].instantiate() as Node3D
				tower.position = Vector3((i - 1.5) * 1.25, 0.0, 0.0)
				set_root.add_child(tower)
				# The model carries one body per upgrade level; the game shows one of them.
				for extra in ["Base2", "Base3"]:
					var body: Node = tower.find_child(extra)
					if body != null:
						body.get_parent().remove_child(body)
						body.queue_free()
	Cosmetics.apply(set_root, id)
	_frame(set_root)


func _frame(root: Node3D) -> void:
	var box := AABB()
	var first := true
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var local: AABB = mesh.get_aabb()
		var world: AABB = mesh.global_transform * local if mesh.is_inside_tree() else local
		box = world if first else box.merge(world)
		first = false
	if first:
		return
	var center: Vector3 = box.get_center()
	root.position = -center
	var radius: float = maxf(box.size.length() * 0.5, 0.3)
	var distance: float = radius / sin(deg_to_rad(_camera.fov * 0.5)) * 1.05
	_camera.position = Vector3(0.0, radius * 0.45, distance)
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _show_sparks(item: Dictionary) -> void:
	for child in _sparks.get_children():
		child.queue_free()
	var tint: Color = Color.html(str(item.get("tint", "#ffffff")))
	var spots: Array[Vector2] = [
		Vector2(0.5, 0.5),
		Vector2(0.28, 0.32),
		Vector2(0.72, 0.36),
		Vector2(0.4, 0.72),
		Vector2(0.66, 0.7)
	]
	var sizes: Array[float] = [120.0, 60.0, 72.0, 52.0, 64.0]
	for i in spots.size():
		var star := TextureRect.new()
		star.texture = SPARK_ICON
		star.modulate = tint
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star.custom_minimum_size = Vector2(sizes[i], sizes[i])
		star.size = Vector2(sizes[i], sizes[i])
		star.anchor_left = spots[i].x
		star.anchor_right = spots[i].x
		star.anchor_top = spots[i].y
		star.anchor_bottom = spots[i].y
		star.offset_left = -sizes[i] / 2.0
		star.offset_right = sizes[i] / 2.0
		star.offset_top = -sizes[i] / 2.0
		star.offset_bottom = sizes[i] / 2.0
		_sparks.add_child(star)
		var tween: Tween = star.create_tween().set_loops()
		tween.tween_property(star, "modulate:a", 0.35, 0.5 + 0.12 * i)
		tween.tween_property(star, "modulate:a", 1.0, 0.5 + 0.12 * i)
