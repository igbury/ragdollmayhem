"""Draws the comic "BANG!"-style starburst (no text) used behind hit words: red halftone fill,
dark outline, grey drop shadow. Output: burst.png next to this script. Run: python make_burst.py"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

W, H, S = 576, 346, 4  # reference layout, supersampled for clean edges
# tips and valleys, clockwise from the left spike (reference layout coordinates)
PTS = [
    (40, 150), (125, 160), (100, 60), (185, 98), (232, 14), (275, 72), (330, 30), (368, 62),
    (432, 18), (440, 98), (548, 84), (490, 166), (566, 216), (482, 226), (512, 302), (420, 256),
    (392, 334), (330, 268), (252, 324), (226, 258), (118, 302), (140, 226), (28, 244), (110, 196),
]
cx, cy = 300, 175  # pull everything onto a canvas with room for the shadow
pad = 20
OUT_W, OUT_H = W + pad * 2, H + pad * 2


def poly(dx=0, dy=0, grow=1.0):
    return [((cx + (x - cx) * grow + dx + pad) * S, (cy + (y - cy) * grow + dy + pad) * S) for x, y in PTS]


img = Image.new("RGBA", (OUT_W * S, OUT_H * S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
d.polygon(poly(14, 12), fill=(190, 190, 195, 200))  # drop shadow, down-right
fill = Image.new("RGBA", img.size, (0, 0, 0, 0))
ImageDraw.Draw(fill).polygon(poly(), fill=(232, 40, 32, 255))
mask = fill.split()[3]
# halftone: orange dots, bigger toward the lower right like printed shading
dots = ImageDraw.Draw(fill)
step = 7 * S
for gy in range(0, img.size[1], step):
    for gx in range(0, img.size[0], step):
        x = gx + (step // 2 if (gy // step) % 2 else 0)
        t = (x / img.size[0] * 0.6 + gy / img.size[1] * 0.4)
        r = (0.9 + 2.2 * t) * S
        dots.ellipse((x - r, gy - r, x + r, gy + r), fill=(255, 150, 50, 255))
fill.putalpha(mask)
img.alpha_composite(fill)
outline = poly()
d.line(outline + outline[:2], fill=(80, 12, 12, 255), width=5 * S, joint="curve")  # dark ink edge (wraps past start so the seam joins)
img = img.resize((OUT_W * 2, OUT_H * 2), Image.LANCZOS)  # 1232x772, plenty for a billboard
img.save(Path(__file__).with_name("burst.png"))
print(img.size)
