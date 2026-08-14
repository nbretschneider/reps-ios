#!/usr/bin/env python3
"""Render the Reps app icon.

Writes a single 1024x1024 **RGB** PNG to the app icon set. RGB matters: App Store Connect
rejects an icon with an alpha channel.

The mark is a heavy lowercase "r" on a diagonal magenta wash, which is deliberately the
same construction as Grams' lowercase "g". The letter-on-a-wash is the family signature;
the hue is what tells the two apart in a home-screen folder.

    python3 scripts/make_icon.py
"""

from __future__ import annotations

import colorsys
import pathlib

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
FONT = ROOT / "AppStore" / "marketing" / "fonts" / "Outfit-Bold.ttf"
OUT = ROOT / "Reps" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"

SIZE = 1024
# 4x supersample, then LANCZOS down. The glyph's curves alias badly at 1024 otherwise.
SCALE = 4


def hsl(h: float, s: float, lightness: float) -> tuple[int, int, int]:
    """HSL in the same units Theme.swift uses, so values can be copied across."""
    r, g, b = colorsys.hls_to_rgb(h / 360.0, lightness / 100.0, s / 100.0)
    return (round(r * 255), round(g * 255), round(b * 255))


# Corners of a 2x2 image, bicubic-upscaled. That is what produces a genuinely diagonal
# falloff rather than the linear band a per-row gradient gives.
CORNERS = [
    [hsl(335, 84, 62), hsl(340, 80, 52)],
    [hsl(342, 80, 50), hsl(352, 84, 36)],
]


def render(size: int = SIZE) -> Image.Image:
    canvas = size * SCALE

    wash = Image.new("RGB", (2, 2))
    wash.putpixel((0, 0), CORNERS[0][0])
    wash.putpixel((1, 0), CORNERS[0][1])
    wash.putpixel((0, 1), CORNERS[1][0])
    wash.putpixel((1, 1), CORNERS[1][1])
    image = wash.resize((canvas, canvas), Image.BICUBIC)

    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(FONT), int(canvas * 0.66))

    # Center on the glyph's ink box, not its typographic box. A lowercase "r" has no
    # descender and a short x-height, so its layout box sits well above the optical center
    # and centering on it puts the letter noticeably high.
    left, top, right, bottom = draw.textbbox((0, 0), "r", font=font)
    draw.text(
        (canvas / 2 - (left + right) / 2, canvas / 2 - (top + bottom) / 2),
        "r",
        font=font,
        fill=(255, 255, 255),
    )

    return image.resize((size, size), Image.LANCZOS)


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    image = render()
    assert image.mode == "RGB", "App Store Connect rejects an icon with an alpha channel"
    image.save(OUT, format="PNG")
    print(f"wrote {OUT.relative_to(ROOT)} ({image.size[0]}x{image.size[1]}, {image.mode})")


if __name__ == "__main__":
    main()
