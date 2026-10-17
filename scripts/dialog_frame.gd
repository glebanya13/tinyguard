class_name DialogFrame
extends Control
## The one frame of every dialog (end screen, pause, settings, account, e-mail, records,
## treasury, confirmations...): a dim over the WHOLE viewport and a panel placed by
## the screen, never by the parent.
##
## Why it exists: screens put their UI in a root inset by the safe area (SafeArea), so a dim or a
## CenterContainer inside it covered only the area between the cutouts: a strip beside the notch
## stayed bright and the window sat off the screen centre. The frame is a top-level Control that
## always spans the viewport, whatever its parents are (parents only decide visibility and order).
##
## The panel is centred on the SCREEN. The room it may take is the screen minus the safe area minus
## MARGIN; it is narrower than the preferred width on a narrow screen, and the content scrolls
## when it is taller than the room. With a cutout on one side only, the centre is kept unless
## the panel would reach into the cutout, then it moves by the least amount.

## Free space kept between a panel and the screen edge / the safe area.
const MARGIN := 16.0
const DIM_COLOR := Color(0.04, 0.06, 0.14)

## Preferred width of the panel (shrinks on a narrow screen).
var preferred_width: float = 640.0
## The panel is at least this tall (fixed-size dialogs).
var min_height: float = 0.0
## Extra free space kept at the bottom (the on-screen keyboard).
var bottom_extra: float = 0.0
var dim: ColorRect = null
var panel: PanelContainer = null
## Put the dialog content here (a VBoxContainer inside a vertical ScrollContainer).
var body: VBoxContainer = null

var scroll: ScrollContainer = null
var _placing: bool = false


## Adds a frame to `host` (any Control: it may sit in an inset root) and returns it.
## `dim_alpha` is the opacity of the veil over the screen; the veil blocks touches.
static func attach(host: Control, width: float, dim_alpha: float = 0.7) -> DialogFrame:
	var frame := DialogFrame.new()
	frame.name = "Frame"
	frame.preferred_width = width
	frame.top_level = true
	host.add_child(frame)
	frame.dim.color = Color(DIM_COLOR, dim_alpha)
	return frame


## The area dialogs may use now: the viewport minus the safe area minus MARGIN.
static func room(viewport: Viewport, extra_bottom: float = 0.0) -> Rect2:
	var screen: Vector2 = viewport.get_visible_rect().size
	var safe: Vector4 = ScreenUtil.safe_margins(viewport)
	var bottom: float = maxf(safe.w, extra_bottom)  # an on-screen keyboard counts like a bar
	return Rect2(
		Vector2(safe.x + MARGIN, safe.y + MARGIN),
		screen - Vector2(safe.x + safe.z + 2.0 * MARGIN, safe.y + bottom + 2.0 * MARGIN)
	)


## Position and size of a panel of the wanted size on a screen: centred on the screen, inside the
## room; a pure function (the layout test checks it against the real panels).
static func fit_rect(screen: Vector2, room_rect: Rect2, wanted: Vector2) -> Rect2:
	var size := Vector2(minf(wanted.x, room_rect.size.x), minf(wanted.y, room_rect.size.y))
	var pos := (screen - size) / 2.0
	pos.x = clampf(
		pos.x, room_rect.position.x, maxf(room_rect.end.x - size.x, room_rect.position.x)
	)
	pos.y = clampf(
		pos.y, room_rect.position.y, maxf(room_rect.end.y - size.y, room_rect.position.y)
	)
	return Rect2(pos, size)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim = ColorRect.new()
	dim.name = "Dim"
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	panel = PanelContainer.new()
	panel.name = "Panel"
	add_child(panel)
	scroll = ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	body = VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	get_viewport().size_changed.connect(_refit)
	body.minimum_size_changed.connect(_refit)
	visibility_changed.connect(_refit)
	_refit()


## Re-reads the screen and the content and places everything (also called by the tests).
func refit() -> void:
	_place()


func _refit() -> void:
	if is_inside_tree():
		_place.call_deferred()


func _place() -> void:
	if _placing or not is_inside_tree():
		return
	_placing = true
	var viewport := get_viewport()
	var screen: Vector2 = viewport.get_visible_rect().size
	position = Vector2.ZERO
	size = screen
	dim.position = Vector2.ZERO
	dim.size = screen
	var margins: Vector2 = panel.get_theme_stylebox("panel").get_minimum_size()
	# Wider than preferred when the content cannot be narrower (rows of buttons), within the room.
	var wanted_width: float = maxf(preferred_width, body.get_combined_minimum_size().x + margins.x)
	var width: float = minf(wanted_width, room(viewport, bottom_extra).size.x)
	# The content is laid out at the final width first, to know how tall it wants to be.
	scroll.custom_minimum_size = Vector2(width - margins.x, 0.0)
	var need: float = body.get_combined_minimum_size().y + margins.y
	var rect: Rect2 = fit_rect(
		screen, room(viewport, bottom_extra), Vector2(width, maxf(need, min_height))
	)
	scroll.custom_minimum_size = rect.size - margins
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = rect.position
	panel.size = rect.size
	_placing = false
