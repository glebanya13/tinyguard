extends Node3D
## One-shot effect: starts every particle emitter and sound below it, then frees
## itself. Spawned at a world position by gameplay code (hits, deaths, building).

## Seconds before the node frees itself (longest particle lifetime + sound).
@export var lifetime: float = 1.2
## Random pitch range so repeated sounds do not feel mechanical.
@export var pitch_jitter: float = 0.08


func _ready() -> void:
	# Spawners set global_position right after add_child(): start at the end of
	# the frame, otherwise the burst is emitted at the world origin.
	_start.call_deferred()


func _start() -> void:
	for emitter: CPUParticles3D in find_children("*", "CPUParticles3D", true, false):
		emitter.restart()
	for player: AudioStreamPlayer in find_children("*", "AudioStreamPlayer", true, false):
		player.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
		player.play()
	get_tree().create_timer(lifetime, false).timeout.connect(queue_free)
