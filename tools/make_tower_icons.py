#!/usr/bin/env python3
"""Draws the four tower icons (ui/icons/tower_*.png, 256x256, transparent).

Every icon is a coloured rounded badge with one big emblem that tells the tower
apart at a glance, even at 96 px: archer = bow and arrow (green), cannon = barrel
with a ball and a muzzle flash (orange), frost = snowflake crystal (blue),
lightning = bolt (yellow on purple). Same soft dark outline and drop shadow as the
icons rendered from the 3D models (tools/render_icons.gd). Colours come from the
project PALETTE only (assets/blender/tg_common.py); drawing is deterministic.

    python3 tools/make_tower_icons.py [out_dir]
"""
import math
import re
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
S = 1024  # supersampled canvas
OUT = 256


def palette() -> dict[str, tuple[int, int, int]]:
    text = (ROOT / "assets/blender/tg_common.py").read_text()
    return {m.group(1): tuple(int(m.group(2)[i:i + 2], 16) for i in (0, 2, 4))
            for m in re.finditer(r'^\s+"(\w+)": \("([0-9A-F]{6})"', text, re.M)}


P = palette()
NAVY = (23, 18, 41)  # same dark outline as render_icons.gd


def lighten(c, k):
    return tuple(int(v + (255 - v) * k) for v in c)


def darken(c, k):
    return tuple(int(v * (1 - k)) for v in c)


def dilate(mask: Image.Image, px: int) -> Image.Image:
    size = px * 2 + 1
    return mask.filter(ImageFilter.MaxFilter(size if size % 2 else size + 1))


def outlined(layer: Image.Image, px: int) -> Image.Image:
    """layer plus a dark outline `px` px wide around its silhouette."""
    alpha = layer.getchannel("A")
    # MaxFilter is square; blur-and-threshold rounds the corners.
    grown = dilate(alpha, px).filter(ImageFilter.GaussianBlur(px * 0.35)).point(lambda v: 255 if v > 110 else 0)
    base = Image.new("RGBA", layer.size, NAVY + (0,))
    base.putalpha(grown)
    return Image.alpha_composite(base, layer)


def rot(points, cx, cy, deg):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in points]


def rrect(cx, cy, w, h, deg):
    pts = [(cx - w / 2, cy - h / 2), (cx + w / 2, cy - h / 2), (cx + w / 2, cy + h / 2), (cx - w / 2, cy + h / 2)]
    return rot(pts, cx, cy, deg)


def line_round(d: ImageDraw.ImageDraw, a, b, width, fill):
    d.line([a, b], fill=fill, width=width)
    r = width / 2
    for x, y in (a, b):
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def badge(top, bottom) -> Image.Image:
    """Rounded square with a vertical gradient, a gloss, a dark outline and a shadow."""
    m = 64
    box = [m, m - 10, S - m, S - m - 14]
    shape = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shape).rounded_rectangle(box, radius=210, fill=255)
    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    for y in range(S):
        t = min(max((y - box[1]) / (box[3] - box[1]), 0), 1)
        gd.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    grad.putalpha(shape)
    # gloss on the top half
    gloss = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gloss).rounded_rectangle([m + 44, m + 26, S - m - 44, 400], radius=150, fill=70)
    white = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    white.putalpha(ImageChops.multiply(gloss, shape))
    grad = Image.alpha_composite(grad, white)
    # inner rim
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle(box, radius=210, outline=darken(bottom, 0.25) + (255,), width=18)
    rim.putalpha(ImageChops.multiply(rim.getchannel("A"), shape))
    grad = Image.alpha_composite(grad, rim)
    out = outlined(grad, 26)
    shadow = Image.new("RGBA", (S, S), (0, 0, 14, 0))
    shadow.putalpha(out.getchannel("A").filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * 0.4)))
    shadow = ImageChops.offset(shadow, 0, 26)
    return Image.alpha_composite(shadow, out)


def emblem(draw_fn, outline_px=20) -> Image.Image:
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer), layer)
    return outlined(layer, outline_px)


# ------------------------------------------------------------------ emblems


def archer(d, layer):
    wood, light = P["wood_light"], lighten(P["wood_light"], 0.25)
    # bow: thick arc on the left, string on the right of it
    box = [150, 190, 690, 830]
    d.arc(box, 285, 75, fill=wood, width=110)
    d.arc([box[0] + 20, box[1] + 20, box[2] - 20, box[3] - 20], 288, 72, fill=light, width=30)
    ax, ay = box[0] + (box[2] - box[0]) / 2 + (box[2] - box[0]) / 2 * math.cos(math.radians(75)), 0
    top = (410 + 270 * math.cos(math.radians(285)), 510 + 320 * math.sin(math.radians(285)))
    bot = (410 + 270 * math.cos(math.radians(75)), 510 + 320 * math.sin(math.radians(75)))
    # arrow drawn back to the string
    tail, tip = (300, 520), (880, 470)
    line_round(d, top, (330, 510), 22, P["string"])
    line_round(d, bot, (330, 510), 22, P["string"])
    line_round(d, tail, tip, 54, P["wood_light"])
    line_round(d, (330, 515), (800, 477), 16, lighten(P["wood_light"], 0.5))
    # steel head
    d.polygon([(740, 360), (985, 465), (750, 580)], fill=P["steel"])
    d.polygon([(740, 360), (985, 465), (860, 468)], fill=lighten(P["steel"], 0.3))
    # red fletching
    for sgn in (-1, 1):
        d.polygon([(250, 524), (420, 508), (330, 524 + sgn * 130)], fill=P["berry"])


