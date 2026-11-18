# The police baton (a side-handle nightstick), built in code rather than in weapons.blend: a few
# lathed cylinders, the same data format as export.py writes and the same comic outline shell as
# comic.py bakes (a pushed-out copy, faces reversed, pure black). Run from the repo root:
#   python assets/weapons/baton.py
# Mesh space: +Y along the stick from the grip (the origin), like the Bat.
import math

SEG = 20
OUTLINE = 0.022
COLORS = [(0.09, 0.09, 0.11), (0.2, 0.2, 0.23), (0.62, 0.63, 0.68), (0, 0, 0), (0.33, 0.22, 0.14)]  # shaft, grip, metal, outline, leather
SHAFT, GRIP, METAL, BLACK, LEATHER = 1, 2, 3, 4, 5

verts, normals, faces = [], [], []  # faces: (a, b, c, na, nb, nc, colour), 1-based


def add_v(p):
    verts.append(p)
    return len(verts)


def add_n(n):
    l = math.sqrt(sum(x * x for x in n)) or 1
    normals.append(tuple(x / l for x in n))
    return len(normals)


def lathe(origin, axis, side, rings, cap_lo, cap_hi, colour_of):
    """rings: [(t, r)] along `axis` from `origin`; `side` is a unit vector across it. Smooth sides,
    flat caps. colour_of(i): colour of the band between ring i and i + 1."""
    other = (axis[1] * side[2] - axis[2] * side[1], axis[2] * side[0] - axis[0] * side[2], axis[0] * side[1] - axis[1] * side[0])

    def at(t, r, k):
        a = 2 * math.pi * k / SEG
        d = tuple(math.cos(a) * s + math.sin(a) * o for s, o in zip(side, other))
        return tuple(o + ax * t + dd * r for o, ax, dd in zip(origin, axis, d)), d

    ring_ids = []
    for t, r in rings:
        ids = []
        for k in range(SEG):
            p, d = at(t, r, k)
            ids.append((add_v(p), add_n(d)))
        ring_ids.append(ids)
    for i in range(len(rings) - 1):
        col = colour_of(i)
        for k in range(SEG):
            a, b = ring_ids[i][k], ring_ids[i][(k + 1) % SEG]
            c, d = ring_ids[i + 1][k], ring_ids[i + 1][(k + 1) % SEG]
            faces.append((a[0], b[0], d[0], a[1], b[1], d[1], col))
            faces.append((a[0], d[0], c[0], a[1], d[1], c[1], col))
    for ids, (t, r), sign, col in ((ring_ids[0], rings[0], -1, cap_lo), (ring_ids[-1], rings[-1], 1, cap_hi)):
        centre = add_v(tuple(o + ax * t for o, ax in zip(origin, axis)))
        n = add_n(tuple(ax * sign for ax in axis))
        cap = [add_v(verts[v - 1]) for v, _ in ids]
        for k in range(SEG):
            a, b = cap[k], cap[(k + 1) % SEG]
            if sign > 0:
                faces.append((centre, a, b, n, n, n, col))
            else:
                faces.append((centre, b, a, n, n, n, col))


def fix_winding():
    """Make each face's winding agree with its normal (cross . n > 0), as the exported weapons do."""
    for i, (a, b, c, na, nb, nc, col) in enumerate(faces):
        pa, pb, pc = verts[a - 1], verts[b - 1], verts[c - 1]
        u = tuple(y - x for x, y in zip(pa, pb))
        w = tuple(y - x for x, y in zip(pa, pc))
        cr = (u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0])
        n = normals[na - 1]
        if sum(x * y for x, y in zip(cr, n)) < 0:
            faces[i] = (a, c, b, na, nc, nb, col)


def torus(centre, axis_a, axis_b, normal, big, small, colour, segs=20, sides=8):
    """A ring of radius `big` in the plane of axis_a / axis_b round `centre`, tube radius `small`."""
    ids = []
    for i in range(segs):
        u = 2 * math.pi * i / segs
        out = tuple(math.cos(u) * a + math.sin(u) * b for a, b in zip(axis_a, axis_b))
        row = []
        for j in range(sides):
            v = 2 * math.pi * j / sides
            d = tuple(math.cos(v) * o + math.sin(v) * n for o, n in zip(out, normal))
            p = tuple(c + o * big + dd * small for c, o, dd in zip(centre, out, d))
            row.append((add_v(p), add_n(d)))
        ids.append(row)
    for i in range(segs):
        for j in range(sides):
            a, b = ids[i][j], ids[(i + 1) % segs][j]
            c, d = ids[i][(j + 1) % sides], ids[(i + 1) % segs][(j + 1) % sides]
            faces.append((a[0], b[0], d[0], a[1], b[1], d[1], colour))
            faces.append((a[0], d[0], c[0], a[1], d[1], c[1], colour))


