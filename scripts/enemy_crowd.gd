class_name EnemyCrowd
extends Node3D
## Draws every enemy with a few MultiMeshInstance3D nodes: one per mesh part of
## each enemy model (slime body, bat wings, golem arms...) plus one for all the
## health bars. A hundred slimes then cost a handful of draw calls instead of a
## hundred models with their own AnimationPlayers. The idle animation (squash,
## wing flaps, arm swing) is computed here from the part names.

const BAR_MESH: Mesh = preload("res://assets/materials/health_bar_mesh.tres")
## Animation cycle (the Blender idle tracks are 32 frames at 24 fps).
const CYCLE := 1.33
const SQUASH := 0.07
const HOP := 0.04
const WING_FLAP := 0.6
const ARM_SWING := 0.45
const BODY_SWAY := 0.07

## model path -> {"parts": Array[Dictionary], "members": Array[Enemy], "mms": Array[MultiMesh]}
var _kinds: Dictionary = {}
var _bars: MultiMesh
var _time: float = 0.0


func _ready() -> void:
	_bars = _new_multimesh(BAR_MESH)


func add(enemy: Enemy) -> void:
	var key: String = enemy.data.model.resource_path
	if not _kinds.has(key):
		_kinds[key] = _make_kind(enemy.data.model)
	var kind: Dictionary = _kinds[key]
	var members: Array[Enemy] = kind["members"]
	members.append(enemy)
	for mm: MultiMesh in kind["mms"]:
		_ensure_capacity(mm, members.size())


func remove(enemy: Enemy) -> void:
	var kind: Dictionary = _kinds.get(enemy.data.model.resource_path, {})
	if kind.is_empty():
		return
	var members: Array[Enemy] = kind["members"]
	var i: int = members.find(enemy)
	if i >= 0:
		members[i] = members[members.size() - 1]  # swap-remove keeps the list packed
		members.pop_back()


func _process(delta: float) -> void:
	_time += delta
	var bar_count: int = 0
	var camera: Camera3D = get_viewport().get_camera_3d()
	var bar_basis: Basis = camera.global_basis if camera else Basis.IDENTITY
	var total: int = 0
	for kind: Dictionary in _kinds.values():
		total += (kind["members"] as Array).size()
	_ensure_capacity(_bars, total)  # before writing: a resize drops the written bars
	for kind: Dictionary in _kinds.values():
		var members: Array[Enemy] = kind["members"]
		var parts: Array = kind["parts"]
		var mms: Array = kind["mms"]
		for i in members.size():
			var enemy: Enemy = members[i]
			var phase: float = (_time / CYCLE + enemy.anim_phase) * TAU
			var base: Transform3D = enemy.global_transform * enemy.model_offset()
			for p in parts.size():
				var part: Dictionary = parts[p]
				var mm: MultiMesh = mms[p]
				mm.set_instance_transform(i, base * part["rest"] * _animate(part["anim"], phase))
			if enemy.shows_health_bar():
				var ratio: float = enemy.health_ratio()
				var thick: float = 1.8 if enemy.is_boss() else 1.0
				var bar := Transform3D(
					bar_basis * Basis.from_scale(Vector3(enemy.bar_width() * ratio, thick, 1.0)),
					enemy.global_position + Vector3.UP * enemy.bar_height()
				)
				_bars.set_instance_transform(bar_count, bar)
				bar_count += 1
		for mm: MultiMesh in mms:
			mm.visible_instance_count = members.size()
	_bars.visible_instance_count = bar_count


## Visible enemy draw calls (for tests and profiling).
func multimesh_count() -> int:
	var n: int = 1
	for kind: Dictionary in _kinds.values():
		n += (kind["mms"] as Array).size()
	return n


func _make_kind(model: PackedScene) -> Dictionary:
	var root: Node3D = model.instantiate()
	var parts: Array = []
	var mms: Array = []
	var has_arms: bool = root.find_child("Arm*", true, false) != null
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var anim: StringName = &"none"
		if mesh_node.name.begins_with("Wing"):
			anim = &"wing_l" if mesh_node.name.ends_with("L") else &"wing_r"
		elif mesh_node.name.begins_with("Arm"):
			anim = &"arm_l" if mesh_node.name.ends_with("L") else &"arm_r"
		elif mesh_node.name == "Body":
			anim = &"sway" if has_arms else &"squash"
		var rest: Transform3D = root.transform.affine_inverse() * _rest_of(mesh_node, root)
		parts.append({"rest": rest, "anim": anim})
		mms.append(_new_multimesh(mesh_node.mesh))
	root.free()
	return {"parts": parts, "members": [] as Array[Enemy], "mms": mms}


func _rest_of(node: Node3D, root: Node3D) -> Transform3D:
	var xform: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent != null and parent != root:
		xform = (parent as Node3D).transform * xform
		parent = parent.get_parent()
	return xform


func _animate(anim: StringName, phase: float) -> Transform3D:
	var s: float = sin(phase)
	var xform := Transform3D.IDENTITY
	match anim:
		&"squash":
			var k := Vector3(1.0 + SQUASH * s, 1.0 - SQUASH * 1.3 * s, 1.0 + SQUASH * s)
			xform = Transform3D(Basis.from_scale(k), Vector3(0.0, HOP * maxf(0.0, -s), 0.0))
		&"sway":
			xform = Transform3D(
				Basis(Vector3.FORWARD, BODY_SWAY * s), Vector3(0.0, 0.02 * absf(s), 0.0)
			)
		&"wing_l", &"wing_r":
			var flap: float = WING_FLAP * sin(phase * 2.0) * (1.0 if anim == &"wing_l" else -1.0)
			xform = Transform3D(Basis(Vector3.FORWARD, flap), Vector3.ZERO)
		&"arm_l", &"arm_r":
			var swing: float = ARM_SWING * s * (1.0 if anim == &"arm_l" else -1.0)
			xform = Transform3D(Basis(Vector3.RIGHT, swing), Vector3.ZERO)
	return xform


func _new_multimesh(mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 16
	mm.visible_instance_count = 0
	# Fixed bounds: no per-frame AABB recompute over all instances.
	mm.custom_aabb = AABB(Vector3(-60.0, -5.0, -60.0), Vector3(120.0, 20.0, 120.0))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mm
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return mm


## MultiMesh buffers are resized in steps (doubling); resizing drops the
## transforms, but they are all rewritten every frame anyway.
func _ensure_capacity(mm: MultiMesh, needed: int) -> void:
	if needed > mm.instance_count:
		var visible: int = mm.visible_instance_count
		mm.instance_count = maxi(needed, mm.instance_count * 2)
		mm.visible_instance_count = visible
