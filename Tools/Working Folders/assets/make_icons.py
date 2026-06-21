#!/usr/bin/env python3
"""Regenerate the Working Folders icon artwork.

Source of the two PNGs in this folder. Run only when you want to change the
look — the tool itself doesn't need this (it ships the PNGs). Requires Pillow
(`pip install Pillow`); that's a build-time tool, not a dependency of the app.

Outputs (1024x1024 RGBA):
  working-folders-app.png     rounded tile + gold star  -> the drag-&-drop app
  working-folders-folder.png  standalone gold star      -> the shelf folder icon
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

SS = 4                      # supersample factor for smooth edges
SIZE = 1024
S = SIZE * SS
HERE = os.path.dirname(os.path.abspath(__file__))

# palette
BLUE_TOP = (78, 162, 255)
BLUE_BOT = (12, 86, 206)
GOLD_TOP = (255, 226, 140)
GOLD_BOT = (242, 161, 0)
GOLD_EDGE = (193, 120, 6)


def lerp(a, b, t):
    return a + (b - a) * t


def vgrad(top, bot):
    """Full-size vertical gradient (built as a 1px strip, then stretched)."""
    strip = Image.new("RGBA", (1, S))
    for y in range(S):
        t = y / (S - 1)
        strip.putpixel((0, y), (int(lerp(top[0], bot[0], t)),
                                int(lerp(top[1], bot[1], t)),
                                int(lerp(top[2], bot[2], t)), 255))
    return strip.resize((S, S))


def star_points(cx, cy, outer, inner, n=5, rot_deg=-90):
    pts = []
    for i in range(n * 2):
        ang = math.radians(rot_deg + i * 180.0 / n)
        rad = outer if i % 2 == 0 else inner
        pts.append((cx + rad * math.cos(ang), cy + rad * math.sin(ang)))
    return pts


def gold_star(canvas, cx, cy, outer, inner, shadow_dy, shadow_blur, shadow_a,
              edge_w):
    """Composite a soft-shadowed, gold-gradient star onto `canvas`."""
    pts = star_points(cx, cy, outer, inner)

    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon(
        star_points(cx, cy + shadow_dy, outer, inner), fill=(0, 0, 0, shadow_a))
    shadow = shadow.filter(ImageFilter.GaussianBlur(shadow_blur))
    canvas = Image.alpha_composite(canvas, shadow)

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    star = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    star.paste(vgrad(GOLD_TOP, GOLD_BOT), (0, 0), mask)
    ImageDraw.Draw(star).line(pts + [pts[0]], fill=GOLD_EDGE + (255,),
                              width=edge_w, joint="curve")
    return Image.alpha_composite(canvas, star)


def make_app():
    margin = int(S * 0.045)
    radius = int(S * 0.225)

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [margin, margin, S - margin, S - margin], radius=radius, fill=255)

    tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    tile.paste(vgrad(BLUE_TOP, BLUE_BOT), (0, 0), mask)

    # soft top sheen
    sheen = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sheen).ellipse(
        [int(S * 0.1), int(-S * 0.35), int(S * 0.9), int(S * 0.45)], fill=70)
    sheen = sheen.filter(ImageFilter.GaussianBlur(S * 0.05))
    sheen = Image.composite(sheen, Image.new("L", (S, S), 0), mask)
    white = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    tile = Image.composite(white, tile, sheen)

    tile = gold_star(tile, S / 2, S * 0.52, S * 0.30, S * 0.135,
                     shadow_dy=S * 0.012, shadow_blur=S * 0.016,
                     shadow_a=150, edge_w=max(1, int(S * 0.004)))
    tile.resize((SIZE, SIZE), Image.LANCZOS).save(
        os.path.join(HERE, "working-folders-app.png"))


def make_folder():
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    canvas = gold_star(canvas, S / 2, S * 0.5, S * 0.46, S * 0.205,
                       shadow_dy=S * 0.02, shadow_blur=S * 0.022,
                       shadow_a=120, edge_w=max(1, int(S * 0.005)))
    canvas.resize((SIZE, SIZE), Image.LANCZOS).save(
        os.path.join(HERE, "working-folders-folder.png"))


if __name__ == "__main__":
    make_app()
    make_folder()
    print("Wrote working-folders-app.png and working-folders-folder.png")
