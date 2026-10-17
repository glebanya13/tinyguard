#!/usr/bin/env python3
"""Draws the UI icon set ui/icons/*.png (256x256, one style) with Pillow only: thick navy
outline, volume gradient, light edge on the top-left, darker lower edge, soft shadow below,
saturated palette of the logo. Deterministic, no external art.

  python3 -I tools/make_ui_icons.py            # all icons
  python3 -I tools/make_ui_icons.py star gear  # only these

The tower / enemy portraits (tower_*.png, slime*.png, boss, stone_golem, ...) are renders of
the game models and are not touched here.
"""

import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "ui", "icons")
N = 256
SS = 4
W = N * SS
NAVY = (18, 28, 69)

# palette: (top, bottom)
GOLD = ((255, 238, 112), (246, 160, 22))
GOLD_D = ((236, 178, 40), (190, 112, 12))
RED = ((255, 128, 128), (212, 40, 70))
BLUE = ((120, 178, 255), (44, 98, 205))
GREEN = ((150, 236, 120), (46, 168, 76))
BROWN = ((214, 150, 84), (140, 84, 40))
BROWN_D = ((170, 108, 56), (104, 60, 26))
WOOD_END = ((255, 232, 176), (232, 182, 104))
SILVER = ((255, 255, 255), (178, 196, 230))
STEEL = ((236, 244, 255), (140, 160, 200))
GREY = ((206, 214, 232), (132, 144, 176))
CREAM = ((255, 250, 232), (240, 216, 160))
PURPLE = ((196, 150, 255), (110, 62, 205))
GLASS = ((220, 246, 255), (130, 196, 240))
SKIN = ((255, 220, 180), (232, 160, 112))
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


def smooth(mask):
	return mask.filter(ImageFilter.GaussianBlur(1.2)).point(lambda v: 255 if v > 128 else 0)


def add(*ms):
	out = ms[0]
	for m in ms[1:]:
		out = ImageChops.lighter(out, m)
	return out


def sub(a, b):
	return ImageChops.subtract(a, b)


def rot(mask, angle, center=(128, 128), scale=1.0):
	m = mask.rotate(angle, resample=Image.BICUBIC, center=(center[0] * SS, center[1] * SS))
	if scale != 1.0:
		cx, cy = center[0] * SS, center[1] * SS
		k = 1.0 / scale
		m = m.transform(m.size, Image.AFFINE, (k, 0, cx - k * cx, 0, k, cy - k * cy), resample=Image.BICUBIC)
	return m


# ---- rendering --------------------------------------------------------------------------


class Part:
	def __init__(self, mask, colors, outline=4, shine=True, flat=False):
		self.mask, self.colors, self.outline, self.shine, self.flat = mask, colors, outline, shine, flat


def gradient(box, top, bottom):
	x0, y0, x1, y1 = box
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
		return None
	key = (bbox, colors)
	if key not in _GRAD:
		_GRAD[key] = gradient(bbox, colors[0], colors[1])
	return _GRAD[key]


def dilate(mask, px):
	if px <= 0:
		return mask
	k = px * SS
	return mask.filter(ImageFilter.GaussianBlur(k * 0.55)).point(lambda v: 255 if v > 14 else 0).filter(
		ImageFilter.GaussianBlur(0.8)
	)


def shift(mask, dx, dy):
	return ImageChops.offset(mask, int(dx * SS), int(dy * SS))


