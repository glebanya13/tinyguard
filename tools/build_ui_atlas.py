#!/usr/bin/env python3
"""Builds ui/theme_atlas.png (9-slice buttons and panels) and the glyph icons in ui/icons/
from Kenney CC0 packs (see docs/CREDITS.md). Pillow is required.

  python3 -I tools/build_ui_atlas.py SRC_DIR

SRC_DIR holds the unpacked packs as SRC_DIR/uipack (Kenney "UI Pack"), SRC_DIR/adventure
("UI Pack - Adventure") and SRC_DIR/gicons ("Game Icons"). Prints the atlas regions
(x, y, w, h) that ui/theme.tres refers to.
"""

import json
import os
import sys

from PIL import Image, ImageChops, ImageEnhance, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COLORS = ["Yellow", "Blue", "Green", "Red", "Grey"]
BTN_W, BTN_H = 192, 64
NAVY = (0.09, 0.07, 0.16)


def load(path: str) -> Image.Image:
	return Image.open(path).convert("RGBA")


def button_set(src: str, color: str) -> dict:
	base = os.path.join(src, "uipack", "PNG", color, "Double")
	up = load(os.path.join(base, "button_rectangle_depth_gloss.png"))
	down = load(os.path.join(base, "button_rectangle_gloss.png"))
	size = (BTN_W, BTN_H)
	up = up.resize(size, Image.LANCZOS)
	down = down.resize(size, Image.LANCZOS)
	if color != "Grey":
		up, down = soften(up), soften(down)
	hover = ImageEnhance.Brightness(up).enhance(1.1)
	if color == "Grey":
		# disabled look: dim, slightly blue
		up = ImageEnhance.Brightness(up).enhance(0.62)
		down = ImageEnhance.Brightness(down).enhance(0.62)
		hover = up
	return {"up": up, "hover": hover, "down": down}


def soften(img: Image.Image) -> Image.Image:
	"""Kenney's buttons have a hard two-tone split (pale top half). Replace the pale half
	by a vertical gradient that fades into the saturated body, so labels read cleanly."""
	img = img.copy()
	px = img.load()
	w, h = img.size
	cx = w // 2
	top = 3 * h // 64
	pale = px[cx, top + 5][:3]
	split = top + 5
	while split < h - 2 and sum(abs(px[cx, split][i] - pale[i]) for i in range(3)) < 30:
		split += 1
	body = px[cx, split + 3][:3]
	span = float(split + 2 - top)
	for y in range(top, split + 3):
		t = min(1.0, max(0.0, (y - top) / span))
		t = t * t * (3 - 2 * t)
		col = tuple(int(pale[i] * (1 - t) + body[i] * t) for i in range(3))
		for x in range(w):
			r, g, b, a = px[x, y]
			if a and (
				all(abs((r, g, b)[i] - pale[i]) < 10 for i in range(3))
				or all(abs((r, g, b)[i] - body[i]) < 10 for i in range(3))
			):
				px[x, y] = col + (a,)
	return img


def round_button(src: str) -> dict:
	base = os.path.join(src, "uipack", "PNG", "Yellow", "Double")
	up = load(os.path.join(base, "button_round_depth_gloss.png"))
	down = load(os.path.join(base, "button_round_gloss.png"))
	up, down = soften(up), soften(down)
	return {"up": up, "hover": ImageEnhance.Brightness(up).enhance(1.1), "down": down}


PANEL_MAP = [
	((109, 75, 39), (34, 24, 66)),  # outer outline -> deep indigo
	((180, 123, 65), (244, 190, 72)),  # frame -> gold
	((163, 112, 58), (196, 138, 40)),  # inner frame edge -> dark gold
]


def recolor_panel(img: Image.Image, interior_top: tuple, interior_bottom: tuple) -> Image.Image:
	"""Cream paper panel with a wooden frame -> indigo panel with a gold frame."""
	px = img.load()
	w, h = img.size
	out = Image.new("RGBA", img.size)
	op = out.load()
	for y in range(h):
		t = y / (h - 1)
		fill = tuple(int(interior_top[i] * (1 - t) + interior_bottom[i] * t) for i in range(3))
		for x in range(w):
			r, g, b, a = px[x, y]
			if a == 0:
				op[x, y] = (0, 0, 0, 0)
				continue
			cands = [((255, 241, 210), fill)] + PANEL_MAP
			best = min(cands, key=lambda c: sum((c[0][i] - (r, g, b)[i]) ** 2 for i in range(3)))
			op[x, y] = best[1] + (a,)
	return out


def make_panels(src: str) -> dict:
	base = os.path.join(src, "adventure", "PNG", "Double")
	paper = load(os.path.join(base, "panel_brown.png"))
	navy = recolor_panel(paper, (48, 66, 128), (26, 36, 82)).resize((64, 64), Image.LANCZOS)
	dark = recolor_panel(paper, (30, 42, 92), (18, 26, 62)).resize((64, 64), Image.LANCZOS)
	paper = paper.resize((64, 64), Image.LANCZOS)
	return {"panel": navy, "chip": dark, "paper": paper}


