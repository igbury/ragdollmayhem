"""Tileable halftone dot tile (white dots on transparent, offset grid) for the menu's print shading.
Tint it with ImageColor3 and fade it with a UIGradient. Output: halftone.png. Run: python make_halftone.py"""
from PIL import Image, ImageDraw

N, S, R = 64, 4, 11  # tile size, supersample, dot radius
img = Image.new("RGBA", (N * S, N * S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
for cx, cy in [(0, 0), (N, 0), (0, N), (N, N), (N / 2, N / 2)]:
    d.ellipse(((cx - R) * S, (cy - R) * S, (cx + R) * S, (cy + R) * S), fill=(255, 255, 255, 255))
img.resize((N, N), Image.LANCZOS).save(__file__.replace("make_halftone.py", "halftone.png"))