def cannon(d, layer):
    iron, dark = P["iron"], P["iron_dark"]
    cx, cy, ang = 480, 470, -32
    # wheel and carriage first (behind)
    d.ellipse([310, 560, 650, 900], fill=P["wood"])
    d.ellipse([360, 610, 600, 850], fill=P["wood_dark"])
    d.ellipse([430, 680, 530, 780], fill=P["gold"])
    for k in range(8):
        a = math.radians(k * 45)
        line_round(d, (480 + 110 * math.cos(a) * 0.3, 730 + 110 * math.sin(a) * 0.3),
                   (480 + 120 * math.cos(a), 730 + 120 * math.sin(a)), 26, P["wood_light"])
    # barrel: tapered, with bands
    body = rot([(150, 400), (700, 340), (700, 600), (150, 540)], cx, cy, ang)
    d.polygon(body, fill=iron)
    hi = rot([(160, 415), (690, 362), (690, 410), (160, 460)], cx, cy, ang)
    d.polygon(hi, fill=lighten(iron, 0.35))
    for x in (260, 560):
        band = rot([(x, 350), (x + 55, 345), (x + 55, 598), (x, 595)], cx, cy, ang)
        d.polygon(band, fill=dark)
    muzzle = rot([(660, 315), (790, 305), (790, 635), (660, 625)], cx, cy, ang)
    d.polygon(muzzle, fill=dark)
    d.polygon(rot([(670, 325), (700, 322), (700, 618), (670, 615)], cx, cy, ang), fill=lighten(dark, 0.3))
    # cannonball rolling out
    d.ellipse([690, 640, 900, 850], fill=dark)
    d.ellipse([725, 670, 790, 735], fill=lighten(iron, 0.4))
    # muzzle flash
    fx, fy = 860, 190
    star = []
    for k in range(16):
        r = 150 if k % 2 == 0 else 62
        a = math.radians(k * 22.5 - 20)
        star.append((fx + r * math.cos(a), fy + r * math.sin(a)))
    d.polygon(star, fill=P["berry"])
    star2 = [(fx + (p[0] - fx) * 0.62, fy + (p[1] - fy) * 0.62) for p in star]
    d.polygon(star2, fill=P["slime_fast"])
    star3 = [(fx + (p[0] - fx) * 0.3, fy + (p[1] - fy) * 0.3) for p in star]
    d.polygon(star3, fill=P["flower_yellow"])


def frost(d, layer):
    cx, cy = 512, 500
    ice, light = P["ice_light"], P["white"]
    for k in range(6):
        a = k * 60 - 90
        far = rot([(cx, cy - 340)], cx, cy, a + 90)[0]
        line_round(d, (cx, cy), rot([(cx, cy - 345)], cx, cy, k * 60)[0], 70, ice)
        # side branches
        for frac, length in ((0.45, 150), (0.72, 110)):
            base = rot([(cx, cy - 345 * frac)], cx, cy, k * 60)[0]
            for sgn in (-1, 1):
                end = rot([(base[0] + sgn * length * 0.6, base[1] - length * 0.55)], base[0], base[1], 0)
                tip = rot([(cx, cy - 345 * frac)], cx, cy, k * 60)[0]
                tipend = rot([(cx + sgn * length * 0.8, cy - 345 * frac - length * 0.55)], cx, cy, k * 60)[0]
                line_round(d, tip, tipend, 52, ice)
        # diamond tip
        t = rot([(cx, cy - 345)], cx, cy, k * 60)[0]
        d.polygon(rot([(cx, cy - 395), (cx + 52, cy - 340), (cx, cy - 290), (cx - 52, cy - 340)], cx, cy, k * 60), fill=P["ice"])
    d.regular_polygon((cx, cy, 120), 6, rotation=0, fill=P["ice"])
    d.regular_polygon((cx, cy, 70), 6, rotation=0, fill=light)


def lightning(d, layer):
    gold, yellow = P["flower_yellow"], P["star"]
    bolt = [(600, 130), (260, 570), (470, 570), (370, 910), (780, 410), (545, 410), (690, 130)]
    d.polygon(bolt, fill=yellow)
    d.polygon([(600, 130), (260, 570), (400, 570), (630, 250)], fill=lighten(gold, 0.55))
    d.polygon([(545, 410), (780, 410), (660, 570), (470, 570)], fill=P["gold"])
    # small sparks
    for (x, y, r) in ((200, 300, 52), (860, 720, 60), (160, 780, 38)):
        d.polygon([(x, y - r), (x + r * 0.3, y - r * 0.3), (x + r, y), (x + r * 0.3, y + r * 0.3),
                   (x, y + r), (x - r * 0.3, y + r * 0.3), (x - r, y), (x - r * 0.3, y - r * 0.3)],
                  fill=P["white"])


ICONS = {
    "archer": (lighten(P["leaf"], 0.12), P["leaf_dark"], archer),
    "cannon": (lighten(P["slime_fast"], 0.1), P["slime_fast_dark"], cannon),
    "frost": (P["ice"], P["ice_dark"], frost),
    "lightning": (P["portal_glow"], P["portal"], lightning),
}


def build(name: str) -> Image.Image:
    top, bottom, fn = ICONS[name]
    img = badge(top, bottom)
    img = Image.alpha_composite(img, emblem(fn))
    return img.resize((OUT, OUT), Image.LANCZOS)


def main() -> None:
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "ui/icons"
    out_dir.mkdir(parents=True, exist_ok=True)
    for name in ICONS:
        build(name).save(out_dir / f"tower_{name}.png")
        print("wrote", out_dir / f"tower_{name}.png")


if __name__ == "__main__":
    main()
