class_name FxParticles
extends Node3D
## Visual-only particle layer: every particle of one kind (soft dots that face the
## camera, or flat rings lying on the ground) is an instance of ONE MultiMesh, so
## the whole layer costs a single draw call however many puffs are alive. The
## particles are simulated here on the CPU (position, velocity, gravity, drag,
## size and colour over the lifetime) and never touch the battle simulation.

## Enough for a victory burst; extra particles are dropped, never queued.
const CAPACITY := 192
const TEXTURE_SIZE := 64

## True: flat rings on the ground; false: camera-facing dots.
var flat: bool = false

var _mm: MultiMesh
var _count: int = 0
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _size0 := PackedFloat32Array()
var _size1 := PackedFloat32Array()
var _grav := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _col0 := PackedColorArray()
var _col1 := PackedColorArray()


func _ready() -> void:
	set_process(false)
	_pos.resize(CAPACITY)
	_vel.resize(CAPACITY)
	_age.resize(CAPACITY)
	_life.resize(CAPACITY)
	_size0.resize(CAPACITY)
	_size1.resize(CAPACITY)
	_grav.resize(CAPACITY)
	_drag.resize(CAPACITY)
	_col0.resize(CAPACITY)
	_col1.resize(CAPACITY)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	if flat:
		quad.orientation = PlaneMesh.FACE_Y
	quad.material = _make_material()
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = quad
	_mm.instance_count = CAPACITY
	_mm.visible_instance_count = 0
	_mm.custom_aabb = AABB(Vector3(-80.0, -5.0, -80.0), Vector3(160.0, 30.0, 160.0))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = _mm
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## Starts one particle; returns false (and does nothing) when the layer is full.
func emit(
	at: Vector3,
	velocity: Vector3,
	life: float,
	size_from: float,
	size_to: float,
	color_from: Color,
	color_to: Color,
	gravity: float = 0.0,
	drag: float = 0.0
) -> bool:
	if _count >= CAPACITY:
		return false
	var i: int = _count
	_count += 1
	_pos[i] = at
	_vel[i] = velocity
	_age[i] = 0.0
	_life[i] = maxf(life, 0.05)
	_size0[i] = size_from
	_size1[i] = size_to
	_col0[i] = color_from
	_col1[i] = color_to
	_grav[i] = gravity
	_drag[i] = drag
	set_process(true)
	return true


func alive_count() -> int:
	return _count


## Removes every particle at once (effects switched off, level restart).
func clear() -> void:
	_count = 0
	if _mm:
		_mm.visible_instance_count = 0
	set_process(false)


func _process(delta: float) -> void:
	var i: int = 0
	while i < _count:
		_age[i] += delta
		if _age[i] >= _life[i]:
			_count -= 1
			_move(_count, i)  # swap-remove keeps the live ones packed at the front
			continue
		var k: float = _age[i] / _life[i]
		var v: Vector3 = _vel[i]
		v.y -= _grav[i] * delta
		v *= maxf(1.0 - _drag[i] * delta, 0.0)
		_vel[i] = v
		_pos[i] += v * delta
		var s: float = lerpf(_size0[i], _size1[i], k)
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), _pos[i]))
		_mm.set_instance_color(i, _col0[i].lerp(_col1[i], k))
		i += 1
	_mm.visible_instance_count = _count
	if _count == 0:
		set_process(false)


func _move(from: int, to: int) -> void:
	if from == to:
		return
	_pos[to] = _pos[from]
	_vel[to] = _vel[from]
	_age[to] = _age[from]
	_life[to] = _life[from]
	_size0[to] = _size0[from]
	_size1[to] = _size1[from]
	_grav[to] = _grav[from]
	_drag[to] = _drag[from]
	_col0[to] = _col0[from]
	_col1[to] = _col1[from]


func _make_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _make_texture()
	material.disable_receive_shadows = true
	if not flat:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
	return material


## Soft dot, or a thin ring for the flat layer; generated, no image files.
func _make_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	if flat:
		gradient.offsets = PackedFloat32Array([0.0, 0.62, 0.84, 1.0])
		gradient.colors = PackedColorArray(
			[Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]
		)
	else:
		gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		gradient.colors = PackedColorArray(
			[Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)]
		)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = TEXTURE_SIZE
	texture.height = TEXTURE_SIZE
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture
