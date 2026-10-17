class_name LayoutPreview
extends Control
## Tiny outline of the battle screen in the settings: the joystick, the road compass and
## its pin button, the sword / whirl buttons and the top bars where they really are
## (HudLayout, saved settings). Redrawn by the settings dialog when an option changes.

const SIZE := Vector2(304.0, 171.0)
const SCREEN := Vector2(1280.0, 720.0)


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var k: float = SIZE.x / SCREEN.x
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.35, 0.65, 0.35))
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.07, 0.11, 0.27), false, 3.0)
	var r: Dictionary = HudLayout.current(SCREEN)
	_box(r["top_left"], k, Color(0.12, 0.17, 0.4, 0.8))
	_box(r["top_right"], k, Color(0.12, 0.17, 0.4, 0.8))
	if r.has("map"):
		_box(r["map"], k, Color(0.16, 0.24, 0.55, 0.9))
		_box(r["pin"], k, Color(0.3, 0.55, 0.95))
	var joy: Rect2 = r["joystick"]
	var c: Vector2 = joy.get_center() * k
	draw_circle(c, joy.size.x * k * 0.5, Color(0.1, 0.16, 0.35, 0.65))
	draw_circle(c, joy.size.x * k * 0.2, Color(0.97, 0.75, 0.25))
	for key in ["attack", "spin"]:
		var b: Rect2 = r[key]
		draw_circle(b.get_center() * k, b.size.x * k * 0.5, Color(0.97, 0.75, 0.25))


func _box(rect: Rect2, k: float, color: Color) -> void:
	draw_rect(Rect2(rect.position * k, rect.size * k), color)
