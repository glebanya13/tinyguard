#!/usr/bin/env python3
"""Draws the UI icon set ui/icons/*.png (256x256, one style), deterministic.

Style ("theme 3"): saturated colour, a vertical gradient, a light rim on the top-left and a
darker rim on the bottom-right, a soft gloss on the upper half and a soft drop shadow. NO thick
dark outline and NO ring badge: an icon stands on its own on the capsule / button. A part only
gets a hair-thin edge in a darker shade of its own colour so that it does not melt into a
button of a similar hue.

Two sources of shapes:
  * silhouettes from game-icons.net (tools/icon_src/*.svg, CC BY 3.0, authors in the file
    names and in docs/CREDITS.md), recoloured here; they need `rsvg-convert` (librsvg) to
    rasterise, only when icons are rebuilt - the PNGs are committed;
  * simple shapes drawn with Pillow (coin, gem, star, heart, arrows, ...).

  python3 -I tools/make_ui_icons.py            # all icons
  python3 -I tools/make_ui_icons.py star gear  # only these

The enemy portraits (slime*.png, boss, stone_golem, ...) are renders of the game models and
are not touched here.
"""

import io
import math
import os
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.environ.get("ICON_OUT") or os.path.join(ROOT, "ui", "icons")
SRC = os.path.join(ROOT, "tools", "icon_src")
N = 256
SS = 4
W = N * SS
SHADOW = (8, 14, 44)
EDGE_PX = 2

# palette: (top, bottom)
GOLD = ((255, 240, 128), (240, 150, 18))
GOLD_D = ((236, 178, 40), (190, 112, 12))
RED = ((255, 138, 128), (206, 36, 66))
BLUE = ((130, 190, 255), (40, 96, 210))
GREEN = ((160, 240, 120), (40, 160, 70))
BROWN = ((226, 160, 92), (128, 74, 34))
WOOD_END = ((255, 232, 176), (232, 182, 104))
SILVER = ((255, 255, 255), (170, 190, 228))
STEEL = ((240, 247, 255), (132, 152, 196))
CREAM = ((255, 250, 232), (236, 206, 148))
PURPLE = ((200, 156, 255), (108, 60, 206))
ORANGE = ((255, 226, 110), (255, 92, 24))
CYAN = ((200, 246, 255), (56, 168, 236))
DARK = ((70, 84, 130), (36, 46, 92))


# ---- shapes: every function returns an "L" mask at supersampled size --------------------


def blank():
	return Image.new("L", (W, W), 0)


def _s(v):
	return [x * SS for x in v] if isinstance(v, (list, tuple)) else v * SS


def poly(points):
	m = blank()
	ImageDraw.Draw(m).polygon([(x * SS, y * SS) for x, y in points], fill=255)
	return m


def ellipse(box):
	m = blank()
	ImageDraw.Draw(m).ellipse(_s(box), fill=255)
	return m


def rrect(box, r):
	m = blank()
	ImageDraw.Draw(m).rounded_rectangle(_s(box), radius=r * SS, fill=255)
	return m


def stroke(points, width, round_caps=True):
	m = blank()
	d = ImageDraw.Draw(m)
	pts = [(x * SS, y * SS) for x, y in points]
	d.line(pts, fill=255, width=int(width * SS), joint="curve")
	if round_caps:
		r = width * SS / 2
		for x, y in (pts[0], pts[-1]):
			d.ellipse((x - r, y - r, x + r, y + r), fill=255)
	return m


def arc(box, start, end, width):
	m = blank()
	d = ImageDraw.Draw(m)
	d.arc(_s(box), start, end, fill=255, width=int(width * SS))
	cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
	rx, ry = (box[2] - box[0]) / 2 - width / 2, (box[3] - box[1]) / 2 - width / 2
	for a in (start, end):
		x = cx + rx * math.cos(math.radians(a))
		y = cy + ry * math.sin(math.radians(a))
		r = width / 2
		d.ellipse(_s((x - r, y - r, x + r, y + r)), fill=255)
	return m


