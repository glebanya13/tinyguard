@tool
class_name HudIcon
extends Control
## Small vector icon for the HUD, drawn in code so the UI needs no image assets.

enum Kind { COIN, HEART, FLAG }

const GOLD := Color("f2c14e")
const GOLD_DARK := Color("a8741f")
const RED := Color("e5484d")
const RED_DARK := Color("9c2730")
const BLUE := Color("3e6fd6")
const CREAM := Color("fff4dc")

@export var kind: Kind = Kind.COIN:
	set(value):
		kind = value
		queue_redraw()


func _draw() -> void:
	var c: Vector2 = size / 2.0
	var r: float = minf(size.x, size.y) * 0.45
	match kind:
		Kind.COIN:
			draw_circle(c, r, GOLD_DARK)
			draw_circle(c, r * 0.8, GOLD)
			draw_arc(c, r * 0.55, 0.0, TAU, 24, GOLD_DARK, maxf(1.5, r * 0.12), true)
			draw_circle(c + Vector2(-r, -r) * 0.35, r * 0.16, CREAM)
		Kind.HEART:
			var pts := PackedVector2Array()
			for i in 32:
				var t: float = TAU * i / 32.0
				var x: float = 16.0 * pow(sin(t), 3)
				var y: float = 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
				pts.append(c + Vector2(x, -y - 2.0) * (r / 17.0))
			draw_colored_polygon(pts, RED)
			pts.append(pts[0])
			draw_polyline(pts, RED_DARK, maxf(1.5, r * 0.1), true)
			draw_circle(c + Vector2(-r * 0.4, -r * 0.35), r * 0.15, CREAM)
		Kind.FLAG:
			var pole := Rect2(c + Vector2(-r * 0.7, -r), Vector2(r * 0.18, r * 2.0))
			draw_rect(pole, GOLD_DARK)
			var cloth := PackedVector2Array(
				[
					c + Vector2(-r * 0.52, -r),
					c + Vector2(r, -r * 0.62),
					c + Vector2(-r * 0.52, -r * 0.1)
				]
			)
			draw_colored_polygon(cloth, BLUE)
			draw_circle(c + Vector2(-r * 0.61, -r), r * 0.16, GOLD)
