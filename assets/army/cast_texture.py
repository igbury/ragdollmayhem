# Paints the plaster cast's texture (build.py casts(): Cast_* pieces) to assets/army/cast_plaster.png.
# Run: python assets/army/cast_texture.py
#
# The casts are UV-mapped round their limb: u = once round (the image tiles across, so the seam does not
# show), v = along it, 1 stud = PX_PER_STUD px, each piece on its own stretch of the image (CAST_V in
# build.py) so the arm, the forearm and the hand do not show the same marks. Painted: warm plaster,
# mottled; the fine weave of the fibreglass tape; the edges of the overlapping turns, slanting round the
# limb as the roll went on; and what friends write on a cast in marker: names, GET WELL SOON, doodles.
# No blood, nothing that could read as a wound (Roblox moderation).
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 1024, 2048
PX_PER_STUD = H / 6  # v: 6 studs of cast down the image
SEED = 7
FONTS = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")


def font(name, size):
    try:
        return ImageFont.truetype(os.path.join(FONTS, name), size)
    except OSError:
        return ImageFont.load_default()


def base(rng):
    # mottled plaster: low-frequency noise, tiling across (wrapped blur)
    noise = rng.normal(0, 1, (H // 16, W // 16)).astype(np.float32)
    img = Image.fromarray(((noise - noise.min()) / np.ptp(noise) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
    mott = np.asarray(img.filter(ImageFilter.GaussianBlur(18)), np.float32) / 255 - 0.5
    grain = rng.normal(0, 1, (H, W)).astype(np.float32)
    col = np.array([243, 240, 232], np.float32)
    shade = 1 + mott[..., None] * 0.07 + grain[..., None] * 0.012
    rgb = col * shade
    # the fibreglass weave: a fine crosshatch
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    weave = (np.sin(x * 2 * math.pi / 9) * np.sin(y * 2 * math.pi / 9))
    rgb *= (1 - 0.025 * (weave > 0.55))[..., None]
    # the turns: band edges slanting once round the limb by exactly one band, so the image tiles across
    band = 118.0
    phase = (y + x * band / W) % band
    edge = np.exp(-((phase - 2) ** 2) / 6)  # the shadow under the next turn's edge
    lip = np.exp(-((phase - 7) ** 2) / 10)  # the edge itself catching the light
    rgb *= (1 - 0.13 * edge)[..., None]
    rgb *= (1 + 0.04 * lip)[..., None]
    return np.clip(rgb, 0, 255).astype(np.uint8)


MARKERS = [(32, 64, 190), (200, 36, 40), (30, 30, 34), (32, 120, 60), (110, 50, 150), (230, 120, 20)]
WORDS = ["GET WELL SOON!", "Mom", "Jake", "Lily <3", "Ouch!", "Sam", "Max", "Grandpa", "Feel better!",
         "Zoe", "Leo", "BFF", "Tough guy!", "Nina", "Coach", "Owen", "Ava", "Ragdoll Mayhem!", "Heal fast!"]


def doodle(d, rng, x, y, col):
    k = rng.integers(0, 4)
    s = int(rng.integers(42, 62))
    if k == 0:  # a heart
        pts = [(x + s * 0.06 * 16 * math.sin(t) ** 3,
                y - s * 0.06 * (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)))
               for t in (i * 2 * math.pi / 40 for i in range(41))]
        d.line(pts, fill=col, width=8, joint="curve")
    elif k == 1:  # a smiley
        d.ellipse((x - s, y - s, x + s, y + s), outline=col, width=8)
        d.ellipse((x - s // 2 - 4, y - s // 3 - 4, x - s // 2 + 4, y - s // 3 + 4), fill=col)
        d.ellipse((x + s // 2 - 4, y - s // 3 - 4, x + s // 2 + 4, y - s // 3 + 4), fill=col)
        d.arc((x - s // 2, y - s // 3, x + s // 2, y + s // 2 + 2), 20, 160, fill=col, width=8)
    elif k == 2:  # a star
        pts = []
        for i in range(10):
            a = -math.pi / 2 + i * math.pi / 5
            r = s if i % 2 == 0 else s * 0.42
            pts.append((x + r * math.cos(a), y + r * math.sin(a)))
        d.line(pts + [pts[0]], fill=col, width=8, joint="curve")
    else:  # a lightning bolt
        d.line((x - s // 3, y - s, x + s // 4, y - s // 6, x - s // 4, y + s // 6, x + s // 3, y + s), fill=col, width=6)


def writing(rgb, rng):
    img = Image.fromarray(rgb)
    hands = ["Inkfree.ttf", "segoepr.ttf", "segoesc.ttf", "comic.ttf", "segoeprb.ttf"]
    # one cell per mark, jittered, kept off the left and right edges (the seam round the limb)
    cols, rows = 2, 8
    words = list(WORDS)
    rng.shuffle(words)
    words.remove("GET WELL SOON!")
    words.insert(0, "GET WELL SOON!")  # always on it
    n = 0
    for r in range(rows):
        for c in range(cols):
            if rng.random() < 0.22:
                continue
            cx = int((c + 0.5) * W / cols + rng.integers(-50, 50))
            cy = int((r + 0.5) * H / rows + rng.integers(-30, 30))
            col = MARKERS[int(rng.integers(0, len(MARKERS)))]
            layer = Image.new("RGBA", (520, 260), (0, 0, 0, 0))
            d = ImageDraw.Draw(layer)
            if rng.random() < 0.3:
                doodle(d, rng, 260, 130, col + (235,))
            else:
                text = words[n % len(words)]
                n += 1
                f = font(hands[int(rng.integers(0, len(hands)))], int(rng.integers(80, 110)) if len(text) < 9 else 58)
                d.text((260, 130), text, font=f, fill=col + (235,), anchor="mm")
                if rng.random() < 0.4:  # underlined, a flourish
                    w = d.textlength(text, font=f)
                    d.line((260 - w / 2, 190, 260 + w / 2, 185), fill=col + (220,), width=6)
            layer = layer.rotate(float(rng.uniform(-28, 28)), resample=Image.BICUBIC)
            layer = layer.filter(ImageFilter.GaussianBlur(0.6))
            img.paste(layer, (cx - 260, cy - 130), layer)
    return img


def main():
    rng = np.random.default_rng(SEED)
    img = writing(base(rng), rng)
    out = os.path.join(HERE, "cast_plaster.png")
    img.save(out, optimize=True)
    print("cast texture ->", out, img.size)


if __name__ == "__main__":
    main()
