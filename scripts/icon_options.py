#!/usr/bin/env python3
"""Render app icon candidates plus a contact sheet, for picking a mark.

    python3 scripts/icon_options.py

Writes each candidate to AppStore/icons/ at 1024, and a `_contact-sheet.png` showing every
one at 320px and again at 120px behind an iOS squircle mask. The 120px row is the one that
matters: an icon that only works large is not an icon.
"""

from __future__ import annotations

import colorsys
import math
import pathlib

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
FONT = ROOT / "AppStore" / "marketing" / "fonts" / "Outfit-Bold.ttf"
OUT = ROOT / "AppStore" / "icons"

SIZE = 1024
SCALE = 4
# iOS squircle corner radius as a fraction of the icon's side.
SQUIRCLE = 0.2237


def hsl(h: float, s: float, lightness: float) -> tuple[int, int, int]:
    r, g, b = colorsys.hls_to_rgb(h / 360.0, lightness / 100.0, s / 100.0)
    return (round(r * 255), round(g * 255), round(b * 255))


MAGENTA = [
    [hsl(335, 84, 62), hsl(340, 80, 52)],
    [hsl(342, 80, 50), hsl(352, 84, 36)],
]
GRAPHITE = [
    [hsl(330, 10, 26), hsl(330, 12, 18)],
    [hsl(330, 12, 17), hsl(335, 16, 9)],
]


def wash(canvas: int, corners) -> Image.Image:
    seed = Image.new("RGB", (2, 2))
    seed.putpixel((0, 0), corners[0][0])
    seed.putpixel((1, 0), corners[0][1])
    seed.putpixel((0, 1), corners[1][0])
    seed.putpixel((1, 1), corners[1][1])
    return seed.resize((canvas, canvas), Image.BICUBIC)


def monogram(size: int = SIZE) -> Image.Image:
    """A heavy lowercase r. The sibling of Grams' g, and the shipped default."""
    canvas = size * SCALE
    image = wash(canvas, MAGENTA)
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(FONT), int(canvas * 0.66))
    left, top, right, bottom = draw.textbbox((0, 0), "r", font=font)
    draw.text(
        (canvas / 2 - (left + right) / 2, canvas / 2 - (top + bottom) / 2),
        "r", font=font, fill=(255, 255, 255),
    )
    return image.resize((size, size), Image.LANCZOS)


def figure(size: int = SIZE) -> Image.Image:
    """A push-up silhouette: a straight body on a diagonal, arms down to the floor line."""
    canvas = size * SCALE
    image = wash(canvas, MAGENTA)
    draw = ImageDraw.Draw(image)
    white = (255, 255, 255)
    stroke = int(canvas * 0.055)

    # Body: shoulders high-left to heels low-right, on the diagonal the eye reads as effort.
    draw.line([(canvas * 0.26, canvas * 0.40), (canvas * 0.80, canvas * 0.62)],
              fill=white, width=stroke)
    # Arm straight down from the shoulder to the floor.
    draw.line([(canvas * 0.30, canvas * 0.42), (canvas * 0.30, canvas * 0.70)],
              fill=white, width=stroke)
    # Floor line, shorter than the body so it does not read as an underline.
    draw.line([(canvas * 0.20, canvas * 0.74), (canvas * 0.80, canvas * 0.74)],
              fill=white, width=int(stroke * 0.7))
    # Head.
    head = canvas * 0.062
    draw.ellipse(
        [canvas * 0.22 - head, canvas * 0.36 - head, canvas * 0.22 + head, canvas * 0.36 + head],
        fill=white,
    )
    return image.resize((size, size), Image.LANCZOS)


def ring_r(size: int = SIZE) -> Image.Image:
    """The progress ring itself, with the r's stem and shoulder cut into it."""
    canvas = size * SCALE
    image = wash(canvas, MAGENTA)
    draw = ImageDraw.Draw(image)
    white = (255, 255, 255)
    stroke = int(canvas * 0.085)
    inset = canvas * 0.20
    box = [inset, inset, canvas - inset, canvas - inset]
    # An open arc, so the gap reads as "in progress" rather than a closed O.
    draw.arc(box, start=118, end=62, fill=white, width=stroke)
    # The stem, dropping from the center to the baseline.
    draw.line([(canvas * 0.42, canvas * 0.38), (canvas * 0.42, canvas * 0.70)],
              fill=white, width=stroke)
    # The shoulder.
    draw.arc([canvas * 0.40, canvas * 0.32, canvas * 0.66, canvas * 0.56],
             start=200, end=350, fill=white, width=stroke)
    return image.resize((size, size), Image.LANCZOS)


def counter(size: int = SIZE) -> Image.Image:
    """A rep count, on graphite. Reads as a number, which is what the app produces."""
    canvas = size * SCALE
    image = wash(canvas, GRAPHITE)
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(FONT), int(canvas * 0.40))
    text = "100"
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    draw.text(
        (canvas / 2 - (left + right) / 2, canvas / 2 - (top + bottom) / 2),
        text, font=font, fill=hsl(335, 84, 62),
    )
    return image.resize((size, size), Image.LANCZOS)


CANDIDATES = {
    "monogram": monogram,
    "figure": figure,
    "ring_r": ring_r,
    "counter": counter,
}


def squircle_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size * 4 - 1, size * 4 - 1],
        radius=int(size * 4 * SQUIRCLE),
        fill=255,
    )
    return mask.resize((size, size), Image.LANCZOS)


def contact_sheet(rendered: dict[str, Image.Image]) -> Image.Image:
    large, small, pad = 320, 120, 32
    label = 26
    width = pad + len(rendered) * (large + pad)
    height = pad + large + label + pad + small + label + pad

    sheet = Image.new("RGB", (width, height), (18, 16, 20))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(str(FONT), 20)
    mask_large, mask_small = squircle_mask(large), squircle_mask(small)

    for index, (name, image) in enumerate(rendered.items()):
        x = pad + index * (large + pad)
        big = image.resize((large, large), Image.LANCZOS)
        sheet.paste(big, (x, pad), mask_large)
        draw.text((x, pad + large + 4), name, font=font, fill=(220, 214, 220))

        tiny = image.resize((small, small), Image.LANCZOS)
        y = pad + large + label + pad
        sheet.paste(tiny, (x + (large - small) // 2, y), mask_small)
        draw.text((x + (large - small) // 2, y + small + 4), "120px", font=font, fill=(150, 144, 152))

    return sheet


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rendered = {}
    for name, render in CANDIDATES.items():
        image = render()
        image.save(OUT / f"{name}.png", format="PNG")
        rendered[name] = image
        print(f"wrote AppStore/icons/{name}.png")

    sheet = contact_sheet(rendered)
    sheet.save(OUT / "_contact-sheet.png", format="PNG")
    print("wrote AppStore/icons/_contact-sheet.png")


if __name__ == "__main__":
    main()
