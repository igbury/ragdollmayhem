"""Bruise textures: a mottled purple blotch with a dark core, pinpoint capillary spots and a faint
yellow-green halo fading to transparent at a ragged edge. The server lays them straight onto a
body part as a Texture at the hit point (init.server.luau bruiseAt).

Outputs bruise_1..3.png: three shapes, each a blotch in the middle of a big transparent 1024 tile
(PAD times the blotch width), so the Texture can be tiled huge and show exactly one copy on a part.
Run: python make_bruise.py"""
import numpy as np
from PIL import Image, ImageFilter

N = 256  # the blotch is drawn at this size
PAD = 6.4  # tile width / blotch width; the server's BRUISE_PAD must match
OUT = 1024


def render(seed):
    rng = np.random.default_rng(seed)

    def noise(octaves):
        """Smooth value noise in 0..1, summed over a few octaves."""
        out, amp, total = np.zeros((N, N)), 1.0, 0.0
        for cells in octaves:
            grid = Image.fromarray((rng.random((cells, cells)) * 255).astype(np.uint8))
            out += amp * np.asarray(grid.resize((N, N), Image.BICUBIC), dtype=float) / 255
            total += amp
            amp *= 0.5
        return out / total

    y, x = np.mgrid[0:N, 0:N] / (N - 1) * 2 - 1
    # a few overlapping soft patches (blood pooled under the skin), not one round disc
    density = np.zeros((N, N))
    for _ in range(11):
        cx, cy = rng.normal(0, 0.24, 2)
        sx, sy = rng.uniform(0.14, 0.32, 2)
        th = rng.uniform(0, np.pi)
        u = (x - cx) * np.cos(th) + (y - cy) * np.sin(th)
        v = -(x - cx) * np.sin(th) + (y - cy) * np.cos(th)
        density += rng.uniform(0.5, 1) * np.exp(-((u / sx) ** 2 + (v / sy) ** 2))
    density /= density.max()
    # a ragged edge and a blotchy inside: noise eats into it
    density *= 0.35 + 1.1 * noise([5, 10, 20])
    mottle = noise([8, 16, 32, 64])
    density *= 0.55 + 0.9 * mottle
    # pinpoint spots of broken capillaries, mostly in the darker middle
    spots = np.zeros((N, N))
    for _ in range(45):
        px, py = rng.normal(0, 0.28, 2)
        spots += np.exp(-(((x - px) ** 2 + (y - py) ** 2) / rng.uniform(0.0006, 0.002)))
    density = np.maximum(density, np.clip(spots, 0, 1) * 0.7 * np.clip(density * 3, 0, 1))
    density = np.clip(density / np.percentile(density, 99.5), 0, 1)
    # the halo: blood broken down to yellow-green around the purple, wider and fainter
    blur = Image.fromarray((density * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(18))
    halo = np.asarray(blur, dtype=float) / 255

    core = np.array([70, 30, 70])  # deep plum
    body = np.array([118, 58, 104])  # violet-red
    edge = np.array([150, 104, 140])  # faded mauve
    rim = np.array([176, 168, 104])  # old yellow-green

    def mix(a, b, k):
        return a + (b - a) * np.clip(k, 0, 1)[..., None]

    col = mix(rim, edge, density / 0.3)
    col = mix(col, body, (density - 0.3) / 0.35)
    col = mix(col, core, (density - 0.7) / 0.3)
    col *= (0.85 + 0.3 * mottle)[..., None]

    alpha = np.clip(density * 1.3, 0, 0.85) + np.clip(halo * 0.9, 0, 0.35) * (1 - density)
    alpha *= np.clip((0.98 - np.hypot(x, y)) * 5, 0, 1)  # nothing reaches the blotch's border
    img = np.dstack([np.clip(col, 0, 255), np.clip(alpha, 0, 1) * 255]).astype(np.uint8)
    return Image.fromarray(img, "RGBA").filter(ImageFilter.GaussianBlur(0.8))


if __name__ == "__main__":
    size = round(OUT / PAD)
    for i, seed in enumerate([7, 21, 58], 1):
        tile = Image.new("RGBA", (OUT, OUT), (0, 0, 0, 0))
        blotch = render(seed).resize((size, size), Image.LANCZOS)
        tile.alpha_composite(blotch, ((OUT - size) // 2, (OUT - size) // 2))
        tile.save(__file__.replace("make_bruise.py", f"bruise_{i}.png"))