def star_pts(cx, cy, R, r, n=5, rot=-90):
	pts = []
	for i in range(n * 2):
		a = math.radians(rot + i * 180 / n)
		rad = R if i % 2 == 0 else r
		pts.append((cx + rad * math.cos(a), cy + rad * math.sin(a)))
	return pts


def rounded(mask, r):
	"""Round the corners of a mask (blur + threshold)."""
	k = r * SS
	return mask.filter(ImageFilter.GaussianBlur(k)).point(lambda v: 255 if v > 128 else 0)


def add(*ms):
	out = ms[0]
	for m in ms[1:]:
		out = ImageChops.lighter(out, m)
	return out


def sub(a, b):
	return ImageChops.subtract(a, b)


def both(a, b):
	return ImageChops.multiply(a, b)


def rot(mask, angle, center=(128, 128), scale=1.0):
	m = mask.rotate(angle, resample=Image.BICUBIC, center=(center[0] * SS, center[1] * SS))
	if scale != 1.0:
		cx, cy = center[0] * SS, center[1] * SS
		k = 1.0 / scale
		m = m.transform(m.size, Image.AFFINE, (k, 0, cx - k * cx, 0, k, cy - k * cy), resample=Image.BICUBIC)
	return m


def svg_mask(name, box=(22, 22, 234, 230), rotate=0.0, flip=False):
	"""Silhouette of a game-icons.net SVG, scaled to fit `box` (final px), centred."""
	path = os.path.join(SRC, name + ".svg")
	png = subprocess.run(
		["rsvg-convert", "-w", str(W), "-h", str(W), path], capture_output=True, check=True
	).stdout
	m = Image.open(io.BytesIO(png)).convert("RGBA").getchannel("A")
	if flip:
		m = m.transpose(Image.FLIP_LEFT_RIGHT)
	if rotate:
		m = m.rotate(rotate, resample=Image.BICUBIC, expand=False)
	bbox = m.getbbox()
	m = m.crop(bbox)
	bw, bh = (box[2] - box[0]) * SS, (box[3] - box[1]) * SS
	k = min(bw / m.width, bh / m.height)
	m = m.resize((max(1, int(m.width * k)), max(1, int(m.height * k))), Image.LANCZOS)
	out = blank()
	out.paste(m, (int(box[0] * SS + (bw - m.width) / 2), int(box[1] * SS + (bh - m.height) / 2)))
	return out


# ---- rendering --------------------------------------------------------------------------


class Part:
	def __init__(self, mask, colors, outline=2, shine=True, flat=False):
		self.mask, self.colors, self.outline, self.shine, self.flat = mask, colors, outline, shine, flat


def ramp(box, y0, y1, a0, a1):
	"""L image: alpha a0 at y0 easing to a1 at y1 (final px), constant outside."""
	col = Image.new("L", (1, W))
	px = col.load()
	for y in range(W):
		t = min(1.0, max(0.0, (y / SS - y0) / max(1e-6, y1 - y0)))
		px[0, y] = int(a0 + (a1 - a0) * t)
	return col.resize((W, W), Image.NEAREST)


def gradient(bbox, top, bottom):
	x0, y0, x1, y1 = bbox
	col = Image.new("RGBA", (1, W))
	px = col.load()
	h = max(1, y1 - y0)
	for y in range(W):
		t = min(1.0, max(0.0, (y - y0) / h))
		px[0, y] = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3)) + (255,)
	return col.resize((W, W), Image.NEAREST)


_GRAD = {}


def grad_for(mask, colors):
	bbox = mask.getbbox()
	if bbox is None:
		return None, None
	key = (bbox, colors)
	if key not in _GRAD:
		_GRAD[key] = gradient(bbox, colors[0], colors[1])
	return _GRAD[key], bbox


