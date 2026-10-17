#!/usr/bin/env python3
"""Draws the UI atlas ui/theme_atlas.png and writes ui/theme.tres (deterministic, Pillow only,
no external art). Palette from assets/brand/logo.png: blue helmet, gold, green, navy outline.

  python3 -I tools/make_ui_atlas.py

Design system (all units are canvas pixels at 1280x720, grid 8 px):
  outline 3-4 px navy; radii small 8 / medium 16 / large 24; buttons have a 8 px "step" under
  the body (4 px when pressed: the body sinks 4 px); one atlas, 9-slice StyleBoxTexture.
Glyph icons (ui/icons/*.png) are NOT touched here, see tools/build_ui_atlas.py.
"""

import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SS = 4  # supersampling

NAVY = (18, 28, 69)
NAVY_SOFT = (30, 44, 107)
WHITE = (255, 255, 255)

# colour sets: (top, bottom, step/dark, frame light)
GOLD = ((255, 222, 84), (247, 163, 26), (178, 100, 12))
BLUE = ((96, 160, 255), (43, 95, 199), (26, 58, 140))
GREEN = ((120, 228, 112), (47, 166, 74), (26, 106, 49))
RED = ((255, 124, 112), (218, 58, 62), (140, 30, 42))
GREY = ((156, 166, 186), (112, 122, 146), (72, 80, 104))
WOOD = ((214, 156, 90), (160, 104, 52), (100, 62, 28))


def lerp(a, b, t):
	return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(len(a)))


def rr_mask(size, box, radius, ss=SS):
	"""Anti-aliased rounded-rect mask; box in final pixels (x0, y0, x1, y1), exclusive end."""
	w, h = size
	m = Image.new("L", (w * ss, h * ss), 0)
	d = ImageDraw.Draw(m)
	x0, y0, x1, y1 = box
	d.rounded_rectangle(
		(x0 * ss, y0 * ss, x1 * ss - 1, y1 * ss - 1), radius=radius * ss, fill=255
	)
	return m.resize((w, h), Image.LANCZOS)


def grad(size, top, bottom, y0=None, y1=None):
	"""Vertical gradient image (RGBA) between y0..y1 (defaults to full height)."""
	w, h = size
	y0 = 0 if y0 is None else y0
	y1 = h if y1 is None else y1
	img = Image.new("RGBA", size)
	px = img.load()
	for y in range(h):
		t = 0.0 if y1 <= y0 else min(1.0, max(0.0, (y - y0) / float(y1 - y0)))
		c = lerp(top, bottom, t) + (255,)
		for x in range(w):
			px[x, y] = c
	return img


def fill(canvas, mask, top, bottom=None, y0=None, y1=None):
	bottom = top if bottom is None else bottom
	layer = grad(canvas.size, top, bottom, y0, y1)
	layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
	canvas.alpha_composite(layer)


def white_alpha(canvas, mask, alpha, y0=None, y1=None, fade=True):
	"""Soft white sheen inside mask: strongest at y0, fading to 0 at y1."""
	w, h = canvas.size
	y0 = 0 if y0 is None else y0
	y1 = h if y1 is None else y1
	layer = Image.new("RGBA", canvas.size, WHITE + (0,))
	px = layer.load()
	for y in range(h):
		t = min(1.0, max(0.0, (y - y0) / float(max(1, y1 - y0))))
		a = alpha * (1 - t) if fade else alpha
		for x in range(w):
			px[x, y] = WHITE + (int(a),)
	layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
	canvas.alpha_composite(layer)


def black_alpha(canvas, mask, alpha):
	layer = Image.new("RGBA", canvas.size, (0, 0, 20, int(alpha)))
	layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
	canvas.alpha_composite(layer)


def inset(box, d):
	return (box[0] + d, box[1] + d, box[2] - d, box[3] - d)


def shade(color, f):
	return tuple(max(0, min(255, int(c * f))) for c in color)


