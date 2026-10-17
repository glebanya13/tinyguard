class_name QualityGuard
extends Node
## Keeps a battle playable (and alive) on a weak phone. When the frame rate stays low, or
## the system runs short of memory, it lowers the purely visual settings one notch at a time:
##   1 sun shadows off, 2 MSAA off, 3 fewer effects + 3D resolution 85%,
##   4 no effects + 3D resolution 75%, 5 far forest hidden + villager animation frozen + 65%,
##   6 "minimum": all decor hidden + 60%.
## Low memory (MemoryWatch) skips straight to the last notch when critical. It never touches
## the simulation, so battles and replays are not affected, and it never raises quality
## again (no flip-flopping). The level reached is kept for the session: the next battle
## starts at it. A phone that is weak by its RAM or GPU, or whose last battle died, starts
## lower from the first frame (start_level_for, CrashTrace.penalty).

signal level_lowered(level: int)
## The system is short of memory (notch jumped to the last one when `critical`).
signal memory_low(critical: bool)

## Average frame time (milliseconds) over WINDOW_SECONDS above which a notch goes.
const SLOW_FRAME_MS := 30.0
const WINDOW_SECONDS := 2.0
## No judgement right after the level starts (loading hitches).
const GRACE_SECONDS := 6.0
## Pause between two notches: let the previous one show its effect.
const COOLDOWN_SECONDS := 5.0
## A single frame counts for at most this much (a hitch is not a trend).
const FRAME_CLAMP_MS := 100.0
const MAX_LEVEL := 6
## Sun shadow map sizes (pixels) of the medium and the other tiers.
const SHADOW_SIZE_MEDIUM := 1024
const SHADOW_SIZE_HIGH := 2048
## Seconds between two looks at the free memory of the phone.
const MEMORY_CHECK_SECONDS := 4.0
## 3D resolution scale of each notch (index = notch); the HUD is always drawn at full size.
const RENDER_SCALES: Array[float] = [1.0, 1.0, 1.0, 0.85, 0.75, 0.65, 0.6]
## Notch that a phone with very little RAM starts on.
const VERY_LOW_START := 4

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
var _memory_timer: float = 0.0


## Notches a battle starts on for a graphics tier: the low tier begins with the sun shadows
## off, MSAA off and fewer effects (notch 3), the others with everything on.
static func start_level_for(tier: int, ram_mb: int = -1, penalty: int = 0) -> int:
	var start: int = 3 if tier == GameSettings.GFX_LOW else 0
	if tier == GameSettings.GFX_LOW and ram_mb > 0 and ram_mb < GameSettings.VERY_LOW_RAM_MB:
		start = VERY_LOW_START
	return clampi(start + penalty, 0, MAX_LEVEL)


## The player changed the graphics choice: forget what the guard lowered so far.
static func reset_session() -> void:
	session_level = 0
	GameSettings.cap_effects(GameSettings.FX_FULL)


## Takes the settings it may lower and applies the notches already taken (those of this
## session, or those of the graphics tier when that is lower).
func setup(sun: DirectionalLight3D, viewport: Viewport) -> void:
	_sun = sun
	_viewport = viewport
	level = 0
	var tier: int = GameSettings.graphics_tier()
	# Medium: a quarter of the shadow texels. (MSAA is off on phones from project.godot:
	# open Godot issues #97967 / #124258 report growing native memory with 3D MSAA on Android.)
	if OS.has_feature("mobile"):
		RenderingServer.directional_shadow_atlas_set_size(
			SHADOW_SIZE_MEDIUM if tier == GameSettings.GFX_MEDIUM else SHADOW_SIZE_HIGH, true
		)
	var physical: int = int(OS.get_memory_info().get("physical", -1))
	var ram_mb: int = physical / 1048576 if physical > 0 else -1
	# Runs the system killed or that crashed lower the start too (CrashTrace, ExitReasons).
	var start: int = maxi(session_level, start_level_for(tier, ram_mb, CrashTrace.penalty()))
	start = maxi(start, ExitReasons.start_notch())
	while level < start:
		level += 1
		_apply(level)


func _notification(what: int) -> void:
	if what == NOTIFICATION_OS_MEMORY_WARNING:
		check_memory(0)  # the system itself says so: treat as critical


func _process(delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var frame_ms: float = (now - _last_usec) / 1000.0 if _last_usec > 0 else 0.0
	_last_usec = now
	if get_tree().paused or DisplayServer.get_name() == "headless":
		_window_ms = 0.0
		_window_time = 0.0
		_window_frames = 0
		return
	feed(frame_ms)
	_memory_timer += delta / maxf(Engine.time_scale, 0.001)
	if _memory_timer >= MEMORY_CHECK_SECONDS:
		_memory_timer = 0.0
		check_memory(MemoryWatch.available_mb())


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


## Memory the system still has (MB, -1 unknown): low takes a notch, critical goes to the last
## one at once. Public so tests can drive it.
func check_memory(available_mb: int) -> void:
	var pressure: int = MemoryWatch.pressure(available_mb)
	if pressure == 0:
		return
	memory_low.emit(pressure == 2)
	if pressure == 2:
		while level < MAX_LEVEL:
			lower()
	elif _cooldown <= 0.0:
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
		5:
			_hide_group(&"qg_forest")
			_freeze_villagers()
		6:
			_hide_group(&"qg_decor")
	# Scaling after MSAA is off (open Godot issue 124258: MSAA + scaling leaks on Android).
	if notch >= 3 and _viewport != null and is_instance_valid(_viewport):
		if _viewport.msaa_3d == Viewport.MSAA_DISABLED:
			_viewport.scaling_3d_scale = RENDER_SCALES[notch]


func _hide_group(group: StringName) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(group):
		(node as Node3D).visible = false


func _freeze_villagers() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(Villager.GROUP):
		var puppet: Node = node.get_node_or_null("Puppet")
		if puppet != null:
			puppet.set_process(false)
