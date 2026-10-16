class_name DiagOverlay
extends CanvasLayer
## Diagnostics for a phone without a cable: FPS, frame time, memory, nodes, enemies,
## the cost of a simulation step and the notch of the quality guard. Hidden until the
## version line in the settings is tapped five times (GameSettings.diagnostics()). Also
## leaves the CrashTrace note every few seconds, shown or not.

const REFRESH := 0.5
const FONT_SIZE := 15

var _label: Label = null
var _guard: QualityGuard = null
var _sim: Sim = null
var _wave_manager: WaveManager = null
var _level_id: int = 0
var _timer: float = 0.0
var _trace_timer: float = 0.0
var _frame_sum: float = 0.0
var _frame_max: float = 0.0
var _frames: int = 0
var _last_usec: int = 0
var _fps: int = 0


func _init() -> void:
	layer = 120
	name = "DiagOverlay"


func _process(delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if _last_usec > 0:
		var frame_ms: float = (now - _last_usec) / 1000.0
		_frame_sum += frame_ms
		_frame_max = maxf(_frame_max, frame_ms)
		_frames += 1
	_last_usec = now
	# Real time, not the scaled delta: x2 speed must not make the timers run twice as fast.
	var real: float = delta / maxf(Engine.time_scale, 0.001)
	_trace_timer += real
	if _trace_timer >= CrashTrace.INTERVAL:
		_trace_timer = 0.0
		_write_trace("battle")
	_timer += real
	if _timer < REFRESH or _frames == 0:
		return
	_timer = 0.0
	_fps = roundi(1000.0 * _frames / _frame_sum)
	if _label.visible:
		_label.text = text()
	_frame_sum = 0.0
	_frame_max = 0.0
	_frames = 0


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_write_trace("background")
		NOTIFICATION_APPLICATION_RESUMED:
			_write_trace("battle")
		NOTIFICATION_WM_CLOSE_REQUEST:
			CrashTrace.write("closed")


func _exit_tree() -> void:
	# Leaving the battle (to the map, restart) is an orderly end.
	if _label != null:
		CrashTrace.write("map")


## `guard` may be null (tests).
func setup(sim: Sim, wave_manager: WaveManager, level_id: int, guard: QualityGuard) -> void:
	_sim = sim
	_wave_manager = wave_manager
	_level_id = level_id
	_guard = guard
	CrashTrace.read_previous()
	_label = Label.new()
	_label.position = Vector2(8, 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	_label.visible = GameSettings.diagnostics()
	add_child(_label)
	_write_trace("battle")


## The overlay text (public for tests).
func text() -> String:
	var lines: Array[String] = []
	var previous: String = CrashTrace.previous_text()
	if previous != "":
		lines.append(previous)
	var frame_avg: float = _frame_sum / maxf(_frames, 1)
	lines.append("FPS %d  frame %.1f ms (max %.0f)" % [_fps, frame_avg, _frame_max])
	var vram: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	lines.append("mem %.0f MB  vram %.0f MB  draws %d" % [_static_mb(), vram, draws])
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	lines.append("nodes %d  orphans %d" % [nodes, orphans])
	if _sim != null:
		lines.append(
			(
				"enemies %d  towers %d  shots %d"
				% [_sim.enemies.size(), _sim.towers.size(), _sim.projectiles.size()]
			)
		)
		lines.append(
			(
				"step %.1f ms  slow frames %d  dropped %d"
				% [_sim.last_frame_step_usec / 1000.0, _sim.over_budget_frames, _sim.dropped_steps]
			)
		)
	if _guard != null:
		lines.append("quality notch %d/%d" % [_guard.level, QualityGuard.MAX_LEVEL])
	return "\n".join(lines)


func _static_mb() -> float:
	return Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0


func _write_trace(state: String) -> void:
	(
		CrashTrace
		. write(
			state,
			{
				"level": _level_id,
				"wave": _wave_manager.current_wave if _wave_manager else 0,
				"enemies": _sim.enemies.size() if _sim else 0,
				"mem_mb": roundi(_static_mb()),
				"fps": _fps,
			}
		)
	)
