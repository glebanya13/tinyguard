class_name HudLayout
extends RefCounted
## Where the thumb controls live, in HUD canvas pixels (the HUD root is already inset by
## the safe area). One place computes the rectangles for the HUD, the road compass, the
## settings preview and the layout test, so they can never disagree.
##
## Bottom-left corner: the compass pin button, the compass panel above it, the joystick
## above (or, on the right, above the sword / whirl buttons). Nothing overlaps at any
## setting; the joystick keeps its dead zone and logic, only its size and place change.

const MARGIN := 16.0
const SIDE_LEFT := 0
const SIDE_RIGHT := 1
const MAP_SHOW := 0
const MAP_HIDE := 1
const MAP_WAVE := 2
## Joystick control side by size setting (small / medium / large); radius = 0.4 * side.
const JOY_SIDES: Array[float] = [168.0, 220.0, 272.0]
const JOY_RADIUS_RATIO := 0.4
## Extra lift by the position setting (lower / standard / higher).
const JOY_LIFT: Array[float] = [0.0, 24.0, 72.0]
## Distance of the joystick from the bottom edge when no compass is reserved above the corner.
const JOY_FREE_BOTTOM: Array[float] = [16.0, 56.0, 112.0]
## Compass panel size by size setting (small / medium / large): the map in it is the field seen
## turned like the screen, a diamond, so the panel is nearly square (see LaneMap).
const MAP_SIZES: Array[Vector2] = [
	Vector2(150.0, 150.0), Vector2(196.0, 186.0), Vector2(240.0, 224.0)
]
const PIN_SIZE := Vector2(84.0, 84.0)
const GAP := 8.0
const ATTACK_SIZE := 132.0
const SPIN_SIZE := 92.0


## Rects ("joystick", "map", "pin", "attack", "spin", "top_right", "top_left") for a HUD root
## of `size` and the given settings (indices as in GameSettings).
static func rects(
	size: Vector2, joy_size: int, joy_pos: int, joy_side: int, map_size: int, map_mode: int
) -> Dictionary:
	joy_size = clampi(joy_size, 0, 2)
	joy_pos = clampi(joy_pos, 0, 2)
	map_size = clampi(map_size, 0, 2)
	var out := {}
	var attack := Rect2(
		size.x - 24.0 - ATTACK_SIZE, size.y - 24.0 - ATTACK_SIZE, ATTACK_SIZE, ATTACK_SIZE
	)
	var spin := Rect2(size.x - 44.0 - SPIN_SIZE, size.y - 176.0 - SPIN_SIZE, SPIN_SIZE, SPIN_SIZE)
	out["attack"] = attack
	out["spin"] = spin
	out["top_right"] = Rect2(size.x - 192.0, 16.0, 176.0, 84.0)
	out["top_left"] = Rect2(16.0, 16.0, 600.0, 48.0)
	var map_h: float = 0.0
	var corner_top: float = size.y - MARGIN  # top edge of what the corner holds
	if map_mode != MAP_HIDE:
		var panel: Vector2 = MAP_SIZES[map_size]
		var pin := Rect2(MARGIN, size.y - MARGIN - PIN_SIZE.y, PIN_SIZE.x, PIN_SIZE.y)
		var map := Rect2(MARGIN, pin.position.y - GAP - panel.y, panel.x, panel.y)
		out["pin"] = pin
		out["map"] = map
		corner_top = map.position.y
		map_h = size.y - corner_top
	var side: float = JOY_SIDES[joy_size]
	var bottom: float
	var x: float
	if joy_side == SIDE_RIGHT:
		# Above the sword and whirl buttons (the command card lives lower and further left).
		bottom = size.y - spin.position.y + GAP + JOY_LIFT[joy_pos]
		x = size.x - 24.0 - side
	else:
		bottom = (
			map_h + GAP + JOY_LIFT[joy_pos] if map_mode != MAP_HIDE else JOY_FREE_BOTTOM[joy_pos]
		)
		x = 24.0
	# A high lift stops under the top bars (the lift gives way, never the gap below).
	var top: float = maxf(size.y - bottom - side, 108.0 if joy_side == SIDE_RIGHT else 72.0)
	out["joystick"] = Rect2(x, top, side, side)
	return out


## Same, with the saved settings.
static func current(size: Vector2) -> Dictionary:
	return rects(
		size,
		GameSettings.joystick_size(),
		GameSettings.joystick_position(),
		GameSettings.joystick_side(),
		GameSettings.minimap_size(),
		GameSettings.minimap_mode()
	)