def button(size, scheme, state, radius=16):
	"""Chunky button: navy outline, gradient body, top sheen, darker step below."""
	w, h = size
	top, bottom, step_col = scheme
	step = 8 if state != "down" else 4
	off = 0 if state != "down" else 4
	body_h = h - 8 - 0
	img = Image.new("RGBA", size, (0, 0, 0, 0))
	body = (0, off, w, off + body_h)
	step_box = (0, off + step, w, off + step + body_h)
	# step: navy outline, then dark colour
	fill(img, rr_mask(size, step_box, radius), NAVY)
	fill(img, rr_mask(size, inset(step_box, 3), radius - 3), shade(step_col, 1.0), shade(step_col, 0.85))
	# body
	fill(img, rr_mask(size, body, radius), NAVY)
	inner = inset(body, 3)
	if state == "hover":
		top, bottom = shade(top, 1.1), shade(bottom, 1.08)
	fill(img, rr_mask(size, inner, radius - 3), top, bottom, inner[1], inner[3])
	# bottom inner shade
	low = (inner[0], inner[3] - 10, inner[2], inner[3])
	black_alpha(img, ImageChops.multiply(rr_mask(size, inner, radius - 3), rr_mask(size, (0, inner[3] - 9, w, h), 0)), 38)
	# top sheen (soft glossy band) and a crisp specular line
	sheen = (inner[0] + 4, inner[1] + 3, inner[2] - 4, inner[1] + (body_h - 6) // 2)
	white_alpha(img, rr_mask(size, sheen, radius - 6), 110, sheen[1], sheen[3])
	line = (inner[0] + 8, inner[1] + 2, inner[2] - 8, inner[1] + 4)
	white_alpha(img, rr_mask(size, line, 1), 170, fade=False)
	if state == "disabled":
		pass
	return img


def panel(size, frame, inner_top, inner_bottom, radius=24, outline=4, frame_w=4, lip=6):
	"""Modal panel: navy outline, coloured frame, gradient interior, top sheen, inner shadow, lip."""
	w, h = size
	img = Image.new("RGBA", size, (0, 0, 0, 0))
	body_h = h - lip
	if lip:
		lip_box = (0, lip, w, h)
		fill(img, rr_mask(size, lip_box, radius), NAVY)
		fill(img, rr_mask(size, inset(lip_box, outline), radius - outline), shade(frame[2], 0.9))
	body = (0, 0, w, body_h)
	fill(img, rr_mask(size, body, radius), NAVY)
	f_box = inset(body, outline)
	fill(img, rr_mask(size, f_box, radius - outline), frame[0], frame[1], f_box[1], f_box[3])
	i_box = inset(f_box, frame_w)
	i_mask = rr_mask(size, i_box, max(4, radius - outline - frame_w))
	fill(img, i_mask, inner_top, inner_bottom, i_box[1], i_box[3])
	# inner shadow just under the frame (top and sides)
	sh = Image.new("L", size, 0)
	sh.paste(255, (0, 0, w, h))
	hole = rr_mask(size, (i_box[0] + 3, i_box[1] + 8, i_box[2] - 3, i_box[3] + 40), 12)
	sh = ImageChops.subtract(sh, hole).filter(ImageFilter.GaussianBlur(5))
	black_alpha(img, ImageChops.multiply(i_mask, sh), 70)
	# top sheen line
	line = (i_box[0] + 6, i_box[1] + 2, i_box[2] - 6, i_box[1] + 4)
	white_alpha(img, rr_mask(size, line, 1), 70, fade=False)
	# frame highlight
	fl = (f_box[0] + 6, f_box[1] + 2, f_box[2] - 6, f_box[1] + 4)
	white_alpha(img, rr_mask(size, fl, 1), 140, fade=False)
	return img


def slot_card(size, selected=False, disabled=False, radius=16, step=6):
	"""Cream item card (tower slot) with a gold frame and a step under it."""
	w, h = size
	img = Image.new("RGBA", size, (0, 0, 0, 0))
	body_h = h - step
	frame = GOLD if not selected else ((255, 244, 140), (255, 205, 40), (200, 130, 20))
	if disabled:
		frame = GREY
	step_box = (0, step, w, h)
	fill(img, rr_mask(size, step_box, radius), NAVY)
	fill(img, rr_mask(size, inset(step_box, 3), radius - 3), shade(frame[2], 1.0))
	body = (0, 0, w, body_h)
	fill(img, rr_mask(size, body, radius), NAVY)
	f_box = inset(body, 3)
	fill(img, rr_mask(size, f_box, radius - 3), frame[0], frame[1], f_box[1], f_box[3])
	i_box = inset(f_box, 3)
	i_mask = rr_mask(size, i_box, radius - 6)
	if disabled:
		fill(img, i_mask, (206, 210, 222), (176, 182, 200), i_box[1], i_box[3])
	else:
		fill(img, i_mask, (255, 247, 224), (246, 224, 170), i_box[1], i_box[3])
	sh = Image.new("L", size, 0)
	sh.paste(255, (0, 0, w, h))
	hole = rr_mask(size, (i_box[0] + 2, i_box[1] + 5, i_box[2] - 2, i_box[3] + 30), 10)
	sh = ImageChops.subtract(sh, hole).filter(ImageFilter.GaussianBlur(3))
	black_alpha(img, ImageChops.multiply(i_mask, sh), 55)
	line = (i_box[0] + 6, i_box[1] + 1, i_box[2] - 6, i_box[1] + 3)
	white_alpha(img, rr_mask(size, line, 1), 200, fade=False)
	return img


def ribbon(size, scheme):
	"""Title plaque: band with folded swallow-tail ends (9-slice, margins 56)."""
	w, h = size
	top, bottom, dark = scheme
	img = Image.new("RGBA", size, (0, 0, 0, 0))
	band_h = h - 12
	tail_y0, tail_y1 = 12, h
	for side in (0, 1):
		x0, x1 = (0, 60) if side == 0 else (w - 60, w)
		tail = Image.new("L", (size[0] * SS, size[1] * SS), 0)
		d = ImageDraw.Draw(tail)
		if side == 0:
			pts = [(x0, tail_y0), (x1, tail_y0), (x1, tail_y1), (x0, tail_y1), (x0 + 16, (tail_y0 + tail_y1) / 2)]
		else:
			pts = [(x1, tail_y0), (x0, tail_y0), (x0, tail_y1), (x1, tail_y1), (x1 - 16, (tail_y0 + tail_y1) / 2)]
		d.polygon([(px * SS, py * SS) for px, py in pts], fill=255)
		tail = tail.resize(size, Image.LANCZOS)
		grown = tail.filter(ImageFilter.MaxFilter(7))
		fill(img, grown, NAVY)
		fill(img, tail, shade(dark, 1.05), shade(dark, 0.8), tail_y0, tail_y1)
	band = (24, 0, w - 24, band_h)
	fill(img, rr_mask(size, band, 12), NAVY)
	inner = inset(band, 3)
	fill(img, rr_mask(size, inner, 9), top, bottom, inner[1], inner[3])
	sheen = (inner[0] + 4, inner[1] + 3, inner[2] - 4, inner[1] + band_h // 2 - 4)
	white_alpha(img, rr_mask(size, sheen, 6), 100, sheen[1], sheen[3])
	line = (inner[0] + 8, inner[1] + 2, inner[2] - 8, inner[1] + 4)
	white_alpha(img, rr_mask(size, line, 1), 170, fade=False)
	black_alpha(img, ImageChops.multiply(rr_mask(size, inner, 9), rr_mask(size, (0, band_h - 12, w, h), 0)), 30)
	return img


def chip(size, ring):
	"""HUD chip: dark pill with a round badge on the left (ring colour = resource)."""
	w, h = size
	img = Image.new("RGBA", size, (0, 0, 0, 0))
	r = h // 2
	pill = (0, 0, w, h)
	fill(img, rr_mask(size, pill, r), NAVY)
	i1 = inset(pill, 3)
	fill(img, rr_mask(size, i1, r - 3), (46, 66, 148), (24, 36, 92), i1[1], i1[3])
	sh = (i1[0] + r, i1[1] + 2, i1[2] - 8, i1[1] + 5)
	white_alpha(img, rr_mask(size, sh, 2), 60, fade=False)
	# badge
	badge = (0, 0, h, h)
	fill(img, rr_mask(size, badge, r), NAVY)
	b1 = inset(badge, 3)
	fill(img, rr_mask(size, b1, r - 3), ring[0], ring[1], b1[1], b1[3])
	b2 = inset(badge, 8)
	fill(img, rr_mask(size, b2, r - 8), (22, 32, 82), (40, 56, 128), b2[1], b2[3])
	white_alpha(img, rr_mask(size, (b1[0] + 6, b1[1] + 1, b1[2] - 6, b1[1] + 3), 1), 150, fade=False)
	return img


def pill(size, ring=None):
	"""Small price pill / count capsule, dark navy with a thin light rim."""
	w, h = size
	img = Image.new("RGBA", size, (0, 0, 0, 0))
	r = h // 2
	box = (0, 0, w, h)
	fill(img, rr_mask(size, box, r), NAVY)
	i1 = inset(box, 2)
	fill(img, rr_mask(size, i1, r - 2), (44, 62, 140), (28, 40, 100), i1[1], i1[3])
	white_alpha(img, rr_mask(size, (i1[0] + r // 2, i1[1] + 1, i1[2] - r // 2, i1[1] + 3), 1), 70, fade=False)
	return img


def bar(size, kind):
	w, h = size
	img = Image.new("RGBA", size, (0, 0, 0, 0))
	r = h // 2
	box = (0, 0, w, h)
	fill(img, rr_mask(size, box, r), NAVY)
	i1 = inset(box, 3)
	if kind == "bg":
		fill(img, rr_mask(size, i1, r - 3), (14, 22, 58), (28, 40, 96), i1[1], i1[3])
		black_alpha(img, ImageChops.multiply(rr_mask(size, i1, r - 3), rr_mask(size, (0, 0, w, h // 2), 0)), 50)
	else:
		fill(img, rr_mask(size, i1, r - 3), GREEN[0], GREEN[1], i1[1], i1[3])
		white_alpha(img, rr_mask(size, (i1[0] + 4, i1[1] + 2, i1[2] - 4, i1[1] + 6), 2), 150, fade=False)
	return img


def round_button(size, scheme, state):
	"""Round (circular) action button with a step; 128x128 source drawn at 1:1."""
	w, h = size
	top, bottom, step_col = scheme
	step = 10 if state != "down" else 5
	off = 0 if state != "down" else 5
	d = h - 10
	img = Image.new("RGBA", size, (0, 0, 0, 0))
	sbox = (0, off + step, w, off + step + d)
	fill(img, rr_mask(size, sbox, d // 2), NAVY)
	fill(img, rr_mask(size, inset(sbox, 4), d // 2 - 4), step_col, shade(step_col, 0.85))
	box = (0, off, w, off + d)
	fill(img, rr_mask(size, box, d // 2), NAVY)
	i = inset(box, 4)
	if state == "hover":
		top, bottom = shade(top, 1.1), shade(bottom, 1.08)
	fill(img, rr_mask(size, i, d // 2 - 4), top, bottom, i[1], i[3])
	sheen = (i[0] + 12, i[1] + 6, i[2] - 12, i[1] + d // 2 - 8)
	white_alpha(img, rr_mask(size, sheen, 30), 120, sheen[1], sheen[3])
	white_alpha(img, rr_mask(size, (i[0] + 28, i[1] + 3, i[2] - 28, i[1] + 6), 1), 160, fade=False)
	return img


# name -> (image builder, nine-slice margins (l, t, r, b) or None, content margins)
def build():
	items = []  # (name, image)
	# round buttons must stay at (0,0),(130,0),(260,0): the HUD scene uses these regions
	for state in ("up", "hover", "down"):
		items.append(("round_gold_" + state, round_button((128, 128), GOLD, state)))
	schemes = {"gold": GOLD, "blue": BLUE, "green": GREEN, "red": RED, "grey": GREY}
	for cname, sc in schemes.items():
		for state in ("up", "hover", "down"):
			if cname == "grey" and state != "up":
				continue
			items.append((f"btn_{cname}_{state}", button((96, 72), sc, state)))
	items.append(("panel", panel((96, 96), BLUE, (44, 62, 140), (26, 38, 100))))
	items.append(("panel_gold", panel((96, 96), GOLD, (44, 62, 140), (26, 38, 100))))
	items.append(("card", panel((64, 64), ((84, 128, 224), (52, 88, 184), (30, 54, 130)), (48, 68, 150), (36, 52, 122), radius=16, outline=3, frame_w=3, lip=0)))
	items.append(("card_select", panel((64, 64), ((255, 226, 100), (240, 170, 30), (170, 100, 10)), (56, 78, 170), (42, 60, 138), radius=16, outline=3, frame_w=3, lip=0)))
	items.append(("inset", panel((48, 48), ((20, 30, 78), (20, 30, 78), (10, 16, 48)), (14, 22, 62), (22, 32, 84), radius=12, outline=2, frame_w=2, lip=0)))
	items.append(("slot", slot_card((96, 112))))
	items.append(("slot_select", slot_card((96, 112), selected=True)))
	items.append(("slot_off", slot_card((96, 112), disabled=True)))
	for cname, sc in (("blue", BLUE), ("green", GREEN), ("red", RED), ("gold", GOLD)):
		items.append(("ribbon_" + cname, ribbon((192, 76), sc)))
	for cname, sc in (("gold", GOLD), ("wood", WOOD), ("red", RED), ("blue", BLUE)):
		items.append(("chip_" + cname, chip((160, 48), sc)))
	items.append(("pill", pill((64, 32))))
	items.append(("bar_bg", bar((96, 28), "bg")))
	items.append(("bar_fill", bar((96, 28), "fill")))
	items.append(("toast", panel((128, 80), GOLD, (44, 62, 140), (26, 38, 100), radius=20, outline=3, frame_w=3, lip=4)))
	return items


def pack(items, width=408):
	"""Shelf packer; keeps the first three items at x = 0, 130, 260 on row 0."""
	rects = {}
	x = y = row_h = 0
	placed = []
	rest = sorted(items[3:], key=lambda p: (-p[1].height, p[0]))
	order = items[:3] + rest
	for name, img in order:
		if x + img.width > width and x > 0:
			x, y, row_h = 0, y + row_h + 2, 0
		placed.append((name, img, x, y))
		rects[name] = (x, y, img.width, img.height)
		x += img.width + 2
		row_h = max(row_h, img.height)
	atlas = Image.new("RGBA", (width, y + row_h), (0, 0, 0, 0))
	for _, img, px, py in placed:
		atlas.alpha_composite(img, (px, py))
	return atlas, rects


# --- theme.tres ------------------------------------------------------------

RIBBON_SHIFT = 0
BTN_M = (24, 24, 24, 32)  # nine-slice margins l, t, r, b
BTN_CM = {"up": (28, 14, 28, 24), "down": (28, 18, 28, 20)}


def sb(sid, rect, margins, content, expand=None):
	x, y, w, h = rect
	ml, mt, mr, mb = margins
	cl, ct, cr, cb = content
	return (
		f'[sub_resource type="StyleBoxTexture" id="{sid}"]\n'
		f"content_margin_left = {cl}\ncontent_margin_top = {ct}\n"
		f"content_margin_right = {cr}\ncontent_margin_bottom = {cb}\n"
		'texture = ExtResource("atlas")\n'
		f"texture_margin_left = {ml}\ntexture_margin_top = {mt}\n"
		f"texture_margin_right = {mr}\ntexture_margin_bottom = {mb}\n"
		f"region_rect = Rect2({x}, {y}, {w}, {h})\n"
		+ (
			f"expand_margin_top = {expand[0]}\nexpand_margin_bottom = {expand[1]}\n"
			if expand
			else ""
		)
	)


def theme_text(r):
	subs = []
	for c in ("gold", "blue", "green", "red"):
		for st in ("up", "hover", "down"):
			cm = BTN_CM["down" if st == "down" else "up"]
			subs.append(sb(f"{c}_{st}", r[f"btn_{c}_{st}"], BTN_M, cm))
	subs.append(sb("grey", r["btn_grey_up"], BTN_M, BTN_CM["up"]))
	subs.append(sb("panel", r["panel"], (32, 32, 32, 38), (32, 16, 32, 40)))
	subs.append(sb("panel_gold", r["panel_gold"], (32, 32, 32, 38), (32, 16, 32, 40)))
	subs.append(sb("card", r["card"], (24, 24, 24, 24), (16, 12, 16, 12)))
	subs.append(sb("card_select", r["card_select"], (24, 24, 24, 24), (16, 12, 16, 12)))
	subs.append(sb("inset", r["inset"], (16, 16, 16, 16), (16, 12, 16, 12)))
	subs.append(sb("slot", r["slot"], (28, 28, 28, 34), (6, 6, 6, 12)))
	subs.append(sb("slot_select", r["slot_select"], (28, 28, 28, 34), (6, 6, 6, 12)))
	subs.append(sb("slot_off", r["slot_off"], (28, 28, 28, 34), (6, 6, 6, 12)))
	for c in ("blue", "green", "red", "gold"):
		subs.append(
			sb(f"ribbon_{c}", r[f"ribbon_{c}"], (64, 12, 64, 12), (56, 14, 56, 24), (RIBBON_SHIFT, -RIBBON_SHIFT) if RIBBON_SHIFT else None)
		)
	for c in ("gold", "wood", "red", "blue"):
		subs.append(sb(f"chip_{c}", r[f"chip_{c}"], (54, 24, 24, 24), (11, 4, 18, 4)))
	subs.append(sb("pill", r["pill"], (16, 16, 16, 16), (12, 2, 12, 2)))
	subs.append(sb("bar_bg", r["bar_bg"], (14, 14, 14, 14), (0, 0, 0, 0)))
	subs.append(sb("bar_fill", r["bar_fill"], (14, 14, 14, 14), (0, 0, 0, 0)))
	subs.append(sb("toast", r["toast"], (28, 28, 28, 32), (24, 12, 24, 20)))
	flat = (
		'[sub_resource type="StyleBoxEmpty" id="focus"]\n'
	)
	body = "\n".join(subs)
	head = (
		'[gd_resource type="Theme" load_steps=60 format=3]\n\n'
		'[ext_resource type="Texture2D" path="res://ui/theme_atlas.png" id="atlas"]\n'
		'[ext_resource type="FontFile" path="res://assets/fonts/Nunito.ttf" id="font_body_file"]\n'
		'[ext_resource type="FontFile" path="res://assets/fonts/rubik/Rubik.ttf" id="font_display_file"]\n\n'
		'[sub_resource type="FontVariation" id="font_body"]\n'
		'base_font = ExtResource("font_body_file")\n'
		"variation_opentype = {\n2003265652: 800.0\n}\n\n"
		'[sub_resource type="FontVariation" id="font_display"]\n'
		'base_font = ExtResource("font_display_file")\n'
		"variation_opentype = {\n2003265652: 900.0\n}\n\n"
		'[sub_resource type="FontVariation" id="font_button"]\n'
		'base_font = ExtResource("font_display_file")\n'
		"variation_opentype = {\n2003265652: 800.0\n}\n\n"
	)
	cream = "Color(1, 0.97, 0.88, 1)"
	navy = "Color(0.07, 0.11, 0.27, 1)"
	dark_brown = "Color(0.24, 0.15, 0.06, 1)"

	def btn_type(name, base, c):
		lines = [f"{name}/base_type = &\"{base}\""] if name != "Button" else []
		lines += [
			f'{name}/styles/normal = SubResource("{c}_up")',
			f'{name}/styles/hover = SubResource("{c}_hover")',
			f'{name}/styles/pressed = SubResource("{c}_down")',
			f'{name}/styles/hover_pressed = SubResource("{c}_down")',
		]
		return "\n".join(lines)

	res = [
		"[resource]",
		'default_font = SubResource("font_body")',
		"default_font_size = 22",
		# Button: display font, cream text with a navy outline on every colour
		'Button/fonts/font = SubResource("font_button")',
		"Button/font_sizes/font_size = 22",
		f"Button/colors/font_color = {cream}",
		f"Button/colors/font_focus_color = {cream}",
		f"Button/colors/font_hover_color = {cream}",
		f"Button/colors/font_pressed_color = {cream}",
		f"Button/colors/font_hover_pressed_color = {cream}",
		"Button/colors/font_disabled_color = Color(0.82, 0.86, 0.94, 0.9)",
		f"Button/colors/font_outline_color = {navy}",
		"Button/constants/outline_size = 3",
		"Button/constants/h_separation = 10",
		"Button/constants/icon_max_width = 40",
		'Button/styles/disabled = SubResource("grey")',
		'Button/styles/focus = SubResource("focus")',
		btn_type("Button", "", "gold"),
		btn_type("SecondaryButton", "Button", "blue"),
		btn_type("GreenButton", "Button", "green"),
		btn_type("DangerButton", "Button", "red"),
		# slot card (tower build / upgrade card): dark text on cream
		'SlotButton/base_type = &"Button"',
		'SlotButton/styles/normal = SubResource("slot")',
		'SlotButton/styles/hover = SubResource("slot_select")',
		'SlotButton/styles/pressed = SubResource("slot_select")',
		'SlotButton/styles/hover_pressed = SubResource("slot_select")',
		'SlotButton/styles/disabled = SubResource("slot_off")',
		f"SlotButton/colors/font_color = {dark_brown}",
		f"SlotButton/colors/font_hover_color = {dark_brown}",
		f"SlotButton/colors/font_pressed_color = {dark_brown}",
		f"SlotButton/colors/font_focus_color = {dark_brown}",
		f"SlotButton/colors/font_hover_pressed_color = {dark_brown}",
		"SlotButton/colors/font_disabled_color = Color(0.36, 0.38, 0.46, 1)",
		"SlotButton/constants/outline_size = 0",
		'SlotButton/fonts/font = SubResource("font_body")',
		# labels
		f"Label/colors/font_color = {cream}",
		f"Label/colors/font_outline_color = {navy}",
		"Label/constants/outline_size = 0",
		"Label/constants/line_spacing = 4",
		'TitleLabel/base_type = &"Label"',
		'TitleLabel/fonts/font = SubResource("font_display")',
		"TitleLabel/font_sizes/font_size = 32",
		"TitleLabel/colors/font_color = Color(1, 0.88, 0.45, 1)",
		"TitleLabel/colors/font_shadow_color = Color(0.03, 0.05, 0.15, 0.55)",
		"TitleLabel/constants/shadow_offset_x = 0",
		"TitleLabel/constants/shadow_offset_y = 3",
		"TitleLabel/constants/outline_size = 6",
		'HeadingLabel/base_type = &"Label"',
		'HeadingLabel/fonts/font = SubResource("font_display")',
		"HeadingLabel/font_sizes/font_size = 22",
		"HeadingLabel/colors/font_color = Color(1, 0.88, 0.45, 1)",
		"HeadingLabel/constants/outline_size = 3",
		'NumberLabel/base_type = &"Label"',
		'NumberLabel/fonts/font = SubResource("font_display")',
		"NumberLabel/font_sizes/font_size = 22",
		"NumberLabel/constants/outline_size = 3",
		'StatsLabel/base_type = &"Label"',
		'StatsLabel/fonts/font = SubResource("font_display")',
		"StatsLabel/font_sizes/font_size = 16",
		"StatsLabel/constants/line_spacing = 8",
		'StatsLabel/styles/normal = SubResource("inset")',
		'CaptionLabel/base_type = &"Label"',
		"CaptionLabel/font_sizes/font_size = 16",
		"CaptionLabel/colors/font_color = Color(0.78, 0.84, 0.97, 1)",
		'RibbonLabel/base_type = &"Label"',
		'RibbonLabel/fonts/font = SubResource("font_display")',
		"RibbonLabel/font_sizes/font_size = 32",
		f"RibbonLabel/colors/font_color = {cream}",
		"RibbonLabel/colors/font_shadow_color = Color(0.03, 0.05, 0.15, 0.5)",
		"RibbonLabel/constants/shadow_offset_y = 3",
		"RibbonLabel/constants/outline_size = 5",
		'RibbonLabel/styles/normal = SubResource("ribbon_blue")',
		'RibbonLabelGreen/base_type = &"RibbonLabel"',
		'RibbonLabelGreen/styles/normal = SubResource("ribbon_green")',
		'RibbonLabelRed/base_type = &"RibbonLabel"',
		'RibbonLabelRed/styles/normal = SubResource("ribbon_red")',
		'RibbonLabelGold/base_type = &"RibbonLabel"',
		'RibbonLabelGold/styles/normal = SubResource("ribbon_gold")',
		# containers
		'PanelContainer/styles/panel = SubResource("panel")',
		'CardPanel/base_type = &"PanelContainer"',
		'CardPanel/styles/panel = SubResource("card")',
		'SelectedCard/base_type = &"PanelContainer"',
		'SelectedCard/styles/panel = SubResource("card_select")',
		'InsetPanel/base_type = &"PanelContainer"',
		'InsetPanel/styles/panel = SubResource("inset")',
		'GoldPanel/base_type = &"PanelContainer"',
		'GoldPanel/styles/panel = SubResource("panel_gold")',
		'ToastPanel/base_type = &"PanelContainer"',
		'ToastPanel/styles/panel = SubResource("toast")',
		'PricePill/base_type = &"PanelContainer"',
		'PricePill/styles/panel = SubResource("pill")',
		'HudChip/base_type = &"PanelContainer"',
		'HudChip/styles/panel = SubResource("chip_gold")',
		'HudChipWood/base_type = &"PanelContainer"',
		'HudChipWood/styles/panel = SubResource("chip_wood")',
		'HudChipRed/base_type = &"PanelContainer"',
		'HudChipRed/styles/panel = SubResource("chip_red")',
		'HudChipBlue/base_type = &"PanelContainer"',
		'HudChipBlue/styles/panel = SubResource("chip_blue")',
		'HudPill/base_type = &"PanelContainer"',
		'HudPill/styles/panel = SubResource("chip_gold")',
		'ProgressBar/styles/background = SubResource("bar_bg")',
		'ProgressBar/styles/fill = SubResource("bar_fill")',
		f"ProgressBar/colors/font_color = {cream}",
	]
	return head + body + "\n" + flat + "\n" + "\n".join(res) + "\n"


def main():
	atlas, rects = pack(build())
	atlas.save(os.path.join(ROOT, "ui", "theme_atlas.png"), optimize=True)
	with open(os.path.join(ROOT, "ui", "theme.tres"), "w") as f:
		f.write(theme_text(rects))
	for k, v in rects.items():
		print(k, v)
	print("atlas", atlas.size)


if __name__ == "__main__":
	main()
