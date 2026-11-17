# Builds the comic boxing gloves in weapons.blend: "BoxingGloves" (right) and "BoxingGloveLeft" (its
# mirror): a fist with the fingers curled under, a thumb laid along its side, piping, palm panel,
# laces, a velcro strap and a logo patch; flat sRGB face colours ("Col") and comic.py's outline shell.
# Run inside Blender with weapons.blend open, then export.py with NAMES = ["BoxingGloves", "BoxingGloveLeft"]:
#   exec(open(r"<repo>/assets/weapons/glove.py").read(), {"__name__": "__main__"})
# Modelled in the glove space of src/shared/BoxingGloves.luau (Roblox axes: -Z out along the fingers,
# +Z up the forearm, +Y the back of the hand, thumb on -X for the right hand); the origin is that
# space's origin, so the mesh drops in where the part-built glove was. Blender = (-x, z, y) of Roblox.
# Keep BoxingGloves under ~4k triangles before the outline: the icon atlas (WeaponMeshes.icon) holds
# it with every other weapon under the 20k EditableMesh cap.
import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

RED = (0.86, 0.09, 0.11)
RED_DARK = (0.52, 0.05, 0.09)
PIPING = (0.42, 0.03, 0.07)
WHITE = (0.96, 0.94, 0.88)

comic = {"__name__": "comic"}
exec(open(os.path.join(os.path.dirname(bpy.data.filepath), "comic.py")).read(), comic)

V = Vector


def blender(v):
    return V((-v.x, v.z, v.y))


def spline(pts, t):
    """Catmull-Rom through pts, t in 0..1."""
    n = len(pts) - 1
    f = min(t * n, n - 1e-6)
    i = int(f)
    u = f - i
    p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, n)]
    return 0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u
                  + (-p0 + 3 * p1 - 3 * p2 + p3) * u * u * u)


def frames(pts, samples, side=None):
    """Points along the spline with a parallel-transported frame (t, centre, tangent, side, normal).
    side: the starting side axis (default +X)."""
    ts = [(1 - math.cos(math.pi * i / (samples - 1))) / 2 for i in range(samples)]  # denser at the ends
    cs = [spline(pts, t) for t in ts]
    out, s = [], V(side or (1, 0, 0))
    for i, c in enumerate(cs):
        tan = (cs[min(i + 1, samples - 1)] - cs[max(i - 1, 0)]).normalized()
        s = (s - tan * s.dot(tan)).normalized()
        out.append((ts[i], c, tan, s, tan.cross(s)))
    return out


def ends(t, a=0.14):
    u = min(t / a, (1 - t) / a, 1)
    return math.sqrt(max(0.0, 1 - (1 - u) ** 2))


class Glove:
    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")

    def _paint(self, faces, rgb):
        for f in faces:
            for loop in f.loops:
                loop[self.col] = (*rgb, 1)

    def blob(self, centre, radii, rgb, rot=(0, 0, 0), segs=18, rings=12):
        """An ellipsoid (Roblox space), poles out to the sides."""
        before = set(self.bm.faces)
        bmesh.ops.create_uvsphere(self.bm, u_segments=segs, v_segments=rings, radius=1)
        faces = [f for f in self.bm.faces if f not in before]
        m = Euler(rot).to_matrix()
        for v in {v for f in faces for v in f.verts}:
            p = V((v.co.z * radii[0], v.co.y * radii[1], v.co.x * radii[2]))
            v.co = blender(m @ p + V(centre))
        self._paint(faces, rgb)

    def tube(self, pts, prof, rgb, ring=16, samples=24, side=None, a=0.14):
        """A closed tube along pts (Roblox space). prof(t) -> (rx, ry): half-width along the side
        axis and half-thickness along the normal; the ends round off over the first / last a of t."""
        before = set(self.bm.faces)
        rings = []
        for t, c, _, s, n in frames(pts, samples, side):
            rx, ry = prof(t)
            e = max(ends(t, a), 0.04)
            rings.append([self.bm.verts.new(blender(c + s * (rx * e * math.cos(k * 2 * math.pi / ring))
                                                   + n * (ry * e * math.sin(k * 2 * math.pi / ring))))
                          for k in range(ring)])
        for r0, r1 in zip(rings, rings[1:]):
            for k in range(ring):
                self.bm.faces.new((r0[k], r0[(k + 1) % ring], r1[(k + 1) % ring], r1[k]))
        self.bm.faces.new(rings[0])
        self.bm.faces.new(list(reversed(rings[-1])))
        self._paint([f for f in self.bm.faces if f not in before], rgb)

    def ring(self, z0, z1, r0, r1, rgb, segs=24):
        """A capped band round Roblox Z: radius r0 at z0 to r1 at z1."""
        before = set(self.bm.faces)
        bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs,
                              radius1=r0, radius2=r1, depth=abs(z1 - z0))
        faces = [f for f in self.bm.faces if f not in before]
        for v in {v for f in faces for v in f.verts}:
            v.co = blender(V((v.co.x, v.co.y, (z0 + z1) / 2 + v.co.z)))
        self._paint(faces, rgb)

    def finish(self, name):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        for e in self.bm.edges:  # crisp where pieces meet at hard angles, smooth over the padding
            e.smooth = not (e.is_manifold and e.calc_face_angle(0) > math.radians(55))
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for p in me.polygons:
            p.use_smooth = True
        me.materials.append(bpy.data.materials["WeaponVertexColor"])
        return place(name, me)


