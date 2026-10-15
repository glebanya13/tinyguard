class_name FxNumbers
extends Control
## Floating numbers (damage, gold) over the battle. Every glyph is a rectangle cut
## from one small atlas (the digits and "+" rendered once by a SubViewport), so all
## numbers share a texture and the canvas draws them in a single batch. Drawing the
## text itself costs a draw call per string and per outline: ten numbers were 20 calls.
## A fixed number of slots: further numbers are dropped, never queued.

const MAX_NUMBERS := 10
const LIFE := 0.8
## Metres the number rises over its life.
const RISE := 0.9
const GLYPHS := "0123456789+-"
## Atlas cell: glyphs are rendered at this size and drawn scaled down.
const ATLAS_FONT := 56
const CELL := Vector2(44.0, 72.0)
const OUTLINE := 8
const OUTLINE_COLOR := Color(0.1, 0.07, 0.05, 0.95)
## The font_size of add() is a height in pixels; the atlas font is ATLAS_FONT.
const HEIGHT_PER_SIZE := 1.35

var _entries: Array[Dictionary] = []
var _atlas: Texture2D = null
## Nothing is on screen: no redraw needed.
var _blank: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_atlas()


## Starts a number at a world point; false when all slots are busy (or the atlas
## is not rendered yet).
func add(text: String, world: Vector3, color: Color, font_size: int) -> bool:
	if _entries.size() >= MAX_NUMBERS or _atlas == null:
		return false
	_entries.append(
		{
			"text": text,
			"world": world,
			"color": color,
			"size": font_size,
			"age": 0.0,
			"pos": Vector2.ZERO
		}
	)
	return true


func count() -> int:
	return _entries.size()


func clear() -> void:
	_entries.clear()
	queue_redraw()


## Moves the numbers; `camera` projects their world points to the screen.
func step(delta: float, camera: Camera3D) -> void:
	if _entries.is_empty() and _blank:
		return
	var i: int = 0
	while i < _entries.size():
		var entry: Dictionary = _entries[i]
		var age: float = float(entry["age"]) + delta
		if age >= LIFE:
			_entries.remove_at(i)
			continue
		entry["age"] = age
		var k: float = age / LIFE
		var world: Vector3 = entry["world"]
		world.y += RISE * (1.0 - pow(1.0 - k, 2.0))
		entry["visible"] = not camera.is_position_behind(world)
		if entry["visible"]:
			entry["pos"] = camera.unproject_position(world)
		i += 1
	_blank = _entries.is_empty()
	queue_redraw()


func _draw() -> void:
	if _atlas == null:
		return
	# Outlines (atlas row 0) first, then fills (row 1): one texture, one batch.
	for row in 2:
		for entry in _entries:
			if entry.get("visible", false):
				_draw_entry(entry, row)


func _draw_entry(entry: Dictionary, row: int) -> void:
	var k: float = float(entry["age"]) / LIFE
	var text: String = entry["text"]
	var pop: float = 1.0 + 0.35 * maxf(1.0 - k * 6.0, 0.0)
	var alpha: float = 1.0 - maxf((k - 0.7) / 0.3, 0.0)
	var scale_to: float = float(entry["size"]) * HEIGHT_PER_SIZE / CELL.y * pop
	var cell: Vector2 = CELL * scale_to
	var at: Vector2 = entry["pos"]
	var left: float = at.x - cell.x * 0.5 * text.length()
	var tint: Color = OUTLINE_COLOR if row == 0 else entry["color"]
	tint.a *= alpha
	for i in text.length():
		var index: int = GLYPHS.find(text[i])
		if index < 0:
			continue
		var source := Rect2(Vector2(index * CELL.x, row * CELL.y), CELL)
		draw_texture_rect_region(
			_atlas, Rect2(Vector2(left + i * cell.x, at.y - cell.y * 0.5), cell), source, tint
		)


## Renders the glyphs into a transparent SubViewport once and keeps its texture.
func _build_atlas() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(int(CELL.x) * GLYPHS.length(), int(CELL.y) * 2)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := Control.new()
	painter.draw.connect(_paint_atlas.bind(painter))
	viewport.add_child(painter)
	add_child(viewport)
	_atlas = viewport.get_texture()


func _paint_atlas(painter: Control) -> void:
	var font: Font = get_theme_default_font()
	for i in GLYPHS.length():
		var glyph: String = GLYPHS[i]
		var width: float = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, ATLAS_FONT).x
		var x: float = i * CELL.x + (CELL.x - width) * 0.5
		var baseline: float = CELL.y * 0.78
		painter.draw_string_outline(
			font,
			Vector2(x, baseline),
			glyph,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			ATLAS_FONT,
			OUTLINE,
			Color.WHITE
		)
		painter.draw_string(
			font,
			Vector2(x, baseline + CELL.y),
			glyph,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			ATLAS_FONT,
			Color.WHITE
		)
