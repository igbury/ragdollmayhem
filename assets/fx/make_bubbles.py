"""Draws the comic speech bubbles (no text) used over dummies: white fill, black ink edge and a
halftone dot shadow down-right. Output: bubble_talk.png, bubble_shout.png, bubble_think.png next
to this script. Run: python make_bubbles.py"""
import math
import random
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter

W, H, S = 600, 400, 3  # final size, supersample factor
INK, EDGE, SHADOW = 7, (22, 18), 7  # outline px, shadow offset, dot spacing (final px)


def canvas():
    return Image.new("L", (W * S, H * S), 0)


def talk():  # oval with a tail to the lower left
    m = canvas()
    d = ImageDraw.Draw(m)
    d.ellipse((60 * S, 30 * S, 560 * S, 300 * S), fill=255)
    d.polygon([(150 * S, 250 * S), (250 * S, 280 * S), (70 * S, 375 * S)], fill=255)
    return m


def shout():  # spiky burst, sharp uneven points, the longest one pointing down-left
    m = canvas()
    rnd = random.Random(7)
    cx, cy, n = 305, 175, 22
    pts = []
    for i in range(n * 2):
        a = i / (n * 2) * math.tau
        if i % 2:
            r = 0.72
        else:
            r = 1.0 + rnd.uniform(-0.04, 0.16)
        if i == 2 * round(n * 0.36):  # the tail spike
            r = 1.45
        pts.append(((cx + math.cos(a) * 250 * r) * S, (cy + math.sin(a) * 140 * r) * S))
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


def think():  # cloud of puffs with a trail of little ones
    m = canvas()
    d = ImageDraw.Draw(m)
    cx, cy, rx, ry = 310, 170, 200, 98
    d.ellipse(((cx - rx) * S, (cy - ry) * S, (cx + rx) * S, (cy + ry) * S), fill=255)
    n = 11
    for i in range(n):
        a = i / n * math.tau
        x, y = cx + math.cos(a) * rx, cy + math.sin(a) * ry
        r = 52 + 10 * math.sin(i * 2.3)
        d.ellipse(((x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S), fill=255)
    for x, y, r in ((135, 315, 24), (90, 360, 14)):
        d.ellipse(((x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S), fill=255)
    return m


def render(mask):
    k = INK * S * 2 + 1
    outer = mask.filter(ImageFilter.MaxFilter(k if k < 60 else 59))
    shadow = ImageChops.offset(outer, EDGE[0] * S, EDGE[1] * S)
    dots = canvas()
    dd = ImageDraw.Draw(dots)
    step = SHADOW * S
    for gy in range(0, H * S, step):
        for gx in range(0, W * S, step):
            x = gx + (step // 2 if (gy // step) % 2 else 0)
            r = 1.7 * S
            dd.ellipse((x - r, gy - r, x + r, gy + r), fill=255)
    shadow = ImageChops.multiply(shadow, dots)
    img = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    black = Image.new("RGBA", mask.size, (15, 15, 15, 255))
    img.paste(black, mask=ImageChops.lighter(shadow, outer))
    img.paste(Image.new("RGBA", mask.size, (255, 255, 255, 255)), mask=mask)
    return img.resize((W, H), Image.LANCZOS)


for name, fn in (("talk", talk), ("shout", shout), ("think", think)):
    render(fn()).save(Path(__file__).with_name(f"bubble_{name}.png"))
print("ok")
