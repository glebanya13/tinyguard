extends Node3D
## Root of an imported model: plays one of its animations in a loop, starting
## from a random phase so that several copies do not move in sync.

@export var animation: StringName = &"idle"
@export var random_phase: bool = true


func _ready() -> void:
	var player := find_child("AnimationPlayer", false) as AnimationPlayer
	if player == null or not player.has_animation(animation):
		push_warning("%s: no animation '%s'" % [name, animation])
		return
	player.get_animation(animation).loop_mode = Animation.LOOP_LINEAR
	player.play(animation)
	if random_phase:
		player.seek(randf() * player.current_animation_length, true)
