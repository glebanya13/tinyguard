extends Node3D
## Turns off shadow casting for every mesh below this node: small props and the
## ground gain nothing visible from it, but each shadow caster costs a draw call.


func _ready() -> void:
	for mesh: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
