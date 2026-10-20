extends Node3D
## Short-lived zig-zag bolt through a list of world points (chain lightning).
## All segments are instances of one thin box in a single MultiMesh: one draw
## call per bolt instead of one per segment.

const BOLT_MESH: Mesh = preload("res://assets/materials/bolt_mesh.tres")
const ZAP_SOUND: AudioStream = preload("res://assets/audio/lightning_hit.wav")
## Sideways jitter of the kink in the middle of each hop (metres).
const JITTER := 0.18

@export var lifetime: float = 0.2


func setup(points: PackedVector3Array) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = ZAP_SOUND
	player.volume_db = -3.0
	player.pitch_scale = randf_range(0.95, 1.05)
	add_child(player)
	player.play()
	var segments: Array[Transform3D] = []
	var to_local: Transform3D = global_transform.affine_inverse()
	for i in points.size() - 1:
		var a: Vector3 = to_local * points[i]
		var b: Vector3 = to_local * points[i + 1]
		var mid: Vector3 = (
			(a + b) / 2.0
			+ Vector3(
				randf_range(-JITTER, JITTER),
				randf_range(-JITTER, JITTER),
				randf_range(-JITTER, JITTER)
			)
		)
		_segment(segments, a, mid)
		_segment(segments, mid, b)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = BOLT_MESH
	multimesh.instance_count = segments.size()
	for i in segments.size():
		multimesh.set_instance_transform(i, segments[i])
	var bolt := MultiMeshInstance3D.new()
	bolt.multimesh = multimesh
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bolt)
	get_tree().create_timer(lifetime, false).timeout.connect(queue_free)


## A box from `a` to `b`: the unit-length mesh stretched along its Z axis.
func _segment(segments: Array[Transform3D], a: Vector3, b: Vector3) -> void:
	var length: float = a.distance_to(b)
	if length < 0.01:
		return
	var direction: Vector3 = (b - a) / length
	var up: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(direction, up) * Basis.from_scale(Vector3(1.0, 1.0, length))
	segments.append(Transform3D(basis, (a + b) / 2.0))