def glyph(
	path: str, fill_top: tuple, fill_bottom: tuple, scale: float = 0.62, canvas=256, shift=(0, -6)
) -> Image.Image:
	"""White glyph -> coloured gradient fill, navy outline and soft shadow (like render_icons.gd)."""
	g = load(path)
	alpha = g.split()[3]
	side = int(canvas * scale)
	k = side / max(alpha.size)
	alpha = alpha.resize((max(1, int(alpha.width * k)), max(1, int(alpha.height * k))), Image.LANCZOS)
	# crisp the upscaled edge
	alpha = alpha.filter(ImageFilter.GaussianBlur(1.2)).point(lambda v: 0 if v < 100 else min(255, (v - 100) * 4))
	mask = Image.new("L", (canvas, canvas), 0)
	mask.paste(
		alpha, ((canvas - alpha.width) // 2 + shift[0], (canvas - alpha.height) // 2 + shift[1])
	)
	pad = 22
	# round dilation: blur wide, then threshold low
	outline = mask.filter(ImageFilter.GaussianBlur(pad * 0.55)).point(lambda v: 0 if v < 14 else 255)
	outline = outline.filter(ImageFilter.GaussianBlur(1.6))
	shadow = ImageChops.offset(outline, 0, 12).filter(ImageFilter.GaussianBlur(5)).point(lambda v: int(v * 0.35))
	out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
	out.alpha_composite(Image.merge("RGBA", [Image.new("L", out.size, 0)] * 3 + [shadow]))
	navy = tuple(int(c * 255) for c in NAVY)
	out.alpha_composite(Image.merge("RGBA", [Image.new("L", out.size, c) for c in navy] + [outline]))
	bbox = mask.getbbox() or (0, 0, canvas, canvas)
	grad = Image.new("RGBA", (canvas, canvas))
	gp = grad.load()
	for y in range(canvas):
		t = min(1.0, max(0.0, (y - bbox[1]) / max(1, bbox[3] - bbox[1])))
		col = tuple(int(fill_top[i] * (1 - t) + fill_bottom[i] * t) for i in range(3)) + (255,)
		for x in range(canvas):
			gp[x, y] = col
	grad.putalpha(mask)
	out.alpha_composite(grad)
	# glossy top highlight
	shine = mask.copy()
	shine = ImageChops.multiply(shine, Image.linear_gradient("L").resize((canvas, canvas)).point(lambda v: 255 - v))
	hi = Image.merge("RGBA", [Image.new("L", out.size, 255)] * 3 + [shine.point(lambda v: v // 5)])
	out.alpha_composite(hi)
	return out


GLYPHS = {
	# name: (source relative to src, top colour, bottom colour)
	"pause": ("gicons/PNG/White/2x/pause.png", (255, 255, 255), (222, 232, 250)),
	"speed": ("gicons/PNG/White/2x/fastForward.png", (255, 255, 255), (222, 232, 250)),
	"sound_on": ("gicons/PNG/White/2x/audioOn.png", (255, 255, 255), (222, 232, 250)),
	"sound_off": ("gicons/PNG/White/2x/audioOff.png", (255, 255, 255), (222, 232, 250)),
	"gear": ("gicons/PNG/White/2x/gear.png", (255, 255, 255), (222, 232, 250)),
	"cancel": ("gicons/PNG/White/2x/cross.png", (255, 140, 150), (225, 50, 80)),
	"play": ("uipack/PNG/Extra/Double/icon_play_light.png", (170, 255, 170), (60, 190, 90)),
	"restart": ("uipack/PNG/Extra/Double/icon_repeat_light.png", (170, 255, 170), (60, 190, 90)),
}


def main() -> None:
	src = sys.argv[1]
	rects: dict = {}
	pieces: list = []
	for color in COLORS:
		for state, img in button_set(src, color).items():
			pieces.append((f"btn_{color.lower()}_{state}", img))
	for state, img in round_button(src).items():
		pieces.append((f"round_yellow_{state}", img))
	for name, img in make_panels(src).items():
		pieces.append((name, img))
	width = 2 * BTN_W + 4
	x = y = row_h = 0
	placed = []
	for name, img in sorted(pieces, key=lambda p: -p[1].height):
		if x + img.width > width:
			x, y, row_h = 0, y + row_h + 2, 0
		placed.append((name, img, x, y))
		rects[name] = [x, y, img.width, img.height]
		x += img.width + 2
		row_h = max(row_h, img.height)
	atlas = Image.new("RGBA", (width, y + row_h), (0, 0, 0, 0))
	for _, img, px, py in placed:
		atlas.alpha_composite(img, (px, py))
	atlas.save(os.path.join(ROOT, "ui", "theme_atlas.png"), optimize=True)
	for name, (path, top, bottom) in GLYPHS.items():
		img = glyph(os.path.join(src, path), top, bottom)
		if name == "sound_off":
			cross = glyph(
				os.path.join(src, GLYPHS["cancel"][0]),
				GLYPHS["cancel"][1],
				GLYPHS["cancel"][2],
				scale=0.34,
				shift=(58, 40),
			)
			img.alpha_composite(cross)
		img.save(os.path.join(ROOT, "ui", "icons", name + ".png"), optimize=True)
	print(json.dumps({"size": atlas.size, "rects": rects}, indent=1))


if __name__ == "__main__":
	main()