def composite(img, mask, rgb, alpha=255):
	layer = Image.new("RGBA", (W, W), rgb + (255,))
	a = mask.point(lambda v: v * alpha // 255) if alpha != 255 else mask
	layer.putalpha(a)
	img.alpha_composite(layer)


def render(parts, rotate=0.0, outer=8):
	img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
	total = add(*[p.mask for p in parts])
	outer_mask = dilate(total, outer)
	# soft shadow
	sh = shift(outer_mask, 0, 9).filter(ImageFilter.GaussianBlur(7 * SS / 2))
	composite(img, sh, (6, 12, 40), 105)
	composite(img, outer_mask, NAVY)
	for p in parts:
		if p.outline:
			composite(img, dilate(p.mask, p.outline), shade_navy())
		g = grad_for(p.mask, p.colors)
		layer = g.copy()
		layer.putalpha(ImageChops.multiply(layer.getchannel("A"), p.mask))
		img.alpha_composite(layer)
		if p.flat:
			continue
		# darker lower rim
		low = sub(p.mask, shift(p.mask, 0, -9))
		composite(img, ImageChops.multiply(low, p.mask), (20, 20, 70), 70)
		if p.shine:
			hi = sub(p.mask, shift(p.mask, 8, 10))
			hi = hi.filter(ImageFilter.GaussianBlur(2.5))
			composite(img, ImageChops.multiply(hi, p.mask), (255, 255, 255), 175)
	return img.resize((N, N), Image.LANCZOS)


def shade_navy():
	return (24, 34, 82)


# ---- icons ------------------------------------------------------------------------------


def i_star():
	m = rounded(poly(star_pts(128, 134, 104, 46)), 5)
	return [Part(m, GOLD, outline=0)]


def i_star_empty():
	m = rounded(poly(star_pts(128, 134, 104, 46)), 5)
	return [Part(m, ((196, 206, 232), (120, 132, 170)), outline=0)]


def i_coin():
	outer = ellipse((26, 26, 230, 230))
	inner = ellipse((58, 58, 198, 198))
	star = rounded(poly(star_pts(128, 132, 52, 24)), 3)
	return [
		Part(outer, GOLD),
		Part(inner, ((240, 176, 36), (255, 224, 96)), outline=3, shine=False),
		Part(star, ((255, 246, 190), (255, 204, 70)), outline=3, shine=False),
	]


def i_heart():
	m = add(ellipse((28, 40, 142, 154)), ellipse((114, 40, 228, 154)), poly([(34, 112), (222, 112), (128, 228)]))
	m = rounded(m, 8)
	return [Part(m, RED, outline=0)]


def i_wood():
	logs = []
	body = rrect((30, 96, 200, 214), 22)
	end = ellipse((150, 96, 234, 214))
	ring1 = ellipse((172, 124, 214, 186))
	ring2 = ellipse((184, 142, 202, 168))
	bark = stroke([(60, 128), (150, 128)], 7)
	bark2 = stroke([(52, 168), (140, 168)], 7)
	top = rrect((46, 40, 176, 130), 20)
	top_end = ellipse((124, 40, 200, 130))
	t_ring = ellipse((144, 62, 182, 108))
	logs += [
		Part(top, BROWN_D),
		Part(top_end, WOOD_END),
		Part(t_ring, ((246, 206, 140), (214, 160, 90)), outline=3, shine=False),
		Part(body, BROWN),
		Part(bark, BROWN_D, outline=0, flat=True),
		Part(bark2, BROWN_D, outline=0, flat=True),
		Part(end, WOOD_END),
		Part(ring1, ((246, 206, 140), (214, 160, 90)), outline=3, shine=False),
		Part(ring2, ((226, 176, 108), (190, 130, 66)), outline=3, shine=False),
	]
	return logs


def _vsword():
	blade = poly([(128, 18), (150, 60), (150, 150), (106, 150), (106, 60)])
	blade = rounded(blade, 2)
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
	handle = rrect((118, 40, 142, 232), 10)
	head = poly([(138, 52), (214, 40), (222, 150), (138, 132)])
	head = rounded(head, 5)
	edge = stroke([(214, 48), (220, 144)], 9)
	back = rrect((100, 50, 140, 104), 8)
	return rot_parts(
		[Part(handle, BROWN), Part(back, STEEL), Part(head, STEEL), Part(edge, ((255, 255, 255), (214, 226, 248)), outline=0, flat=True)],
		-35,
		0.92,
	)


def i_hammer():
	handle = rrect((118, 80, 142, 236), 10)
	head = rrect((52, 28, 204, 108), 16)
	band = rrect((52, 54, 204, 70), 4)
	return rot_parts([Part(handle, BROWN), Part(head, STEEL), Part(band, GREY, outline=0, flat=True)], 35)


def i_crown():
	body = poly([(30, 196), (22, 70), (84, 126), (128, 44), (172, 126), (234, 70), (226, 196)])
	body = rounded(body, 5)
	band = rrect((30, 176, 226, 220), 14)
	gems = [
		Part(ellipse((112, 178, 144, 214)), RED, outline=3),
		Part(ellipse((60, 182, 86, 212)), BLUE, outline=3),
		Part(ellipse((170, 182, 196, 212)), GREEN, outline=3),
	]
	tips = [Part(ellipse((c - 15, y - 15, c + 15, y + 15)), ((255, 250, 220), (255, 214, 90)), outline=3) for c, y in ((22, 68), (128, 40), (234, 68))]
	return [Part(body, GOLD), Part(band, GOLD_D)] + gems + tips


def i_trophy():
	cup = rounded(poly([(60, 40), (196, 40), (186, 118), (150, 162), (106, 162), (70, 118)]), 6)
	rim = rrect((52, 30, 204, 58), 12)
	h1 = arc((14, 46, 90, 126), 90, 270, 16)
	h2 = arc((166, 46, 242, 126), 270, 450, 16)
	stem = rrect((110, 156, 146, 200), 6)
	base = rrect((70, 196, 186, 232), 12)
	star = rounded(poly(star_pts(128, 96, 34, 15)), 2)
	return [
		Part(h1, GOLD_D, outline=3),
		Part(h2, GOLD_D, outline=3),
		Part(stem, GOLD_D),
		Part(base, GOLD),
		Part(cup, GOLD),
		Part(rim, GOLD),
		Part(star, ((255, 252, 220), (255, 216, 96)), outline=3, shine=False),
	]


def i_hourglass():
	top = rrect((46, 24, 210, 56), 12)
	bot = rrect((46, 200, 210, 232), 12)
	glass = poly([(70, 52), (186, 52), (186, 80), (140, 128), (186, 176), (186, 204), (70, 204), (70, 176), (116, 128), (70, 80)])
	glass = rounded(glass, 4)
	sand_t = poly([(86, 66), (170, 66), (150, 90), (106, 90)])
	sand_b = poly([(90, 196), (166, 196), (140, 160), (116, 160)])
	stream = rrect((124, 100, 132, 168), 3)
	return [
		Part(glass, GLASS),
		Part(sand_t, GOLD, outline=0, flat=True),
		Part(sand_b, GOLD, outline=0, flat=True),
		Part(stream, GOLD, outline=0, flat=True),
		Part(top, BROWN),
		Part(bot, BROWN),
	]


def i_flag():
	pole = rrect((52, 24, 74, 236), 10)
	banner = poly([(70, 36), (214, 52), (186, 98), (214, 144), (70, 128)])
	banner = rounded(banner, 4)
	top = ellipse((44, 14, 82, 52))
	star = rounded(poly(star_pts(128, 90, 24, 11)), 1)
	return [
		Part(pole, BROWN),
		Part(banner, BLUE),
		Part(star, ((255, 252, 220), (255, 214, 90)), outline=2, shine=False),
		Part(top, GOLD),
	]


def i_gear():
	body = ellipse((54, 54, 202, 202))
	teeth = []
	for i in range(8):
		t = rrect((106, 14, 150, 66), 8)
		teeth.append(rot(t, i * 45))
	ring = add(body, *teeth)
	hole = ellipse((96, 96, 160, 160))
	return [Part(ring, STEEL), Part(hole, DARK, outline=3, shine=False)]


def _speaker(color=SILVER):
	box = rrect((22, 92, 84, 164), 8)
	cone = poly([(70, 92), (130, 40), (130, 216), (70, 164)])
	cone = rounded(cone, 4)
	return [Part(cone, color), Part(box, color)]


def i_sound_on():
	parts = _speaker()
	w1 = arc((92, 84, 164, 172), -50, 50, 15)
	w2 = arc((92, 56, 214, 200), -52, 52, 15)
	return parts + [Part(w1, ((150, 220, 255), (70, 150, 240)), outline=3), Part(w2, ((150, 220, 255), (70, 150, 240)), outline=3)]


def i_sound_off():
	parts = _speaker()
	x = add(stroke([(156, 92), (226, 164)], 22), stroke([(226, 92), (156, 164)], 22))
	return parts + [Part(x, RED, outline=3)]


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
	tx, ty = -math.sin(ang), math.cos(ang)  # clockwise tangent
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
	return [Part(add(a, h1), GOLD), Part(add(b, h2), GOLD)]


def i_map():
	sheet = rounded(poly([(24, 60), (96, 40), (160, 62), (232, 42), (232, 198), (160, 218), (96, 196), (24, 216)]), 4)
	f1 = stroke([(96, 44), (96, 194)], 5, False)
	f2 = stroke([(160, 64), (160, 214)], 5, False)
	x = add(stroke([(176, 96), (208, 128)], 14), stroke([(208, 96), (176, 128)], 14))
	path = stroke([(44, 170), (70, 130), (118, 150), (140, 100)], 8)
	return [
		Part(sheet, CREAM),
		Part(f1, ((214, 188, 140), (190, 160, 110)), outline=0, flat=True),
		Part(f2, ((214, 188, 140), (190, 160, 110)), outline=0, flat=True),
		Part(path, ((120, 190, 255), (60, 130, 230)), outline=0, flat=True),
		Part(x, RED, outline=2),
	]


def i_lock():
	body = rrect((46, 108, 210, 232), 22)
	shackle = sub(arc((70, 22, 186, 150), 180, 360, 26), rrect((0, 100, 256, 256), 0))
	shackle = add(shackle, rrect((70, 84, 96, 120), 6), rrect((160, 84, 186, 120), 6))
	key = add(ellipse((112, 148, 144, 180)), poly([(120, 172), (136, 172), (140, 208), (116, 208)]))
	return [Part(shackle, STEEL), Part(body, GOLD), Part(key, ((90, 60, 40), (50, 30, 20)), outline=0, flat=True)]


def i_cancel():
	x = add(stroke([(54, 54), (202, 202)], 52), stroke([(202, 54), (54, 202)], 52))
	return [Part(x, RED, outline=0)]


def i_check():
	c = stroke([(44, 136), (100, 192), (214, 64)], 50)
	return [Part(c, GREEN, outline=0)]


def i_upgrade():
	a = rounded(poly([(128, 16), (232, 128), (170, 128), (170, 232), (86, 232), (86, 128), (24, 128)]), 8)
	return [Part(a, ((190, 255, 130), (60, 180, 70)))]


def i_sell():
	c2 = ellipse((70, 40, 226, 196))
	c2i = ellipse((98, 68, 198, 168))
	c1 = ellipse((24, 92, 180, 248))
	c1i = ellipse((52, 120, 152, 220))
	return [
		Part(c2, GOLD_D),
		Part(c2i, ((255, 224, 96), (240, 176, 36)), outline=3, shine=False),
		Part(c1, GOLD),
		Part(c1i, ((240, 176, 36), (255, 224, 96)), outline=3, shine=False),
		Part(rounded(poly(star_pts(102, 170, 34, 15)), 2), ((255, 246, 190), (255, 204, 70)), outline=2, shine=False),
	]


def i_villager():
	body = ellipse((34, 138, 222, 330))
	body = ImageChops.multiply(body, rrect((0, 0, 256, 232), 0))
	head = ellipse((74, 26, 182, 134))
	hat = add(ellipse((52, 58, 204, 96)), rrect((84, 22, 172, 74), 20))
	return [
		Part(body, BLUE),
		Part(head, SKIN),
		Part(hat, ((255, 226, 130), (224, 160, 60))),
	]


def i_shield():
	m = rounded(poly([(30, 30), (226, 30), (226, 120), (128, 238), (30, 120)]), 14)
	inner = rounded(poly([(58, 56), (198, 56), (198, 112), (128, 196), (58, 112)]), 10)
	st = rounded(poly(star_pts(128, 116, 40, 18)), 2)
	return [
		Part(m, GOLD),
		Part(inner, BLUE, outline=3),
		Part(st, ((255, 252, 220), (255, 214, 90)), outline=2, shine=False),
	]


def i_compass():
	rim = ellipse((20, 20, 236, 236))
	face = ellipse((50, 50, 206, 206))
	n = rounded(poly([(128, 62), (152, 128), (104, 128)]), 1)
	s = rounded(poly([(128, 194), (152, 128), (104, 128)]), 1)
	pin = ellipse((116, 116, 140, 140))
	return [
		Part(rim, GOLD),
		Part(face, CREAM, outline=3, shine=False),
		Part(n, RED, outline=2, shine=False),
		Part(s, STEEL, outline=2, shine=False),
		Part(pin, GOLD, outline=2),
	]


def i_chest():
	body = rrect((28, 108, 228, 224), 20)
	lid = sub(rrect((28, 40, 228, 140), 40), rrect((0, 126, 256, 256), 0))
	band1 = rrect((74, 40, 98, 224), 4)
	band2 = rrect((158, 40, 182, 224), 4)
	lock = rrect((108, 112, 148, 164), 10)
	hole = ellipse((120, 128, 136, 144))
	return [
		Part(body, BROWN),
		Part(lid, ((228, 164, 96), (170, 104, 52))),
		Part(band1, GOLD_D, outline=3),
		Part(band2, GOLD_D, outline=3),
		Part(lock, GOLD),
		Part(hole, ((90, 60, 40), (50, 30, 20)), outline=0, flat=True),
	]


ICONS = {
	"star": i_star,
	"star_empty": i_star_empty,
	"coin": i_coin,
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
	"shield": i_shield,
	"compass": i_compass,
	"chest": i_chest,
}


def main():
	names = sys.argv[1:] or list(ICONS)
	for name in names:
		img = render(ICONS[name]())
		img.save(os.path.join(OUT, name + ".png"), optimize=True)
		print("wrote", name)


if __name__ == "__main__":
	main()