# the stick: knurled metal butt cap, ribbed rubber grip, metal collar, long black shaft, a metal
# ring near the end, rounded metal tip
rings = [(-0.56, 0.05), (-0.56, 0.09), (-0.54, 0.118)]
t = -0.54
for _ in range(3):  # knurls on the cap
    rings += [(t + 0.02, 0.124), (t + 0.035, 0.112)]
    t += 0.035
rings += [(-0.42, 0.118), (-0.42, 0.098)]
n_cap = len(rings) - 1
t = -0.42
for _ in range(6):  # ribs
    rings += [(t + 0.05, 0.098), (t + 0.05, 0.107), (t + 0.1, 0.107), (t + 0.1, 0.098)]
    t += 0.125
n_grip = len(rings) - 1
rings += [(0.34, 0.098), (0.34, 0.112), (0.42, 0.112), (0.42, 0.09)]  # collar
n_collar = len(rings) - 1
rings += [(0.46, 0.088), (1.95, 0.085), (1.95, 0.094), (2.02, 0.094), (2.02, 0.085), (2.15, 0.084),
          (2.2, 0.08), (2.24, 0.068), (2.27, 0.05), (2.29, 0.026)]


def stick_colour(i):
    if i < n_cap:
        return METAL
    if i < n_grip:
        return GRIP
    if i < n_collar:
        return METAL
    return METAL if rings[i][0] >= 1.95 and not (2.02 <= rings[i][0] < 2.15) else SHAFT


lathe((0, 0, 0), (0, 1, 0), (1, 0, 0), rings, METAL, METAL, stick_colour)
# the side handle: a collar on the stick, a ribbed grip, a knob on its end
handle = [(0.0, 0.1), (0.06, 0.1), (0.06, 0.072)]
t = 0.08
for _ in range(4):
    handle += [(t, 0.072), (t, 0.08), (t + 0.04, 0.08), (t + 0.04, 0.072)]
    t += 0.075
handle += [(0.4, 0.072), (0.4, 0.088), (0.47, 0.088), (0.5, 0.06)]
lathe((0, 0.55, 0.05), (0, 0, 1), (1, 0, 0), handle, METAL, METAL,
      lambda i: METAL if i < 2 or i >= len(handle) - 4 else (GRIP if i % 4 in (1, 2) else SHAFT))
# the wrist strap: a leather loop hanging from the butt
torus((0, -0.78, 0), (0, 1, 0), (1, 0, 0), (0, 0, 1), 0.2, 0.025, LEATHER)
fix_winding()

# comic outline: every face again, pushed out along its vertex normals, reversed, black
body = list(faces)
moved = {}
for a, b, c, na, nb, nc, _ in body:
    for v, n in ((a, na), (b, nb), (c, nc)):
        if (v, n) not in moved:
            p, nn = verts[v - 1], normals[n - 1]
            moved[(v, n)] = (add_v(tuple(x + y * OUTLINE for x, y in zip(p, nn))), add_n(tuple(-x for x in nn)))
for a, b, c, na, nb, nc, _ in body:
    (va, ma), (vb, mb), (vc, mc) = moved[(a, na)], moved[(b, nb)], moved[(c, nc)]
    faces.append((va, vc, vb, ma, mc, mb, BLACK))


def fmt(xs):
    return ",".join(("%.3f" % x).rstrip("0").rstrip(".") if isinstance(x, float) else str(x) for x in xs)


out = [
    "-- Generated by assets/weapons/baton.py. v = xyz per vertex, n = xyz per normal, c = rgb per colour,",
    "-- f = 7 numbers per triangle: 3 vertex ids, 3 normal ids, 1 colour id (all 1-based).",
    "return {",
    "\tv = {" + fmt([x for p in verts for x in p]) + "},",
    "\tn = {" + fmt([x for p in normals for x in p]) + "},",
    "\tc = {" + fmt([float(x) for p in COLORS for x in p]) + "},",
    "\tf = {" + fmt([x for f in faces for x in f]) + "},",
    "}",
    "",
]
open("src/client/WeaponMeshes/Baton.luau", "w", newline="\n").write("\n".join(out))
print(len(verts), "verts", len(faces), "tris")
