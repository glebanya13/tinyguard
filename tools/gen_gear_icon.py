#!/usr/bin/env python3
"""Draws ui/icons/gear.png (settings button): a cream gear with a dark outline.

Deterministic, no external assets. Run from the repo root: python3 tools/gen_gear_icon.py
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 256
SCALE = 4  # supersampling for smooth edges
CREAM = (250, 236, 200, 255)
OUTLINE = (58, 62, 84, 255)
TEETH = 8


def gear_polygon(cx: float, cy: float, r_out: float, r_in: float) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    step = 2 * math.pi / TEETH
    for i in range(TEETH):
        a = i * step
        for da, r in ((-0.30, r_in), (-0.17, r_out), (0.17, r_out), (0.30, r_in)):
            ang = a + da * step * 1.6
            points.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    return points


def main() -> None:
    big = SIZE * SCALE
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    c = big / 2
    outer = gear_polygon(c, c, big * 0.46, big * 0.35)
    draw.polygon(outer, fill=OUTLINE)
    inner = gear_polygon(c, c, big * 0.41, big * 0.31)
    draw.polygon(inner, fill=CREAM)
    hole = big * 0.13
    draw.ellipse((c - hole * 1.25, c - hole * 1.25, c + hole * 1.25, c + hole * 1.25), fill=OUTLINE)
    draw.ellipse((c - hole, c - hole, c + hole, c + hole), fill=(0, 0, 0, 0))
    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    path = Path(__file__).resolve().parent.parent / "ui" / "icons" / "gear.png"
    out.save(path)
    print("wrote", path)


if __name__ == "__main__":
    main()
