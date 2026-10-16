extends SceneTree
## Contact sheets of the little people moving (needs a window, NOT --headless):
## SHOT_DIR=<dir> godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##   --resolution 1280x720 --script res://tools/shot_walkers.gd
## Writes walkers_hero.png (run, idle, swing, whirlwind) and walkers_villager.png
## (stroll, wave, hop): one row per move, frames 0.07 s apart, side-on camera.

const HERO_SCENE := "res://scenes/hero.tscn"
const VILLAGER_SCENE := "res://scenes/villager.tscn"
const CELL := Vector2i(300, 330)
const FRAMES := 8
const STEP := 0.07

var _dir: String = ""
var _camera: Camera3D
var _target: Node3D


func _initialize() -> void:
	_dir = OS.get_environment("SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("user://")
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _setup() -> void:
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
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.7, 0.35)
	ground.material_override = mat
	root.add_child(ground)
	_camera = Camera3D.new()
	_camera.fov = 40.0
	root.add_child(_camera)
	_camera.make_current()


func _aim(zoom: float) -> void:
	var p: Vector3 = _target.global_position
	_camera.global_position = p + Vector3(0.5, 1.5, 3.4) * zoom
	_camera.look_at(p + Vector3(0, 0.55, 0))


func _capture(row: Image, col: int) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var size: Vector2i = img.get_size()
	var rect := Rect2i(size.x / 2 - CELL.x / 2, size.y / 2 - CELL.y / 2 - 10, CELL.x, CELL.y)
	row.blit_rect(img, rect, Vector2i(col * CELL.x, 0))


func _sheet(rows: Array[Image], file: String) -> void:
	var sheet := Image.create(CELL.x * FRAMES, CELL.y * rows.size(), false, Image.FORMAT_RGB8)
	for i in rows.size():
		sheet.blit_rect(rows[i], Rect2i(0, 0, rows[i].get_width(), CELL.y), Vector2i(0, i * CELL.y))
	sheet.save_png(_dir.path_join(file))
	print("saved ", file)


## Records FRAMES frames; `drive` moves the figure each rendered frame.
func _row(drive: Callable, start_delay: float, step: float = STEP) -> Image:
	var row := Image.create(CELL.x * FRAMES, CELL.y, false, Image.FORMAT_RGB8)
	var t: float = 0.0
	var next: float = start_delay
	var col: int = 0
	var last: int = Time.get_ticks_usec()
	while col < FRAMES:
		await process_frame
		t += 1.0 / 60.0
		drive.call(1.0 / 60.0, t)
		_aim(1.35)
		if t >= next:
			await _capture(row, col)
			col += 1
			next += step
	return row


func _run() -> void:
	_setup()
	var hero := (load(HERO_SCENE) as PackedScene).instantiate() as Hero
	hero.set_physics_process(false)
	root.add_child(hero)
	var hero_model: Node3D = hero.get_node("Model")
	var puppet: Puppet = hero.get_node("Puppet")
	_target = hero
	hero_model.rotation.y = PI / 2.0
	var rows: Array[Image] = []
	var run := func(delta: float, _t: float) -> void: hero.position.x += 3.2 * delta
	var stand := func(_d: float, _t: float) -> void: pass
	await _frames(40)
	rows.append(await _row(run, 0.6))
	await get_process_frame_idle()
	rows.append(await _row(stand, 0.5, 0.25))
	puppet.play_action(&"attack")
	rows.append(await _row(stand, 0.0, 0.06))
	await _frames(40)
	puppet.play_action(&"spin", 0.45)
	rows.append(await _row(stand, 0.0, 0.05))
	_sheet(rows, "walkers_hero.png")
	hero.queue_free()

	var vil := (load(VILLAGER_SCENE) as PackedScene).instantiate() as Villager
	root.add_child(vil)
	vil.set_process(false)
	var vil_model: Node3D = vil.get_node("Model")
	var vpup: Puppet = vil.get_node("Puppet")
	_target = vil
	vil_model.rotation.y = PI / 2.0
	rows = []
	var stroll := func(delta: float, _t: float) -> void: vil.position.x += 0.6 * delta
	await _frames(40)
	rows.append(await _row(stroll, 0.5, 0.12))
	await _frames(60)
	vpup.play_action(&"wave")
	rows.append(await _row(stand, 0.0, 0.14))
	await _frames(80)
	vpup.play_action(&"cheer")
	rows.append(await _row(stand, 0.0, 0.14))
	await _frames(80)
	rows.append(await _row(stand, 0.0, 0.4))
	_sheet(rows, "walkers_villager.png")
	quit()


func get_process_frame_idle() -> void:
	await process_frame
