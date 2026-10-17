#!/usr/bin/env python3
"""Draws ui/icons/gem.png (the gem currency, "Самоцветы"): a faceted cyan crystal with the
same dark outline as the other UI icons (see gen_gear_icon.py).

Deterministic, no external assets. Run from the repo root: python3 tools/gen_gem_icon.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 256
SCALE = 4  # supersampling for smooth edges
OUTLINE = (58, 62, 84, 255)
LIGHT = (200, 247, 255, 255)
MID = (94, 211, 243, 255)
MID_DARK = (52, 164, 224, 255)
DARK = (34, 112, 184, 255)
SHINE = (255, 255, 255, 235)

# Unit coordinates of a brilliant-cut gem seen from the side.
TOP_L, TOP_R = (0.27, 0.20), (0.73, 0.20)
LEFT, RIGHT, TIP = (0.06, 0.43), (0.94, 0.43), (0.5, 0.93)
TABLE_L, TABLE_R = (0.38, 0.43), (0.62, 0.43)
MID_TOP = (0.5, 0.20)

FACETS = [
    ([TOP_L, MID_TOP, TABLE_L], LIGHT),
    ([MID_TOP, TOP_R, TABLE_R], MID),
    ([TOP_L, TABLE_L, LEFT], MID),
    ([TOP_R, RIGHT, TABLE_R], MID_DARK),
    ([MID_TOP, TABLE_R, TABLE_L], LIGHT),
    ([LEFT, TABLE_L, TIP], MID_DARK),
    ([TABLE_L, TABLE_R, TIP], MID),
    ([TABLE_R, RIGHT, TIP], DARK),
]


def scale(points: list[tuple[float, float]], big: int) -> list[tuple[float, float]]:
    return [(x * big, y * big) for x, y in points]


def main() -> None:
    big = SIZE * SCALE
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    outline = [TOP_L, TOP_R, RIGHT, TIP, LEFT]
    draw.polygon(scale(outline, big), fill=OUTLINE)
    width = big * 0.045
    # Facets, each pulled slightly in so the outline shows between them.
    for points, colour in FACETS:
        draw.polygon(scale(points, big), fill=colour)
    draw.line(scale(outline + [outline[0]], big), fill=OUTLINE, width=int(width), joint="curve")
    for a, b in ((TOP_L, TABLE_L), (TOP_R, TABLE_R), (TABLE_L, TIP), (TABLE_R, TIP), (LEFT, RIGHT)):
        draw.line(scale([a, b], big), fill=OUTLINE, width=int(width * 0.5))
    draw.ellipse(
        (big * 0.31, big * 0.255, big * 0.37, big * 0.31), fill=SHINE
    )  # a small shine on the crown
    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    path = Path(__file__).resolve().parent.parent / "ui" / "icons" / "gem.png"
    out.save(path)
    print("wrote", path)


if __name__ == "__main__":
    main()
