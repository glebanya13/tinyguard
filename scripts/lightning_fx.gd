extends Node3D
## Short-lived zig-zag bolt through a list of world points (chain lightning).
## Built from thin boxes sharing one mesh and one material.

const BOLT_MESH: Mesh = preload("res://assets/materials/bolt_mesh.tres")
## Sideways jitter of the kink in the middle of each hop (metres).
const JITTER := 0.18

@export var lifetime: float = 0.2


func setup(points: PackedVector3Array) -> void:
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var mid: Vector3 = (
			(a + b) / 2.0
			+ Vector3(
				randf_range(-JITTER, JITTER),
				randf_range(-JITTER, JITTER),
				randf_range(-JITTER, JITTER)
			)
		)
		_segment(a, mid)
		_segment(mid, b)
	get_tree().create_timer(lifetime, false).timeout.connect(queue_free)


func _segment(a: Vector3, b: Vector3) -> void:
	var length: float = a.distance_to(b)
	if length < 0.01:
		return
	var piece := MeshInstance3D.new()
	piece.mesh = BOLT_MESH
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(piece)
	piece.global_position = (a + b) / 2.0
	var up: Vector3 = (
		Vector3.UP if absf((b - a).normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	)
	piece.look_at(b, up)
	piece.scale = Vector3(1.0, 1.0, length)
