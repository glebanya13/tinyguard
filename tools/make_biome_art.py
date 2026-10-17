#!/usr/bin/env python3
"""Draws the level card emblems ui/biomes/<biome>.png (192x192): a tiny cartoon scene in a
framed rounded square, Pillow only, deterministic.   python3 -I tools/make_biome_art.py"""

import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 192
SS = 4
W = S * SS
NAVY = (18, 28, 69)
GOLD = (246, 184, 40)

BIOMES = {
	"meadow": {
		"sky": ((120, 196, 255), (214, 240, 255)),
		"hills": [((142, 214, 110), 128), ((92, 182, 84), 150)],
		"tree": ((72, 170, 78), (40, 118, 60)),
		"sun": (255, 232, 120),
		"deco": "round",
	},
	"winter": {
		"sky": ((150, 190, 240), (232, 244, 255)),
		"hills": [((236, 246, 255), 130), ((200, 224, 248), 152)],
		"tree": ((70, 150, 120), (36, 100, 90)),
		"sun": (240, 246, 255),
		"deco": "pine",
	},
	"autumn": {
		"sky": ((255, 190, 120), (255, 232, 190)),
		"hills": [((224, 160, 70), 130), ((178, 110, 50), 152)],
		"tree": ((240, 120, 40), (190, 70, 30)),
		"sun": (255, 214, 120),
		"deco": "round",
	},
	"desert": {
		"sky": ((255, 176, 110), (255, 232, 170)),
		"hills": [((250, 214, 130), 132), ((232, 176, 90), 154)],
		"tree": ((96, 170, 80), (56, 120, 60)),
		"sun": (255, 244, 170),
		"deco": "cactus",
	},
}


def vgrad(top, bottom):
	col = Image.new("RGB", (1, W))
	px = col.load()
	for y in range(W):
		t = y / (W - 1)
		px[0, y] = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
	return col.resize((W, W))


def shade(c, f):
	return tuple(max(0, min(255, int(v * f))) for v in c)


def draw_scene(name):
	cfg = BIOMES[name]
	img = vgrad(*cfg["sky"]).convert("RGBA")
	d = ImageDraw.Draw(img)
	k = SS
	# sun and two soft clouds
	d.ellipse((128 * k, 22 * k, 168 * k, 62 * k), fill=cfg["sun"] + (255,))
	for cx, cy, r in ((46, 44, 14), (66, 40, 18), (88, 46, 12)):
		d.ellipse(((cx - r) * k, (cy - r) * k, (cx + r) * k, (cy + r) * k), fill=(255, 255, 255, 230))
	# hills
	for col, base in cfg["hills"]:
		pts = [(0, S * k)]
		for x in range(0, S + 4, 4):
			y = base + 10 * math.sin(x / 26.0 + base) + 6 * math.sin(x / 11.0)
			pts.append((x * k, y * k))
		pts.append((S * k, S * k))
		d.polygon(pts, fill=col + (255,))
		d.line(pts[1:-1], fill=shade(col, 1.12) + (255,), width=3 * k)
	# deco
	deco = cfg["deco"]
	top, bot = cfg["tree"]
	spots = [(40, 150, 1.0), (92, 138, 0.8), (150, 152, 1.1), (118, 162, 0.7)]
	for x, y, sc in spots:
		if deco == "round":
			d.rectangle(((x - 3 * sc) * k, y * k, (x + 3 * sc) * k, (y + 14 * sc) * k), fill=(120, 76, 40, 255))
			d.ellipse(((x - 16 * sc) * k, (y - 22 * sc) * k, (x + 16 * sc) * k, (y + 6 * sc) * k), fill=bot + (255,))
			d.ellipse(((x - 14 * sc) * k, (y - 24 * sc) * k, (x + 12 * sc) * k, (y + 2 * sc) * k), fill=top + (255,))
		elif deco == "pine":
			d.rectangle(((x - 2 * sc) * k, (y + 4 * sc) * k, (x + 2 * sc) * k, (y + 14 * sc) * k), fill=(110, 70, 40, 255))
			for i in range(3):
				w = (16 - i * 4) * sc
				yy = y - i * 11 * sc
				d.polygon([((x - w) * k, (yy + 8 * sc) * k), ((x + w) * k, (yy + 8 * sc) * k), (x * k, (yy - 14 * sc) * k)], fill=(top if i % 2 == 0 else bot) + (255,))
				d.polygon([((x - w * 0.5) * k, (yy - 2 * sc) * k), ((x + w * 0.5) * k, (yy - 2 * sc) * k), (x * k, (yy - 14 * sc) * k)], fill=(246, 250, 255, 255))
		else:
			d.rounded_rectangle(((x - 5 * sc) * k, (y - 24 * sc) * k, (x + 5 * sc) * k, (y + 12 * sc) * k), radius=5 * k, fill=top + (255,))
			d.rounded_rectangle(((x - 15 * sc) * k, (y - 14 * sc) * k, (x - 9 * sc) * k, (y - 2 * sc) * k), radius=3 * k, fill=top + (255,))
			d.rounded_rectangle(((x + 9 * sc) * k, (y - 18 * sc) * k, (x + 15 * sc) * k, (y - 6 * sc) * k), radius=3 * k, fill=top + (255,))
	if name == "winter":
		for i in range(18):
			x = (i * 37) % S
			y = (i * 53) % 110
			d.ellipse((x * k, y * k, (x + 4) * k, (y + 4) * k), fill=(255, 255, 255, 235))
	return img


def framed(scene):
	img = Image.new("RGBA", (W, W), (0, 0, 0, 0))

	def mask(inset, radius):
		m = Image.new("L", (W, W), 0)
		ImageDraw.Draw(m).rounded_rectangle(
			(inset * SS, inset * SS, (S - inset) * SS - 1, (S - inset) * SS - 1), radius=radius * SS, fill=255
		)
		return m

	def paste(m, color):
		layer = Image.new("RGBA", (W, W), color + (255,))
		layer.putalpha(m)
		img.alpha_composite(layer)

	paste(mask(0, 28), NAVY)
	paste(mask(4, 24), GOLD)
	paste(mask(8, 20), (255, 232, 140))
	inner = mask(10, 18)
	scene.putalpha(inner)
	img.alpha_composite(scene)
	# inner shade on top, soft white rim
	sh = ImageChops.subtract(inner, ImageChops.offset(inner, 0, 14 * SS)).filter(ImageFilter.GaussianBlur(6))
	layer = Image.new("RGBA", (W, W), (10, 20, 70, 255))
	layer.putalpha(ImageChops.multiply(sh, inner).point(lambda v: v * 70 // 255))
	img.alpha_composite(layer)
	return img.resize((S, S), Image.LANCZOS)


def main():
	out = os.path.join(ROOT, "ui", "biomes")
	os.makedirs(out, exist_ok=True)
	for name in BIOMES:
		framed(draw_scene(name)).save(os.path.join(out, name + ".png"), optimize=True)
		print("wrote", name)


if __name__ == "__main__":
	main()
