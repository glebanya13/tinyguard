class_name QualityGuard
extends Node
## Keeps a battle playable on a weak phone: when the frame rate stays low it lowers
## the purely visual settings one notch at a time (sun shadows, then MSAA, then fewer
## effects, then no effects at all). It never touches the simulation, so battles
## and replays are not affected, and it never raises quality again (no flip-flopping).
## The level reached is kept for the session: the next battle starts at it.

signal level_lowered(level: int)

## Average frame time (milliseconds) over WINDOW_SECONDS above which a notch goes.
const SLOW_FRAME_MS := 30.0
const WINDOW_SECONDS := 2.0
## No judgement right after the level starts (loading hitches).
const GRACE_SECONDS := 6.0
## Pause between two notches: let the previous one show its effect.
const COOLDOWN_SECONDS := 5.0
## A single frame counts for at most this much (a hitch is not a trend).
const FRAME_CLAMP_MS := 100.0
const MAX_LEVEL := 4

## Notches taken this session (shared by the battles of one run of the game).
static var session_level: int = 0

var level: int = 0

var _sun: DirectionalLight3D = null
var _viewport: Viewport = null
var _window_ms: float = 0.0
var _window_time: float = 0.0
var _window_frames: int = 0
var _grace: float = GRACE_SECONDS
var _cooldown: float = 0.0
var _last_usec: int = 0


## Takes the settings it may lower and applies the notches already taken.
func setup(sun: DirectionalLight3D, viewport: Viewport) -> void:
	_sun = sun
	_viewport = viewport
	level = 0
	while level < session_level:
		level += 1
		_apply(level)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var frame_ms: float = (now - _last_usec) / 1000.0 if _last_usec > 0 else 0.0
	_last_usec = now
	if get_tree().paused or DisplayServer.get_name() == "headless":
		_window_ms = 0.0
		_window_time = 0.0
		_window_frames = 0
		return
	feed(frame_ms)


## One frame of `frame_ms` real milliseconds (public so tests can drive the guard).
func feed(frame_ms: float) -> void:
	frame_ms = minf(frame_ms, FRAME_CLAMP_MS)
	var seconds: float = frame_ms / 1000.0
	_grace = maxf(_grace - seconds, 0.0)
	_cooldown = maxf(_cooldown - seconds, 0.0)
	if _grace > 0.0 or _cooldown > 0.0 or level >= MAX_LEVEL:
		return
	_window_ms += frame_ms
	_window_time += seconds
	_window_frames += 1
	if _window_time < WINDOW_SECONDS:
		return
	var mean_ms: float = _window_ms / _window_frames
	_window_ms = 0.0
	_window_time = 0.0
	_window_frames = 0
	if mean_ms > SLOW_FRAME_MS:
		lower()


## Takes one notch down (also used by tests).
func lower() -> void:
	if level >= MAX_LEVEL:
		return
	level += 1
	session_level = maxi(session_level, level)
	_cooldown = COOLDOWN_SECONDS
	_apply(level)
	level_lowered.emit(level)


func _apply(notch: int) -> void:
	match notch:
		1:
			if _sun != null and is_instance_valid(_sun):
				_sun.shadow_enabled = false
		2:
			if _viewport != null and is_instance_valid(_viewport):
				_viewport.msaa_3d = Viewport.MSAA_DISABLED  # costly bandwidth on a phone GPU
		3:
			GameSettings.cap_effects(GameSettings.FX_MIN)
		4:
			GameSettings.cap_effects(GameSettings.FX_OFF)
