class_name SafeArea
extends Node
## Keeps a full-screen UI root out of display cutouts and gesture bars: the offsets of
## `target` follow ScreenUtil.safe_margins() (zero on desktop). Add with SafeArea.attach().

var _target: Control = null


## Fit `root` (a Control anchored to the full rect) to the safe area now and on resize.
static func attach(root: Control) -> SafeArea:
	var fitter := SafeArea.new()
	fitter.name = "SafeArea"
	fitter._target = root
	root.add_child(fitter)
	return fitter


func _ready() -> void:
	get_viewport().size_changed.connect(apply)
	apply()


## Re-reads the margins (tests and screenshot tools call it after faking them).
func apply() -> void:
	if _target == null or not is_inside_tree():
		return
	var m: Vector4 = ScreenUtil.safe_margins(get_viewport())
	_target.offset_left = m.x
	_target.offset_top = m.y
	_target.offset_right = -m.z
	_target.offset_bottom = -m.w
