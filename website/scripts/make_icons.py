#!/usr/bin/env python3
"""Generates the website's icons and optimized images from the game's own art.

Deterministic (no randomness, fixed settings). Run from anywhere:

    python3 website/scripts/make_icons.py

Reads ../assets/brand/logo.png and ../assets/store/*.png, writes into website/public/.
Requires Pillow with WebP support.
"""
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
PUBLIC = Path(__file__).resolve().parents[1] / "public"
IMG = PUBLIC / "img"

SHOTS = [
    "shot_01_map",
    "shot_02_level_1_valley",
    "shot_03_level_4_snow",
    "shot_04_level_5_autumn",
    "shot_05_level_6_desert",
    "shot_06_upgrade",
    "shot_07_tutorial",
    "shot_08_treasury",
]


def square_icon(logo: Image.Image, size: int) -> Image.Image:
    return logo.resize((size, size), Image.LANCZOS)


def cover(img: Image.Image, w: int, h: int) -> Image.Image:
    scale = max(w / img.width, h / img.height)
    resized = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    left = (resized.width - w) // 2
    top = (resized.height - h) // 2
    return resized.crop((left, top, left + w, top + h))


def main() -> None:
    IMG.mkdir(parents=True, exist_ok=True)
    logo = Image.open(ROOT / "assets/brand/logo.png").convert("RGB")

    # Icons from the game logo.
    sizes = [16, 32, 48, 64]
    square_icon(logo, 256).save(PUBLIC / "favicon.ico", format="ICO", sizes=[(s, s) for s in sizes])
    square_icon(logo, 180).save(PUBLIC / "apple-touch-icon.png", optimize=True)
    square_icon(logo, 192).save(PUBLIC / "icon-192.png", optimize=True)
    square_icon(logo, 512).save(PUBLIC / "icon-512.png", optimize=True)

    # Logo for the page (hero) and the header.
    square_icon(logo, 720).save(IMG / "logo-720.webp", quality=82, method=6)
    square_icon(logo, 96).save(IMG / "logo-96.webp", quality=85, method=6)

    # Open Graph card 1200x630: blurred logo background + feature graphic.
    feature = Image.open(ROOT / "assets/store/feature_1024x500.png").convert("RGB")
    og = cover(logo, 1200, 630).filter(ImageFilter.GaussianBlur(18))
    dark = Image.new("RGB", og.size, (11, 16, 32))
    og = Image.blend(og, dark, 0.45)
    fw = 1100
    fh = round(feature.height * fw / feature.width)
    feat = feature.resize((fw, fh), Image.LANCZOS)
    og.paste(feat, ((1200 - fw) // 2, (630 - fh) // 2))
    og.save(PUBLIC / "og-image.png", optimize=True)

    # Hero background: replaceable. The owner may drop their own public/img/hero.jpg; it is never overwritten.
    hero = IMG / "hero.jpg"
    if not hero.exists():
        valley = Image.open(ROOT / "assets/store/shot_02_level_1_valley.png").convert("RGB")
        valley.save(hero, quality=80, optimize=True, progressive=True)

    # Screenshots: 1280x720 WebP for the gallery.
    for name in SHOTS:
        shot = Image.open(ROOT / "assets/store" / f"{name}.png").convert("RGB")
        shot.resize((1280, 720), Image.LANCZOS).save(IMG / f"{name}.webp", quality=78, method=6)

    total = sum(p.stat().st_size for p in IMG.glob("*"))
    print(f"images: {total / 1e6:.2f} MB in {IMG}")


if __name__ == "__main__":
    main()
