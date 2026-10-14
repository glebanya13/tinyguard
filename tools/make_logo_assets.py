#!/usr/bin/env python3
"""Builds every logo-derived image from assets/brand/logo.png (deterministic, Pillow).

  icon.png                          192x192 launcher icon (rounded square)
  ui/app/icon_foreground.png        432x432 adaptive icon foreground (art inside the 66% safe zone)
  ui/app/icon_background.png        432x432 adaptive icon background (blurred logo)
  ui/app/splash.png                 1280x720 boot splash
  assets/store/icon_512.png         512x512 Google Play icon (opaque, square: Play rounds it)
  assets/store/feature_1024x500.png 1024x500 Google Play feature graphic

The source art is assets/brand/logo.png (owner-provided logo, 2026-10-14). These images replace
the ones that tools/render_app_icon.gd and tools/render_store_art.gd used to render.

Run: python3 tools/make_logo_assets.py
"""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "assets/brand/logo.png"


def rounded(im: Image.Image, radius: int) -> Image.Image:
	"""RGBA copy of `im` with rounded corners."""
	im = im.convert("RGBA")
	mask = Image.new("L", im.size, 0)
	ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), radius, fill=255)
	im.putalpha(ImageChops.multiply(im.getchannel("A"), mask))
	return im


def blurred_cover(logo: Image.Image, size: tuple[int, int], radius: int) -> Image.Image:
	"""The logo scaled to cover `size` (centre crop) and blurred: a calm backdrop."""
	scale = max(size[0] / logo.width, size[1] / logo.height)
	big = logo.resize((round(logo.width * scale), round(logo.height * scale)), Image.LANCZOS)
	left = (big.width - size[0]) // 2
	top = (big.height - size[1]) // 2
	return big.crop((left, top, left + size[0], top + size[1])).filter(ImageFilter.GaussianBlur(radius))


def main() -> None:
	logo = Image.open(LOGO).convert("RGB")

	# Legacy launcher icon.
	icon = logo.resize((192, 192), Image.LANCZOS)
	rounded(icon, 38).save(ROOT / "icon.png", optimize=True)

	# Adaptive icon: the whole logo inside the central 66% (288 of 432 px).
	background = blurred_cover(logo, (432, 432), 14)
	background.save(ROOT / "ui/app/icon_background.png", optimize=True)
	foreground = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
	art = rounded(logo.resize((288, 288), Image.LANCZOS), 36)
	foreground.alpha_composite(art, (72, 72))
	foreground.save(ROOT / "ui/app/icon_foreground.png", optimize=True)

	# Play icon: opaque 32-bit PNG, Play applies its own corner rounding.
	logo.resize((512, 512), Image.LANCZOS).convert("RGBA").save(
		ROOT / "assets/store/icon_512.png", optimize=True
	)

	# Boot splash: framed logo on its own blurred backdrop.
	splash = blurred_cover(logo, (1280, 720), 22).convert("RGBA")
	splash.alpha_composite(rounded(logo.resize((640, 640), Image.LANCZOS), 64), (320, 40))
	splash.save(ROOT / "ui/app/splash.png", optimize=True)

	# Feature graphic: the logo in the centre, a wide crop of it as the backdrop.
	feature = blurred_cover(logo, (1024, 500), 10).convert("RGBA")
	feature.alpha_composite(rounded(logo.resize((460, 460), Image.LANCZOS), 48), (282, 20))
	feature.convert("RGB").save(ROOT / "assets/store/feature_1024x500.png", optimize=True)
	print("make_logo_assets: done")


if __name__ == "__main__":
	main()