def place(name, me):
    ob = bpy.data.objects.get(name)
    if ob:
        old = ob.data
        ob.data = me
        bpy.data.meshes.remove(old)
    else:
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
    me.name = name
    return ob


# The curled fingers: from the back of the hand, over the knuckles, round the front and back under
# towards the palm, so the side view is a "C" round the fist.
FIST = [V((0, 0.17, 0.04)), V((0, 0.25, -0.28)), V((0, 0.14, -0.6)), V((0, -0.1, -0.72)),
        V((0, -0.3, -0.6)), V((0, -0.35, -0.36))]


def fist_prof(t):
    knuckles = math.exp(-((t - 0.42) / 0.22) ** 2)  # fullest over the knuckles
    return 0.43 + 0.04 * knuckles, 0.22 + 0.03 * knuckles


def on_fist(angle, inset=0.97, samples=26):
    """Points along the fist's surface at an angle round its section (0 = +X side, 90 = top)."""
    a = math.radians(angle)
    out = []
    for t, c, _, s, n in frames(FIST, samples):
        rx, ry = fist_prof(t)
        e = ends(t)
        out.append(c + s * (rx * e * inset * math.cos(a)) + n * (ry * e * inset * math.sin(a)))
    return out[2:-2]


def build():
    g = Glove()
    g.tube(FIST, fist_prof, RED, ring=20, samples=24)
    # back of the hand and palm, filling the inside of the curl and running up to the cuff
    g.blob((0, -0.04, -0.2), (0.41, 0.34, 0.5), RED, segs=16, rings=10)
    # palm panel underneath, in the darker leather
    g.blob((0, -0.335, -0.06), (0.3, 0.06, 0.27), RED_DARK, rot=(0.12, 0, 0), segs=16, rings=8)
    # piping where the side panels meet the top and the bottom of the fist
    for angle in (35, 145, -35, -145):
        g.tube(on_fist(angle), lambda t: (0.022, 0.022), PIPING, ring=5, samples=20, a=0.05)
    # thumb along the -X side: from the base of the palm, forward and up, its tip stitched to the fist
    thumb = [V((-0.27, -0.16, 0.06)), V((-0.42, -0.1, -0.14)), V((-0.48, -0.01, -0.36)), V((-0.43, 0.06, -0.52))]
    g.tube(thumb, lambda t: (0.15 - 0.03 * t, 0.16 - 0.03 * t), RED, ring=16, samples=18, side=(0, 1, 0), a=0.25)
    g.tube([p + V((-0.13, 0.02, 0)) for p in thumb[1:]], lambda t: (0.02, 0.02), PIPING, ring=6, samples=14, a=0.08)
    # cuff over the wrist: velcro strap, white band, dark lip where the arm goes in
    # swells over the wrist so it swallows the forearm's end (the R15 lower arm is ~0.82 x 0.91 thick),
    # then narrows again to hug the forearm where the glove ends
    def cuff(z):
        return 0.42 + 0.1 * (z - 0.12) / 0.28 if z < 0.4 else 0.52 - 0.06 * (z - 0.4) / 0.26

    g.ring(0.12, 0.4, cuff(0.12), cuff(0.4), RED_DARK)
    g.ring(0.4, 0.66, cuff(0.4), cuff(0.66), RED_DARK)
    g.ring(0.28, 0.38, cuff(0.28) + 0.02, cuff(0.38) + 0.02, RED)
    g.ring(0.43, 0.51, cuff(0.43) + 0.022, cuff(0.51) + 0.022, WHITE)
    g.ring(0.58, 0.68, cuff(0.58) + 0.018, cuff(0.68) + 0.018, PIPING)
    # laces up the palm side of the cuff, below the strap
    for i in range(3):
        z = 0.13 + 0.055 * i
        for x in (-1, 1):
            g.tube([V((-0.09 * x, -cuff(z) - 0.01, z)), V((0.09 * x, -cuff(z + 0.05) - 0.01, z + 0.05))],
                   lambda t: (0.02, 0.02), WHITE, ring=6, samples=6, a=0.2)
    # brand label across the back of the hand: a white strip with a red bar for the lettering
    g.blob((0, 0.485, -0.27), (0.27, 0.045, 0.1), WHITE, rot=(-0.12, 0, 0), segs=16, rings=6)
    g.blob((0, 0.52, -0.27), (0.17, 0.025, 0.03), RED, rot=(-0.12, 0, 0), segs=10, rings=4)
    return g.finish("BoxingGloves")


def mirror(right, name):
    me = right.data.copy()
    me.transform(Matrix.Scale(-1, 4, (1, 0, 0)))
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return place(name, me)


def main():
    right = build()
    right.location = (12.5, 0, -4)
    print("BoxingGloves", sum(len(p.vertices) - 2 for p in right.data.polygons), "tris before the outline")
    comic["punch"](right.data)
    comic["outline"](right.data)
    right.data.update()
    left = mirror(right, "BoxingGloveLeft")
    left.location = (14, 0, -4)


if __name__ == "__main__":
    main()
