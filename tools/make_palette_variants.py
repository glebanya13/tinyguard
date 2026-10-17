#!/usr/bin/env python3
"""Cosmetic skins as palette variants (deterministic).

Every model of the game samples ONE palette atlas (assets/materials/tg_palette_albedo.png,
8x8 cells of 32 px, cell order = PALETTE of assets/blender/tg_common.py). A cosmetic is the
same atlas with a few cells recoloured: the hero, a tower or the castle gets
`material_override` = the shared tg_palette.tres with this texture (one material per
skin, cached, see scripts/cosmetics.gd), so no model is rebuilt and no draw call is added.

Input : resources/shop.json   items[].palette = {"swatch name": "#RRGGBB"}
Output: assets/materials/skins/<item id>.png   (then `godot --headless --import`)

The vertex colours (baked ambient occlusion) are untouched, so shading stays the same.
Usage: python3 tools/make_palette_variants.py [--check]
  --check  only verify that every file is up to date (exit 1 otherwise)
"""
from __future__ import annotations

import ast
import json
import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "assets" / "materials" / "tg_palette_albedo.png"
OUT = ROOT / "assets" / "materials" / "skins"
SHOP = ROOT / "resources" / "shop.json"
GRID = 8
CELL = 32


def palette_names() -> list[str]:
    """Swatch names in atlas order, read from tg_common.py without importing bpy."""
    src = (ROOT / "assets" / "blender" / "tg_common.py").read_text()
    match = re.search(r"PALETTE[^=]*=\s*(\{.*?\n\})", src, re.S)
    if not match:
        raise SystemExit("PALETTE not found in tg_common.py")
    return list(ast.literal_eval(match.group(1)))


def hex_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def build(item: dict, names: list[str]) -> Image.Image:
    image = Image.open(BASE).convert("RGB")
    for swatch, colour in item["palette"].items():
        if swatch not in names:
            raise SystemExit(f"{item['id']}: unknown swatch {swatch}")
        index = names.index(swatch)
        x0, y0 = (index % GRID) * CELL, (index // GRID) * CELL
        image.paste(hex_rgb(colour), (x0, y0, x0 + CELL, y0 + CELL))
    return image


def main() -> int:
    check = "--check" in sys.argv
    names = palette_names()
    items = [i for i in json.loads(SHOP.read_text())["items"] if "palette" in i]
    OUT.mkdir(parents=True, exist_ok=True)
    stale = 0
    wanted = set()
    for item in items:
        path = OUT / f"{item['id']}.png"
        wanted.add(path.name)
        image = build(item, names)
        if check:
            if not path.exists() or Image.open(path).convert("RGB").tobytes() != image.tobytes():
                print(f"stale: {path.relative_to(ROOT)}")
                stale += 1
        else:
            image.save(path, optimize=False)
    for path in OUT.glob("*.png"):
        if path.name not in wanted:
            print(f"unused skin texture: {path.relative_to(ROOT)}")
            stale += 1 if check else 0
    if not check:
        print(f"{len(items)} skin textures written to {OUT.relative_to(ROOT)}")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
