extends Camera3D
## Fixed isometric camera that follows a target (the hero) with smoothing.
## The look-at point is clamped to `bounds` (XZ) so the view stays on the map.

@export var target: Node3D
## Higher is snappier.
@export var smoothing: float = 6.0
## Allowed area for the point the camera looks at (x, z, width, depth).
@export var bounds: Rect2 = Rect2(-10, -7, 20, 14)

var _offset: Vector3


func _ready() -> void:
	# Keep the editor-placed angle: the camera looks at the origin.
	_offset = global_position
	if target:
		global_position = _focus() + _offset


func _process(delta: float) -> void:
	if target == null:
		return
	var goal: Vector3 = _focus() + _offset
	global_position = global_position.lerp(goal, 1.0 - exp(-smoothing * delta))


func _focus() -> Vector3:
	var p: Vector3 = target.global_position
	return Vector3(
		clampf(p.x, bounds.position.x, bounds.end.x),
		0.0,
		clampf(p.z, bounds.position.y, bounds.end.y)
	)