def dilate(mask, px):
	if px <= 0:
		return mask
	k = px * SS
	return mask.filter(ImageFilter.GaussianBlur(k * 0.55)).point(lambda v: 255 if v > 14 else 0)


def shift(mask, dx, dy):
	return ImageChops.offset(mask, int(dx * SS), int(dy * SS))


def composite(img, mask, rgb, alpha=255):
	layer = Image.new("RGBA", (W, W), tuple(rgb) + (255,))
	a = mask.point(lambda v: v * alpha // 255) if alpha != 255 else mask
	layer.putalpha(a)
	img.alpha_composite(layer)


def dim(rgb, k):
	return tuple(int(c * k) for c in rgb)


def render(parts, shadow=True):
	img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
	total = add(*[p.mask for p in parts])
	if shadow:
		sh = shift(total, 0, 7).filter(ImageFilter.GaussianBlur(5 * SS / 2))
		composite(img, sh, SHADOW, 110)
	for p in parts:
		if p.outline:
			composite(img, dilate(p.mask, EDGE_PX), dim(p.colors[1], 0.5), 235)
		g, bbox = grad_for(p.mask, p.colors)
		layer = g.copy()
		layer.putalpha(both(layer.getchannel("A"), p.mask))
		img.alpha_composite(layer)
		if p.flat:
			continue
		# darker rim on the bottom / right
		lo = both(sub(p.mask, shift(p.mask, -5, -6)).filter(ImageFilter.GaussianBlur(1.5)), p.mask)
		composite(img, lo, dim(p.colors[1], 0.55), 120)
		if p.shine:
			hi = both(sub(p.mask, shift(p.mask, 5, 6)).filter(ImageFilter.GaussianBlur(1.5)), p.mask)
			composite(img, hi, (255, 255, 255), 190)
			# soft gloss on the upper half
			y0, y1 = bbox[1] / SS, bbox[3] / SS
			gloss = ramp(bbox, y0, y0 + (y1 - y0) * 0.55, 70, 0)
			composite(img, both(gloss, p.mask), (255, 255, 255), 255)
	return img.resize((N, N), Image.LANCZOS)


# ---- drawn icons -----------------------------------------------------------------------


def i_star():
	m = rounded(poly(star_pts(128, 134, 108, 48)), 6)
	return [Part(m, GOLD, outline=2)]


def i_star_empty():
	m = rounded(poly(star_pts(128, 134, 108, 48)), 6)
	return [Part(m, ((206, 214, 238), (126, 138, 176)), outline=2, shine=False)]


def i_coin():
	outer = ellipse((22, 22, 234, 234))
	inner = ellipse((58, 58, 198, 198))
	star = rounded(poly(star_pts(128, 132, 52, 24)), 3)
	return [
		Part(outer, GOLD),
		Part(inner, ((236, 170, 30), (255, 226, 100)), outline=2, shine=False),
		Part(star, ((255, 252, 214), (255, 206, 70)), outline=0, shine=False),
	]


def i_gem():
	top_l, top_r = (60, 70), (196, 70)
	left, right, tip = (16, 112), (240, 112), (128, 232)
	table_l, table_r = (92, 112), (164, 112)
	mid_top = (128, 70)
	body = rounded(poly([top_l, top_r, right, tip, left]), 4)
	facets = [
		([top_l, mid_top, table_l], ((236, 252, 255), (170, 232, 255))),
		([mid_top, top_r, table_r], ((150, 226, 255), (90, 200, 250))),
		([top_l, table_l, left], ((120, 214, 255), (72, 176, 240))),
		([top_r, right, table_r], ((70, 176, 240), (40, 130, 220))),
		([mid_top, table_r, table_l], ((220, 250, 255), (140, 220, 255))),
		([left, table_l, tip], ((70, 170, 238), (34, 120, 214))),
		([table_l, table_r, tip], ((110, 206, 252), (50, 150, 232))),
		([table_r, right, tip], ((40, 128, 216), (24, 86, 180))),
	]
	parts = [Part(body, ((120, 210, 255), (30, 110, 200)))]
	for pts, col in facets:
		parts.append(Part(poly(pts), col, outline=0, flat=True))
	parts.append(Part(ellipse((70, 82, 96, 106)), ((255, 255, 255), (230, 250, 255)), outline=0, flat=True))
	return parts


def i_heart():
	m = add(ellipse((28, 40, 142, 154)), ellipse((114, 40, 228, 154)), poly([(34, 112), (222, 112), (128, 228)]))
	m = rounded(m, 8)
	return [Part(m, RED)]


def _vsword():
	blade = rounded(poly([(128, 18), (150, 60), (150, 150), (106, 150), (106, 60)]), 2)
	fuller = rrect((124, 52, 132, 140), 4)
	guard = rrect((70, 148, 186, 172), 11)
	grip = rrect((115, 170, 141, 214), 8)
	pommel = ellipse((104, 206, 152, 246))
	return [
		Part(blade, STEEL),
		Part(fuller, ((190, 206, 235), (140, 160, 205)), outline=0, flat=True),
		Part(guard, GOLD),
		Part(grip, BROWN),
		Part(pommel, GOLD),
	]


def rot_parts(parts, angle, scale=1.0):
	for p in parts:
		p.mask = rot(p.mask, angle, scale=scale)
	return parts


def i_sword():
	return rot_parts(_vsword(), -45, 1.12)


def i_axe():
	m = svg_mask("lorc__wood-axe", (28, 24, 228, 232))
	return [Part(m, STEEL)]


def i_hammer():
	m = svg_mask("lorc__anvil-impact", (20, 24, 236, 232))
	return [Part(m, ((255, 236, 200), (170, 150, 150)))]


def i_crown():
	m = svg_mask("lorc__crown", (14, 40, 242, 216))
	return [Part(m, GOLD)]


def i_trophy():
	m = svg_mask("delapouite__trophy-cup", (22, 14, 234, 242))
	return [Part(m, GOLD)]


def i_hourglass():
	m = svg_mask("lorc__hourglass", (44, 14, 212, 242))
	return [Part(m, ((255, 232, 140), (226, 140, 28)))]


def i_flag():
	m = svg_mask("lorc__flying-flag", (26, 16, 226, 240))
	return [Part(m, BLUE)]


def i_gear():
	m = svg_mask("lorc__cog", (20, 20, 236, 236))
	return [Part(m, STEEL)]


def _clip(mask, box):
	return both(mask, rrect(box, 0))


def i_sound_on():
	m = svg_mask("delapouite__speaker", (20, 36, 236, 220))
	body = _clip(m, (0, 0, 140, 256))
	waves = sub(m, body)
	return [
		Part(body, SILVER),
		Part(waves, ((160, 224, 255), (60, 150, 240)), outline=2),
	]


def i_sound_off():
	m = svg_mask("delapouite__speaker-off", (20, 36, 236, 220))
	body = _clip(m, (0, 0, 140, 256))
	cross = sub(m, body)
	return [Part(body, SILVER), Part(cross, RED, outline=2)]


def i_pause():
	a = rrect((54, 30, 112, 226), 16)
	b = rrect((144, 30, 202, 226), 16)
	return [Part(a, SILVER), Part(b, SILVER)]


def i_speed():
	a = rounded(poly([(24, 36), (130, 128), (24, 220)]), 6)
	b = rounded(poly([(122, 36), (232, 128), (122, 220)]), 6)
	return [Part(a, SILVER), Part(b, SILVER)]


def i_play():
	t = rounded(poly([(60, 28), (224, 128), (60, 228)]), 14)
	return [Part(t, GREEN)]


def _circ_arrow(colors, start=40, end=300):
	a = arc((30, 30, 226, 226), start, end, 44)
	ang = math.radians(end)
	r = 76.0
	ex, ey = 128 + r * math.cos(ang), 128 + r * math.sin(ang)
	tx, ty = -math.sin(ang), math.cos(ang)
	nx, ny = math.cos(ang), math.sin(ang)
	head = poly(
		[
			(ex + nx * 46 - tx * 8, ey + ny * 46 - ty * 8),
			(ex - nx * 46 - tx * 8, ey - ny * 46 - ty * 8),
			(ex + tx * 44, ey + ty * 44),
		]
	)
	return [Part(add(a, rounded(head, 3)), colors)]


def i_restart():
	return _circ_arrow(GREEN, 30, 300)


def i_whirl():
	a = arc((34, 34, 222, 222), 200, 340, 34)
	b = arc((34, 34, 222, 222), 20, 160, 34)
	h1 = rounded(poly([(214, 80), (246, 150), (176, 140)]), 2)
	h2 = rounded(poly([(42, 176), (10, 106), (80, 116)]), 2)
	WHIRL = ((255, 255, 255), (150, 190, 240))
	return [Part(add(a, h1), WHIRL), Part(add(b, h2), WHIRL)]


def i_map():
	m = svg_mask("lorc__treasure-map", (26, 22, 230, 234))
	return [Part(m, ((255, 246, 214), (222, 178, 112)))]


def i_lock():
	m = svg_mask("lorc__padlock", (40, 16, 216, 240))
	return [Part(m, GOLD)]


def i_cancel():
	x = add(stroke([(58, 58), (198, 198)], 48), stroke([(198, 58), (58, 198)], 48))
	return [Part(x, RED)]


def i_check():
	c = stroke([(48, 134), (102, 188), (210, 68)], 46)
	return [Part(c, GREEN)]


def i_upgrade():
	a = rounded(poly([(128, 16), (232, 128), (170, 128), (170, 232), (86, 232), (86, 128), (24, 128)]), 8)
	return [Part(a, ((200, 255, 140), (50, 170, 66)))]


def _coin_parts(cx, cy, r):
	outer = ellipse((cx - r, cy - r, cx + r, cy + r))
	k = r * 0.66
	inner = ellipse((cx - k, cy - k, cx + k, cy + k))
	return [
		Part(outer, GOLD),
		Part(inner, ((236, 170, 30), (255, 226, 100)), outline=2, shine=False),
	]


def i_sell():
	back = _coin_parts(150, 104, 84)
	front = _coin_parts(104, 148, 84)
	star = rounded(poly(star_pts(104, 150, 38, 17)), 2)
	return back + front + [Part(star, ((255, 252, 214), (255, 206, 70)), outline=0, shine=False)]


def _bust(cx, cy, s):
	head = ellipse((cx - 38 * s, cy - 92 * s, cx + 38 * s, cy - 16 * s))
	body = both(
		ellipse((cx - 76 * s, cy - 2 * s, cx + 76 * s, cy + 150 * s)),
		rrect((0, 0, 256, cy + 70 * s), 0),
	)
	return head, body


def i_villager():
	head, body = _bust(128, 140, 1.15)
	return [Part(body, BLUE), Part(head, ((255, 226, 190), (232, 160, 112)))]


def i_friends():
	h1, b1 = _bust(80, 136, 0.9)
	h2, b2 = _bust(176, 136, 0.9)
	h3, b3 = _bust(128, 152, 1.05)
	skin = ((255, 226, 190), (232, 160, 112))
	return [
		Part(b1, ((120, 200, 130), (46, 140, 76))),
		Part(h1, skin),
		Part(b2, ((255, 160, 120), (214, 70, 60))),
		Part(h2, skin),
		Part(b3, BLUE),
		Part(h3, skin),
	]


def i_shield():
	m = rounded(poly([(30, 30), (226, 30), (226, 120), (128, 238), (30, 120)]), 14)
	inner = rounded(poly([(60, 58), (196, 58), (196, 112), (128, 194), (60, 112)]), 10)
	st = rounded(poly(star_pts(128, 116, 40, 18)), 2)
	return [
		Part(m, GOLD),
		Part(inner, BLUE),
		Part(st, ((255, 252, 220), (255, 214, 90)), outline=0, shine=False),
	]


def i_compass():
	m = svg_mask("lorc__compass", (18, 18, 238, 238))
	return [Part(m, GOLD)]


def i_chest():
	m = svg_mask("lorc__locked-chest", (16, 30, 240, 232))
	return [Part(m, ((236, 170, 96), (140, 80, 34)))]


def i_wood():
	m = svg_mask("delapouite__wood-pile", (18, 22, 238, 234))
	return [Part(m, ((236, 176, 104), (128, 74, 34)))]


def i_shop():
	m = svg_mask("delapouite__shop", (16, 22, 240, 238))
	return [Part(m, ((255, 190, 120), (222, 76, 50)))]


def i_flame():
	m = svg_mask("carl-olsen__flame", (30, 14, 226, 242))
	return [Part(m, ORANGE)]


def i_cloud(ok):
	body = add(
		ellipse((30, 96, 130, 196)),
		ellipse((70, 50, 178, 158)),
		ellipse((130, 84, 232, 186)),
		rrect((80, 120, 190, 196), 40),
		rrect((30, 120, 232, 196), 40),
	)
	parts = [Part(rounded(body, 4), ((236, 248, 255), (142, 178, 230)))]
	if ok:
		mark = stroke([(88, 132), (116, 160), (172, 100)], 24)
		parts.append(Part(mark, GREEN))
	else:
		mark = add(stroke([(100, 108), (160, 168)], 22), stroke([(160, 108), (100, 168)], 22))
		parts.append(Part(mark, RED))
	return parts


def i_cloud_ok():
	return i_cloud(True)


def i_cloud_off():
	return i_cloud(False)


# towers: one silhouette each, colour tells them apart
def i_tower_archer():
	return [Part(svg_mask("lorc__pocket-bow", (20, 20, 236, 236)), ((190, 250, 120), (50, 160, 56)))]


def i_tower_cannon():
	return [Part(svg_mask("lorc__cannon", (14, 44, 242, 212)), ((255, 206, 120), (214, 92, 28)))]


def i_tower_frost():
	return [Part(svg_mask("lorc__snowflake-1", (18, 18, 238, 238)), CYAN)]


def i_tower_lightning():
	return [Part(svg_mask("lorc__lightning-storm", (20, 16, 236, 240)), ((255, 244, 140), (236, 150, 12)))]


ICONS = {
	"star": i_star,
	"star_empty": i_star_empty,
	"coin": i_coin,
	"gem": i_gem,
	"heart": i_heart,
	"wood": i_wood,
	"sword": i_sword,
	"axe": i_axe,
	"hammer": i_hammer,
	"crown": i_crown,
	"trophy": i_trophy,
	"hourglass": i_hourglass,
	"flag": i_flag,
	"gear": i_gear,
	"sound_on": i_sound_on,
	"sound_off": i_sound_off,
	"pause": i_pause,
	"speed": i_speed,
	"play": i_play,
	"restart": i_restart,
	"whirl": i_whirl,
	"map": i_map,
	"lock": i_lock,
	"cancel": i_cancel,
	"check": i_check,
	"upgrade": i_upgrade,
	"sell": i_sell,
	"villager": i_villager,
	"friends": i_friends,
	"shield": i_shield,
	"compass": i_compass,
	"chest": i_chest,
	"shop": i_shop,
	"flame": i_flame,
	"cloud_ok": i_cloud_ok,
	"cloud_off": i_cloud_off,
	"tower_archer": i_tower_archer,
	"tower_cannon": i_tower_cannon,
	"tower_frost": i_tower_frost,
	"tower_lightning": i_tower_lightning,
}


def main():
	names = sys.argv[1:] or list(ICONS)
	for name in names:
		img = render(ICONS[name]())
		img.save(os.path.join(OUT, name + ".png"), optimize=True)
		print("wrote", name)


if __name__ == "__main__":
	main()
