"""Myth Yard v2 (high detail): Cyclops, Minotaur, Talos and their cages.

Built in Roblox studs under one root empty scaled to metres (1 stud = 0.28 m).
Small details are merged into per-joint "batch" meshes so the scene stays light
on object count while carrying thousands of primitives.

Run headless:
  blender -b --factory-startup --python-exit-code 1 -P build_myth_yard.py -- [--no-render]
"""
import bpy, bmesh, math, os, sys, json, random
from mathutils import Vector, Matrix, Quaternion, Euler

OUT = os.path.dirname(os.path.abspath(__file__))
RENDER = "--no-render" not in sys.argv
S = 0.28
rnd = random.Random(1337)
STATS = {"prims": 0}
SIDES = (("R", -1), ("L", 1))
rad = math.radians

bpy.ops.wm.read_homefile(use_empty=True)
scene = bpy.context.scene

# ======================================================================= materials
def lin(c):
    def f(v):
        v /= 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (f(c[0]), f(c[1]), f(c[2]), 1.0)

def sock(sockets, ident):
    return next(s for s in sockets if s.identifier == ident)

MATS = {}
def mat(name, rgb, rough=0.6, metal=0.0, emit=0.0, noise=0.0, dark=0.7, bump=0.0, veins=None, nscale=None):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    N, L = nt.nodes, nt.links
    bsdf = next(n for n in N if n.type == "BSDF_PRINCIPLED")
    col = lin(rgb)
    m.diffuse_color = col
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit > 0:
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = emit
    tc = N.new("ShaderNodeTexCoord")
    co = tc.outputs["Object"]
    out = None
    if noise > 0:
        nz = N.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = noise
        nz.inputs["Detail"].default_value = 8.0
        L.new(co, nz.inputs["Vector"])
        mr = N.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value = 0.35
        mr.inputs["From Max"].default_value = 0.68
        L.new(nz.outputs["Fac"], mr.inputs["Value"])
        mix = N.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        L.new(mr.outputs["Result"], sock(mix.inputs, "Factor_Float"))
        sock(mix.inputs, "A_Color").default_value = lin([v * dark for v in rgb])
        sock(mix.inputs, "B_Color").default_value = col
        out = sock(mix.outputs, "Result_Color")
        # roughness variation
        rr = N.new("ShaderNodeMapRange")
        rr.inputs["To Min"].default_value = max(0.0, rough - 0.12)
        rr.inputs["To Max"].default_value = min(1.0, rough + 0.12)
        L.new(nz.outputs["Fac"], rr.inputs["Value"])
        L.new(rr.outputs["Result"], bsdf.inputs["Roughness"])
    if veins:
        wv = N.new("ShaderNodeTexWave")
        wv.inputs["Scale"].default_value = 0.16
        wv.inputs["Distortion"].default_value = 9.0
        wv.inputs["Detail"].default_value = 6.0
        L.new(co, wv.inputs["Vector"])
        mr2 = N.new("ShaderNodeMapRange")
        mr2.inputs["From Min"].default_value = 0.0
        mr2.inputs["From Max"].default_value = 0.06
        mr2.inputs["To Min"].default_value = 0.85
        mr2.inputs["To Max"].default_value = 0.0
        L.new(wv.outputs["Fac"], mr2.inputs["Value"])
        mix2 = N.new("ShaderNodeMix")
        mix2.data_type = "RGBA"
        L.new(mr2.outputs["Result"], sock(mix2.inputs, "Factor_Float"))
        if out:
            L.new(out, sock(mix2.inputs, "A_Color"))
        else:
            sock(mix2.inputs, "A_Color").default_value = col
        sock(mix2.inputs, "B_Color").default_value = lin(veins)
        out = sock(mix2.outputs, "Result_Color")
    if out:
        L.new(out, bsdf.inputs["Base Color"])
    if bump > 0:
        nz2 = N.new("ShaderNodeTexNoise")
        nz2.inputs["Scale"].default_value = nscale or 7.0
        nz2.inputs["Detail"].default_value = 12.0
        L.new(co, nz2.inputs["Vector"])
        bp = N.new("ShaderNodeBump")
        bp.inputs["Strength"].default_value = bump
        L.new(nz2.outputs["Fac"], bp.inputs["Height"])
        L.new(bp.outputs["Normal"], bsdf.inputs["Normal"])
    MATS[name] = m
    return m

# ======================================================================= scene graph
COLL = None
REST = {}
_names = {}

def uname(base):
    i = _names.get(base, 0)
    _names[base] = i + 1
    return base if i == 0 else f"{base}.{i:02d}"

def collection(name, parent=None):
    c = bpy.data.collections.new(name)
    (parent or scene.collection).children.link(c)
    return c

def place(ob, parent, pos, rot=None, quat=None):
    COLL.objects.link(ob)
    ob.parent = parent
    base = REST.get(parent.name, Vector()) if parent else Vector()
    ob.location = Vector(pos) - base
    if quat is not None:
        ob.rotation_mode = "QUATERNION"
        ob.rotation_quaternion = quat
    elif rot:
        ob.rotation_euler = [rad(a) for a in rot]
    REST[ob.name] = Vector(pos)
    return ob

def empty(name, pos, parent, size=0.6):
    ob = bpy.data.objects.new(uname(name), None)
    ob.empty_display_size = size
    return place(ob, parent, pos)

def basis_quat(x, side):
    x = Vector(x).normalized()
    y = Vector(side)
    y = (y - y.project(x)).normalized()
    z = x.cross(y)
    return Matrix((x, y, z)).transposed().to_quaternion()

def axes_quat(xa, za):
    z = Vector(za).normalized()
    x = Vector(xa)
    x = (x - x.project(z)).normalized()
    y = z.cross(x)
    return Matrix((x, y, z)).transposed().to_quaternion()

def box(name, size, pos, m, parent, rot=None, bevel=0.12, quat=None, seg=2):
    name = uname(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if m:
        me.materials.append(m)
    ob = place(bpy.data.objects.new(name, me), parent, pos, rot, quat)
    STATS["prims"] += 1
    if bevel:
        me.shade_smooth()
        mod = ob.modifiers.new("Bevel", "BEVEL")
        mod.width = min(bevel, min(size) * 0.3)
        mod.segments = seg
        mod.limit_method = "ANGLE"
        mod.harden_normals = True
    return ob

CHIPS = None
def organic(name, size, pos, m, parent, rot=None, quat=None, bevel=0.4, levels=2, disp=0.0):
    """Rounded, subdivided block - reads as sculpted mass instead of a Roblox part."""
    global CHIPS
    ob = box(name, size, pos, m, parent, rot=rot, quat=quat, bevel=0)
    ob.data.shade_smooth()
    bv = ob.modifiers.new("Bevel", "BEVEL")
    bv.width = min(bevel, min(size) * 0.42)
    bv.segments = 1
    ss = ob.modifiers.new("Subsurf", "SUBSURF")
    ss.levels = ss.render_levels = levels
    if disp:
        if CHIPS is None:
            CHIPS = bpy.data.textures.new("StoneChips", "CLOUDS")
            CHIPS.noise_scale = 0.55
            CHIPS.noise_depth = 4
        d = ob.modifiers.new("Displace", "DISPLACE")
        d.texture = CHIPS
        d.strength = disp
        d.mid_level = 0.5
    return ob

def _M(pos, rot=None, quat=None, scale=(1, 1, 1), base=Vector()):
    T = Matrix.Translation(Vector(pos) - base)
    if quat is not None:
        R = quat.to_matrix().to_4x4()
    elif rot:
        R = Euler([rad(a) for a in rot]).to_matrix().to_4x4()
    else:
        R = Matrix.Identity(4)
    return T @ R @ Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))

class Batch:
    """Accumulates many primitives into one mesh (one object, many materials)."""
    def __init__(self, name, parent, bevel=0.04, sharp=40):
        self.name = uname(name)
        self.parent = parent
        self.bm = bmesh.new()
        self.mats = []
        self.bevel = bevel
        self.sharp = sharp
        self.base = REST.get(parent.name, Vector()) if parent else Vector()
        self.n = 0

    def _tag(self, verts, m):
        if m not in self.mats:
            self.mats.append(m)
        mi = self.mats.index(m)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = mi
            f.smooth = True
        self.n += 1
        STATS["prims"] += 1

    def box(self, size, pos, m, rot=None, quat=None):
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=_M(pos, rot, quat, size, self.base))
        self._tag(r["verts"], m)

    def ball(self, r, pos, m, scale=(1, 1, 1), seg=12, rot=None, quat=None):
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=max(6, seg // 2 + 1), radius=r,
                                        matrix=_M(pos, rot, quat, scale, self.base))
        self._tag(res["verts"], m)

    def rock(self, r, pos, m, scale=(1, 1, 1), jitter=0.28, rot=None):
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=1, radius=r, matrix=_M(pos, rot, None, scale, self.base))
        for v in res["verts"]:
            v.co += Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))) * r * jitter
        self._tag(res["verts"], m)

    def cyl(self, r, depth, pos, m, rot=None, quat=None, verts=12, r2=None, scale=(1, 1, 1)):
        res = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=verts, radius1=r,
                                    radius2=r if r2 is None else r2, depth=depth,
                                    matrix=_M(pos, rot, quat, scale, self.base))
        self._tag(res["verts"], m)

    def cyl_between(self, a, b, r, m, r2=None, verts=10):
        a, b = Vector(a), Vector(b)
        d = b - a
        if d.length < 1e-5:
            return
        self.cyl(r, d.length, (a + b) / 2, m, quat=Vector((0, 0, 1)).rotation_difference(d), verts=verts, r2=r2)

    def box_between(self, a, b, w, d, m, side=(0, -1, 0), extend=0.0):
        a, b = Vector(a), Vector(b)
        dv = b - a
        if dv.length < 1e-5:
            return
        self.box((dv.length + extend, d, w), (a + b) / 2, m, quat=basis_quat(dv, side))

    def torus(self, R, r, pos, m, rot=None, quat=None, seg=16, ring=8, sx=1.0, arc=360.0):
        M = _M(pos, rot, quat, (1, 1, 1), self.base)
        full = arc >= 359.9
        n = seg if full else seg + 1
        grid = []
        for i in range(n):
            a = rad(arc) * i / seg
            row = []
            for j in range(ring):
                b = 2 * math.pi * j / ring
                rr = R + r * math.cos(b)
                row.append(self.bm.verts.new(M @ Vector((rr * math.cos(a) * sx, rr * math.sin(a), r * math.sin(b)))))
            grid.append(row)
        for i in range(seg):
            i2 = (i + 1) % n
            for j in range(ring):
                self.bm.faces.new((grid[i][j], grid[i2][j], grid[i2][(j + 1) % ring], grid[i][(j + 1) % ring]))
        self._tag([v for row in grid for v in row], m)

    def lathe(self, profile, pos, m, rot=None, quat=None, seg=16, scale=(1, 1, 1)):
        M = _M(pos, rot, quat, scale, self.base)
        rings = []
        for r, z in profile:
            if r < 1e-4:
                rings.append([self.bm.verts.new(M @ Vector((0, 0, z)))])
            else:
                rings.append([self.bm.verts.new(M @ Vector((r * math.cos(2 * math.pi * k / seg),
                                                              r * math.sin(2 * math.pi * k / seg), z)))
                              for k in range(seg)])
        for A, B in zip(rings, rings[1:]):
            if len(A) == 1 and len(B) == 1:
                continue
            for k in range(seg):
                if len(A) == 1:
                    self.bm.faces.new((A[0], B[k], B[(k + 1) % seg]))
                elif len(B) == 1:
                    self.bm.faces.new((A[k], B[0], A[(k + 1) % seg]))
                else:
                    self.bm.faces.new((A[k], B[k], B[(k + 1) % seg], A[(k + 1) % seg]))
        self._tag([v for r in rings for v in r], m)

    def prism(self, pts, thick, pos, m, rot=None, quat=None):
        """2D outline in local XZ, extruded along local Y."""
        M = _M(pos, rot, quat, (1, 1, 1), self.base)
        f = [self.bm.verts.new(M @ Vector((x, -thick / 2, z))) for x, z in pts]
        b = [self.bm.verts.new(M @ Vector((x, thick / 2, z))) for x, z in pts]
        self.bm.faces.new(f[::-1])
        self.bm.faces.new(b)
        n = len(pts)
        for i in range(n):
            self.bm.faces.new((f[i], f[(i + 1) % n], b[(i + 1) % n], b[i]))
        self._tag(f + b, m)

    def finish(self):
        if self.n == 0:
            self.bm.free()
            return None
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        try:
            me.set_sharp_from_angle(angle=rad(self.sharp))
        except Exception:
            pass
        ob = bpy.data.objects.new(self.name, me)
        COLL.objects.link(ob)
        ob.parent = self.parent
        REST[ob.name] = self.base
        if self.bevel:
            mod = ob.modifiers.new("Bevel", "BEVEL")
            mod.width = self.bevel
            mod.segments = 2
            mod.limit_method = "ANGLE"
            mod.angle_limit = rad(50)
            mod.harden_normals = True
        return ob

class Detail:
    """Lazy per-joint batches."""
    def __init__(self, P, J, bevel=0.035):
        self.P, self.J, self.b, self.bevel = P, J, {}, bevel
    def __getitem__(self, k):
        if k not in self.b:
            self.b[k] = Batch(self.P + k + "_detail", self.J[k], bevel=self.bevel)
        return self.b[k]
    def finish(self):
        for v in self.b.values():
            v.finish()

def curve(name, pts, radius, m, parent, closed=False, taper=None):
    name = uname(name)
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 3
    cu.use_fill_caps = True
    sp = cu.splines.new("NURBS")
    sp.points.add(len(pts) - 1)
    base = REST.get(parent.name, Vector())
    for i, (p, co) in enumerate(zip(sp.points, pts)):
        c = Vector(co) - base
        p.co = (c.x, c.y, c.z, 1.0)
        if taper:
            p.radius = taper[i]
    sp.use_endpoint_u = True
    sp.order_u = 3
    sp.use_cyclic_u = closed
    cu.materials.append(m)
    ob = bpy.data.objects.new(name, cu)
    COLL.objects.link(ob)
    ob.parent = parent
    REST[ob.name] = base
    STATS["prims"] += 1
    return ob

def text(name, body, pos, size, m, parent, extrude=0.12):
    name = uname(name)
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = body
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.size = size
    cu.extrude = extrude
    cu.bevel_depth = 0.02
    cu.materials.append(m)
    return place(bpy.data.objects.new(name, cu), parent, pos, rot=(90, 0, 0))

def light(name, kind, pos, parent, energy, rgb=(255, 255, 255), radius=0.3, rot=None, size=None):
    name = uname(name)
    ld = bpy.data.lights.new(name, kind)
    ld.energy = energy
    ld.color = lin(rgb)[:3]
    if kind in ("POINT", "SPOT"):
        ld.shadow_soft_size = radius
    if kind == "AREA" and size:
        ld.size = size
    return place(bpy.data.objects.new(name, ld), parent, pos, rot)

# ======================================================================= detail generators
def ell_point(c, r, az, el):
    c = Vector(c)
    x = r[0] * math.cos(el) * math.sin(az)
    y = -r[1] * math.cos(el) * math.cos(az)
    z = r[2] * math.sin(el)
    return c + Vector((x, y, z)), Vector((x / r[0] ** 2, y / r[1] ** 2, z / r[2] ** 2)).normalized()

def crack_ell(b, c, r, az, el, m, steps=7, step=0.13, w=0.085, branch=True):
    a, e = rad(az), rad(el)
    p, n = ell_point(c, r, a, e)
    da, de = rnd.uniform(-1, 1), rnd.uniform(-1, 1)
    for i in range(steps):
        da = da * 0.6 + rnd.uniform(-1, 1)
        de = de * 0.6 + rnd.uniform(-1, 1) - 0.25
        l = math.hypot(da, de) or 1.0
        a += da / l * step
        e += de / l * step
        q, nq = ell_point(c, r, a, e)
        b.box_between(p, q, w, 0.14, m, side=n, extend=w)
        if branch and i == steps // 2:
            crack_ell(b, c, r, math.degrees(a), math.degrees(e), m, steps=3, step=step * 0.8, w=w * 0.65, branch=False)
        p, n = q, nq
        w *= 0.93

def crack_plane(b, origin, t, up, n, u, v, m, steps=8, step=0.45, w=0.1, branch=True):
    o, t, up, n = Vector(origin), Vector(t), Vector(up), Vector(n)
    P = lambda uu, vv: o + t * uu + up * vv
    p = P(u, v)
    du, dv = rnd.uniform(-1, 1), -1.0
    for i in range(steps):
        du = du * 0.5 + rnd.uniform(-1, 1)
        dv = dv * 0.5 + rnd.uniform(-1, 0.4)
        l = math.hypot(du, dv) or 1.0
        u += du / l * step
        v += dv / l * step
        q = P(u, v)
        b.box_between(p, q, w, 0.12, m, side=n, extend=w)
        if branch and i == steps // 2:
            crack_plane(b, origin, t, up, n, u, v, m, steps=3, step=step * 0.7, w=w * 0.6, branch=False)
        p = q
        w *= 0.93

def tuft(b, p, n, L, r, m, droop=0.45):
    d = (Vector(n) * (1 - droop) + Vector((0, 0.18, -1)) * droop).normalized()
    d += Vector((rnd.uniform(-0.15, 0.15), rnd.uniform(-0.15, 0.15), rnd.uniform(-0.1, 0.1)))
    d.normalize()
    p = Vector(p)
    b.cyl_between(p - d * 0.15, p + d * L, r, m, r2=0.02, verts=5)
    d2 = (d + Vector((rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), 0))).normalized()
    b.cyl_between(p - d * 0.1, p + d2 * L * 0.7, r * 0.7, m, r2=0.02, verts=5)

def moss(b, p, n, m, k=12, spread=0.5):
    p, n = Vector(p), Vector(n).normalized()
    t1 = n.orthogonal().normalized()
    t2 = n.cross(t1)
    for _ in range(k):
        u, v = rnd.gauss(0, spread), rnd.gauss(0, spread)
        b.ball(rnd.uniform(0.07, 0.17), p + t1 * u + t2 * v + n * 0.04, m, scale=(1, 1, 0.6), seg=6,
               quat=Vector((0, 0, 1)).rotation_difference(n))

def gear_pts(Ro, Ri, teeth):
    pts = []
    for k in range(teeth):
        a0 = 2 * math.pi * k / teeth
        da = 2 * math.pi / teeth
        for f, R in ((0.0, Ri), (0.18, Ro), (0.5, Ro), (0.68, Ri)):
            a = a0 + da * f
            pts.append((R * math.cos(a), R * math.sin(a)))
    return pts

def chain(b, a, c, m, link=0.62, R=0.32, r=0.09):
    a, c = Vector(a), Vector(c)
    d = c - a
    n = max(1, int(d.length / link))
    q1 = Vector((1, 0, 0)).rotation_difference(d)
    for i in range(n):
        q = Quaternion(d.normalized(), rad(90 * (i % 2))) @ q1
        b.torus(R, r, a + d * ((i + 0.5) / n), m, quat=q, seg=12, ring=6, sx=1.45)

def sag_chain(b, a, c, m, sag=1.0, segs=6, **kw):
    a, c = Vector(a), Vector(c)
    pts = [a.lerp(c, i / segs) - Vector((0, 0, sag * 4 * (i / segs) * (1 - i / segs))) for i in range(segs + 1)]
    for p, q in zip(pts, pts[1:]):
        chain(b, p, q, m, **kw)

def meander(b, origin, t, n, length, m, z0=1.1, h=1.7, unit=3.2, w=0.24):
    o, t, n = Vector(origin), Vector(t), Vector(n)
    P = lambda u, v: o + t * u + Vector((0, 0, z0 + v)) + n * 0.1
    b.box_between(P(0, 0), P(length, 0), w, 0.15, m, side=n, extend=w)
    b.box_between(P(0, h), P(length, h), w, 0.15, m, side=n, extend=w)
    k = int(length // unit)
    pad = (length - k * unit) / 2
    for i in range(k):
        u = pad + i * unit
        for a, c in [((u, 0), (u, h * 0.78)), ((u, h * 0.78), (u + 2.2, h * 0.78)),
                     ((u + 2.2, h * 0.78), (u + 2.2, h * 0.3)), ((u + 2.2, h * 0.3), (u + 1.0, h * 0.3)),
                     ((u + 1.0, h * 0.3), (u + 1.0, h * 0.55))]:
            b.box_between(P(*a), P(*c), w, 0.15, m, side=n, extend=w)

AMPHORA = [(0, 0), (0.28, 0), (0.42, 0.2), (0.75, 0.9), (0.85, 1.5), (0.72, 2.1), (0.36, 2.5),
           (0.27, 2.9), (0.4, 3.05), (0.34, 3.12), (0.24, 3.0), (0, 2.9)]

def amphora(b, pos, m, band, s=1.0, rot=None):
    b.lathe([(r * s, z * s) for r, z in AMPHORA], pos, m, rot=rot, seg=18)
    if rot is None:
        p = Vector(pos)
        b.torus(0.86 * s, 0.05 * s, p + Vector((0, 0, 1.5 * s)), band, seg=24, ring=6)
        b.torus(0.8 * s, 0.04 * s, p + Vector((0, 0, 1.2 * s)), band, seg=24, ring=6)
        for sx in (-1, 1):
            b.torus(0.3 * s, 0.07 * s, p + Vector((sx * 0.45 * s, 0, 2.55 * s)), m, rot=(90, 0, 0), arc=200, seg=10, ring=6)

def bone(b, a, c, m, r=0.14):
    a, c = Vector(a), Vector(c)
    b.cyl_between(a, c, r, m, verts=8)
    d = (c - a).normalized()
    side = d.orthogonal().normalized() * r * 0.8
    for p in (a, c):
        b.ball(r * 1.5, p + side, m, seg=8)
        b.ball(r * 1.5, p - side, m, seg=8)

def skull(b, pos, m, dark, s=1.0, yaw=0.0):
    p = Vector(pos)
    R = Euler((0, 0, rad(yaw))).to_matrix()
    f = lambda v: p + R @ (Vector(v) * s)
    b.ball(0.55 * s, f((0, 0, 0.5)), m, scale=(1, 1.15, 0.95), seg=14)
    b.box((0.75 * s, 0.6 * s, 0.35 * s), f((0, -0.35, 0.12)), m, rot=(0, 0, yaw))
    for sx in (-1, 1):
        b.ball(0.16 * s, f((sx * 0.22, -0.55, 0.5)), dark, seg=8)
    b.ball(0.08 * s, f((0, -0.66, 0.3)), dark, seg=6)
    for k in range(5):
        b.box((0.08 * s, 0.06 * s, 0.12 * s), f((-0.2 + k * 0.1, -0.66, 0.2)), m, rot=(0, 0, yaw))

def straw(b, center, radius, n, m, height=0.6):
    c = Vector(center)
    for _ in range(n):
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(0, radius) ** 0.8
        z = height * (1 - d / radius) * rnd.uniform(0.3, 1.0)
        p = c + Vector((math.cos(a) * d, math.sin(a) * d, z))
        L = rnd.uniform(0.8, 1.8)
        dirv = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.25, 0.25))).normalized()
        b.cyl_between(p - dirv * L / 2, p + dirv * L / 2, 0.045, m, verts=4)

def flame(b, pos, m_out, m_in, s=1.0):
    p = Vector(pos)
    b.cyl(0.32 * s, 1.0 * s, p + Vector((0, 0, 0.45 * s)), m_out, r2=0.0, verts=8)
    for k in range(4):
        a = k * math.pi / 2 + 0.4
        b.cyl(0.16 * s, 0.6 * s, p + Vector((math.cos(a) * 0.2 * s, math.sin(a) * 0.2 * s, 0.25 * s)), m_out, r2=0.0, verts=6,
              rot=(rnd.uniform(-15, 15), rnd.uniform(-15, 15), 0))
    b.cyl(0.18 * s, 0.6 * s, p + Vector((0, 0, 0.3 * s)), m_in, r2=0.0, verts=6)

# ======================================================================= humanoid (MythRig sizes)
def humanoid(P, root, body, limb=None, foot=None, head=True, mech=False, disp=0.0, palm=None):
    limb = limb or body
    foot = foot or limb
    palm = palm or body
    J = {"Root": root}
    J["Hips"] = empty(P + "Hips", (0, 0, 5.0), root)
    J["Spine"] = empty(P + "Spine", (0, 0, 7.0), J["Hips"])
    J["Neck"] = empty(P + "Neck", (0, -0.3, 10.2), J["Spine"])

    def part(name, size, pos, m, parent, bev=0.45):
        if mech:
            return box(P + name, size, pos, m, parent, bevel=0.3, seg=3)
        return organic(P + name, size, pos, m, parent, bevel=bev, levels=2, disp=disp)

    part("LowerTorso", (3.5, 2.4, 2.5), (0, 0, 5.7), body, J["Hips"])
    part("UpperTorso", (5.8, 3.1, 4.3), (0, 0, 8.4), body, J["Spine"], bev=0.9)
    if head:
        part("Head", (3.2, 2.6, 3.3), (0, -0.6, 11.2), body, J["Neck"], bev=0.8)
    for side, sx in SIDES:
        sh = J["Shoulder" + side] = empty(P + "Shoulder" + side, (sx * 3.6, 0, 9.6), J["Spine"])
        el = J["Elbow" + side] = empty(P + "Elbow" + side, (sx * 3.6, 0, 6.7), sh)
        hp = J["Hip" + side] = empty(P + "Hip" + side, (sx * 1.1, 0, 5.0), J["Hips"])
        kn = J["Knee" + side] = empty(P + "Knee" + side, (sx * 1.1, 0, 2.6), hp)
        part("UpperArm" + side, (2.3, 2.4, 3.5), (sx * 3.6, 0, 8.0), limb, sh, bev=0.7)
        part("LowerArm" + side, (1.9, 2.0, 3.0), (sx * 3.6, 0, 5.3), limb, el, bev=0.6)
        part("Hand" + side, (2.1, 1.9, 1.5), (sx * 3.6, 0, 3.45), palm, el, bev=0.5)
        part("UpperLeg" + side, (1.7, 2.0, 2.8), (sx * 1.1, 0, 3.6), limb, hp, bev=0.6)
        part("LowerLeg" + side, (1.5, 1.7, 2.1), (sx * 1.1, 0, 1.5), limb, kn, bev=0.5)
        if foot is not False:
            part("Foot" + side, (2.0, 2.8, 1.0), (sx * 1.1, -0.3, 0.5), foot, kn, bev=0.35)
    return J

def pose(J, **rots):
    for k, r in rots.items():
        J[k].rotation_euler = [rad(a) for a in r]

def posed(root, joint, rest_pos):
    bpy.context.view_layer.update()
    w = joint.matrix_world @ (Vector(rest_pos) - REST[joint.name])
    return root.matrix_world.inverted() @ w

def anatomy(D, m, bulk=1.0):
    sp = D["Spine"]
    for s, sx in SIDES:
        sp.ball(1.5 * bulk, (sx * 1.35, -1.42, 9.3), m, scale=(1, 0.38, 0.72), seg=24)
        for z in (8.05, 7.3, 6.6):
            sp.ball(0.5, (sx * 0.56, -1.52, z), m, scale=(1, 0.42, 0.75), seg=14)
        sp.ball(1.0, (sx * 2.35, -0.9, 7.3), m, scale=(0.55, 0.75, 1.25), seg=16)
        for k in range(3):
            sp.ball(0.35, (sx * 2.6, -1.1, 8.6 - k * 0.55), m, scale=(0.7, 0.6, 1.0), seg=10)
        sp.ball(1.2 * bulk, (sx * 1.6, 0.25, 10.35), m, scale=(1.25, 1.05, 0.55), seg=20)
        sp.ball(1.4, (sx * 1.95, 1.35, 8.6), m, scale=(0.85, 0.42, 1.4), seg=20)
        sh = D["Shoulder" + s]
        sh.ball(1.45 * bulk, (sx * 3.62, 0, 9.35), m, scale=(1, 1.02, 0.78), seg=24)
        sh.ball(1.0 * bulk, (sx * 3.55, -0.72, 7.95), m, scale=(0.95, 0.62, 1.35), seg=20)
        sh.ball(1.0, (sx * 3.65, 0.72, 8.1), m, scale=(0.95, 0.6, 1.4), seg=20)
        el = D["Elbow" + s]
        el.ball(0.95 * bulk, (sx * 3.6, -0.35, 5.9), m, scale=(1.0, 0.85, 1.3), seg=20)
        el.ball(0.55, (sx * 3.6, 0.6, 6.5), m, seg=14)
        hp = D["Hip" + s]
        hp.ball(1.0 * bulk, (sx * 1.1, -0.7, 3.9), m, scale=(0.95, 0.62, 1.4), seg=20)
        hp.ball(0.9, (sx * 1.1, 0.6, 3.8), m, scale=(0.9, 0.55, 1.3), seg=16)
        kn = D["Knee" + s]
        kn.ball(0.85 * bulk, (sx * 1.1, 0.55, 1.85), m, scale=(0.9, 0.75, 1.2), seg=20)
        kn.ball(0.5, (sx * 1.1, -0.85, 2.55), m, scale=(1, 0.7, 0.9), seg=14)
        kn.ball(0.3, (sx * 1.6, -0.1, 0.95), m, seg=10)
        kn.ball(0.3, (sx * 0.6, -0.1, 0.95), m, seg=10)
    D["Neck"].cyl_between((0, -0.15, 9.7), (0, -0.45, 10.7), 1.15, m, r2=1.05, verts=20)
    for sx in (-1, 1):
        D["Neck"].cyl_between((sx * 0.95, -0.35, 10.9), (sx * 0.3, -1.25, 9.85), 0.3, m, verts=10)

def fingers(D, s, sx, m, nail, mech=False, pin=None, n=3, curl=(12, 38, 66)):
    el = D["Elbow" + s]
    ys = [-0.62, 0.0, 0.62] if n == 3 else [-0.75, -0.25, 0.25, 0.75]
    for y in ys:
        p = Vector((sx * 3.6 + sx * 0.12, y, 2.75))
        for L, r, c in zip((0.72, 0.55, 0.42), (0.31, 0.28, 0.23), curl):
            a = rad(c + rnd.uniform(-6, 6))
            d = Vector((-sx * math.sin(a), 0, -math.cos(a)))
            q = p + d * L
            el.cyl_between(p, q, r, m, r2=r * 0.9, verts=10)
            el.ball(r * 1.1, p, m, seg=10)
            if mech and pin:
                el.cyl(r * 0.55, 2 * r + 0.12, p, pin, rot=(90, 0, 0), verts=8)
            p = q
        el.ball(r * 0.95, p, m, seg=10)
        out = Vector((sx * math.cos(a), 0, -math.sin(a)))
        el.ball(r * 0.72, p - d * 0.14 + out * r * 0.62, nail, scale=(0.45, 1.0, 1.0), seg=8)
        el.ball(0.24, Vector((sx * 3.6 + sx * 0.95, y, 3.1)), m, seg=8)  # knuckle ridge
    p = Vector((sx * 3.6 - sx * 0.85, -0.85, 3.05))
    d0 = Vector((-sx * 0.35, -0.55, -0.75)).normalized()
    for L, r in ((0.7, 0.33), (0.55, 0.27)):
        q = p + d0 * L
        el.cyl_between(p, q, r, m, r2=r * 0.9, verts=10)
        el.ball(r * 1.08, p, m, seg=10)
        p = q
        d0 = (d0 + Vector((sx * 0.35, 0, -0.2))).normalized()
    el.ball(0.25, p, m, seg=10)
    el.ball(0.18, p + Vector((0, -0.15, 0)), nail, scale=(1.0, 0.45, 1.0), seg=8)

def toes(D, s, sx, m, nail, n=4):
    kn = D["Knee" + s]
    for i in range(n):
        x = sx * 1.1 + (i - (n - 1) / 2) * 0.46
        r = 0.27 if abs(i - (n - 1) / 2) < 1 else 0.22
        kn.cyl_between((x, -1.4, 0.32), (x, -2.0, 0.27), r, m, r2=r * 0.85, verts=10)
        kn.ball(r * 0.95, (x, -2.0, 0.27), m, seg=10)
        kn.ball(r * 0.6, (x, -2.12, 0.4), nail, scale=(1.0, 0.6, 0.45), seg=8)

def snail_curl(b, p, n, m, r=0.36):
    p, n = Vector(p), Vector(n).normalized()
    q = Vector((0, 0, 1)).rotation_difference(n)
    b.ball(r, p, m, scale=(1, 1, 0.75), seg=12, quat=q)
    b.torus(r * 0.72, r * 0.26, p + n * r * 0.45, m, quat=q, seg=12, ring=6)
    b.ball(r * 0.3, p + n * r * 0.7, m, seg=8)

def boss_root(name, parent, pos, scale):
    r = empty(name, pos, parent, size=2)
    r.scale = (scale,) * 3
    REST[r.name] = Vector()
    return r

def cage_root(name, x):
    r = empty(name, (x, 0, 0), WORLD, size=3)
    REST[r.name] = Vector()
    return r

# ======================================================================= shared materials
MY = collection("MythYard")
COLL = MY
WORLD = empty("MythYard_root", (0, 0, 0), None, size=2)
WORLD.scale = (S, S, S)
REST[WORLD.name] = Vector()

IRON = mat("Iron_Corroded", (43, 47, 51), rough=0.6, metal=0.75, noise=1.2, dark=0.6, bump=0.25)
RUST = mat("Rust", (112, 58, 30), rough=0.92, noise=3.0, dark=0.6, bump=0.4)
DARK = mat("Socket_Dark", (30, 26, 22), rough=0.85)
GOLD = mat("Gold", (201, 162, 71), rough=0.25, metal=1.0, noise=2.0, dark=0.8)
TEAL = mat("Ichor_Neon", (92, 210, 190), emit=9.0)
TEALD = mat("Ichor_Line", (92, 210, 190), emit=3.0)
AMBER = mat("Amber_Neon", (236, 181, 68), emit=7.0)
FLAME = mat("Flame", (255, 150, 50), emit=22.0)
FLAMEI = mat("Flame_Core", (255, 230, 150), emit=35.0)
COALH = mat("Coal_Hot", (255, 86, 28), emit=5.0)
COAL = mat("Coal", (26, 24, 22), rough=0.8, noise=4.0)
WOOD = mat("Wood_Old", (92, 64, 40), rough=0.85, noise=2.5, dark=0.6, bump=0.3)
LEATHER = mat("Leather", (91, 58, 28), rough=0.7, noise=3.0, dark=0.7, bump=0.25)
STRAW = mat("Straw", (196, 160, 82), rough=0.9, noise=4.0, dark=0.75)
BONE = mat("Bone", (222, 210, 186), rough=0.6, noise=3.0, dark=0.8, bump=0.2)
MOSS = mat("Moss", (70, 96, 44), rough=1.0, noise=5.0, dark=0.6)
CLAY = mat("Terracotta", (168, 92, 58), rough=0.8, noise=2.0, dark=0.8)
CLOTH = mat("Cloth_Red", (128, 34, 30), rough=0.95, noise=3.0, dark=0.7, bump=0.2)
WATER = mat("Puddle", (72, 80, 88), rough=0.08)
CANDLE = mat("Candle", (230, 214, 180), rough=0.6)

# ======================================================================= CYCLOPS gate (x = -56)
COLL = collection("Cage_Cyclops", MY)
CG = cage_root("Cage_Cyclops", -56)
MORTAR = mat("Mortar", (74, 66, 58), rough=0.95, noise=2.0, dark=0.7, bump=0.5)
BRK = [mat(f"Brick_{i}", c, rough=0.9, noise=1.6, dark=0.72, bump=0.35)
       for i, c in enumerate([(110, 74, 51), (124, 82, 56), (96, 64, 46), (118, 70, 48)])]
STONE = mat("Stone_Dressed", (150, 122, 92), rough=0.85, noise=1.0, bump=0.45)
SLATE = mat("Slate_Dark", (52, 55, 60), rough=0.88, noise=0.8, dark=0.6, bump=0.45)
SLATE2 = mat("Slate_Block", (64, 66, 70), rough=0.9, noise=1.2, dark=0.6, bump=0.45)
SAND = mat("Sand", (196, 168, 120), rough=1.0, noise=0.6, dark=0.82, bump=0.3, nscale=20)
PEBBLE = mat("Pebble", (140, 128, 112), rough=0.8, noise=3.0)
GRASS = mat("Weed", (88, 112, 52), rough=0.9, noise=3.0, dark=0.6)

wall = box("ArchWall", (28, 3, 24), (0, -9, 12), MORTAR, CG, bevel=0)
cut1 = box("cutter_rect", (20, 6, 10), (0, -9, 5.0), None, CG, bevel=0)
cut2_me = bpy.data.meshes.new("cutter_arch")
_bm = bmesh.new()
bmesh.ops.create_cone(_bm, cap_ends=True, cap_tris=False, segments=64, radius1=10, radius2=10, depth=6)
_bm.to_mesh(cut2_me)
_bm.free()
cut2 = place(bpy.data.objects.new("cutter_arch", cut2_me), CG, (0, -9, 10), rot=(90, 0, 0))
for c in (cut1, cut2):
    md = wall.modifiers.new("cut", "BOOLEAN")
    md.operation, md.object, md.solver = "DIFFERENCE", c, "EXACT"
dg = bpy.context.evaluated_depsgraph_get()
new_me = bpy.data.meshes.new_from_object(wall.evaluated_get(dg))
wall.modifiers.clear()
old = wall.data
wall.data = new_me
bpy.data.meshes.remove(old)
for c in (cut1, cut2):
    me = c.data
    bpy.data.objects.remove(c)
    bpy.data.meshes.remove(me)

G = Batch("Gate_Masonry", CG, bevel=0.07)

def blocked(x, z):
    if z < 10.0:
        return abs(x) < 10.05
    return x * x + (z - 10.0) ** 2 < 11.95 ** 2

PITCH, Z0B = 0.97, 1.4
z, row = Z0B, 0
while z + PITCH <= 23.8:
    zc = z + PITCH / 2
    off = 1.05 if row % 2 else 0.0
    x = -14 - off
    while x < 14:
        x0, x1 = max(x, -14), min(x + 2.1, 14)
        x += 2.1
        if x1 - x0 < 0.45:
            continue
        if any(blocked(cx, cz) for cx, cz in ((x0, z), (x1, z), (x0, z + PITCH), (x1, z + PITCH))):
            continue
        if rnd.random() < 0.03:
            continue
        Lb = x1 - x0 - 0.1
        if rnd.random() < 0.07:
            Lb *= rnd.uniform(0.6, 0.85)
        G.box((Lb, 0.36, PITCH - 0.1), ((x0 + x1) / 2, -10.68 + rnd.uniform(-0.05, 0.05), zc), rnd.choice(BRK),
              rot=(rnd.uniform(-1, 1), rnd.uniform(-0.8, 0.8), rnd.uniform(-1.2, 1.2)))
    for sx in (-1, 1):
        y = -10.5 - (0.75 if row % 2 else 0.0)
        while y < -7.5:
            y0, y1 = max(y, -10.5), min(y + 1.5, -7.5)
            y += 1.5
            if y1 - y0 < 0.4:
                continue
            G.box((0.36, y1 - y0 - 0.1, PITCH - 0.1), (sx * 14.18, (y0 + y1) / 2, zc), rnd.choice(BRK),
                  rot=(rnd.uniform(-1, 1), 0, rnd.uniform(-1, 1)))
            if zc < 9.6:
                G.box((0.36, y1 - y0 - 0.1, PITCH - 0.1), (sx * 9.85, (y0 + y1) / 2, zc), rnd.choice(BRK),
                      rot=(rnd.uniform(-1, 1), 0, rnd.uniform(-1, 1)))
    z += PITCH
    row += 1
for sx in (-1, 1):  # base course
    x = 10.1
    while x < 14:
        Lb = min(rnd.uniform(1.6, 2.3), 14 - x)
        G.box((Lb - 0.1, 0.55, 1.3), (sx * (x + Lb / 2), -10.78, 0.68), STONE, rot=(0, 0, rnd.uniform(-1, 1)))
        x += Lb
    G.box((0.55, 2.9, 1.3), (sx * 14.25, -9, 0.68), STONE)
G.box((29.4, 3.9, 0.55), (0, -9, 24.28), STONE)
for k in range(32):
    G.box((0.42, 0.32, 0.42), (-13.95 + k * 0.9, -11.0, 23.82), STONE)
for x in (-12.4, -7.4, -2.4, 2.4, 7.4, 12.4):
    G.box((2.6, 3.0, 1.8), (x, -9, 25.45), rnd.choice(BRK), rot=(0, 0, rnd.uniform(-1, 1)))
    G.box((2.9, 3.3, 0.3), (x, -9, 26.5), STONE)
for i in range(9):  # voussoirs
    a = 180.0 * i / 8
    key = i == 4
    rr = 10.9 if not key else 11.2
    p = (rr * math.cos(rad(a)), -10.75, 10 + rr * math.sin(rad(a)))
    G.box((2.4 if key else 1.8, 0.9, 4.0 if key else 3.6), p, STONE, rot=(rnd.uniform(-1, 1), -a + rnd.uniform(-1.5, 1.5), 0))
    G.box((1.5 if key else 1.0, 0.1, 3.0 if key else 2.6), (p[0], -11.22, p[2]), MATS["Stone_Dressed"], rot=(0, -a, 0))
G.torus(0.62, 0.12, (0, -11.3, 21.2), STONE, rot=(90, 0, 0), seg=20)  # carved eye on keystone
G.ball(0.36, (0, -11.25, 21.2), STONE, scale=(1, 0.5, 1))
PLQ = mat("Bronze_Plaque", (120, 84, 46), rough=0.4, metal=0.9, noise=2.0, dark=0.6)
G.box((6.6, 0.3, 1.25), (0, -10.72, 23.08), PLQ)
for k in range(4):
    G.box((6.9 if k < 2 else 0.18, 0.22, 0.16 if k < 2 else 1.5), (0 if k < 2 else (-3.4 if k == 2 else 3.4), -10.85,
          (23.68 if k == 0 else 22.48) if k < 2 else 23.08), GOLD)
for sx in (-1, 1):
    G.ball(0.12, (sx * 3.05, -10.95, 23.08), GOLD, seg=8)
text("PlaqueText", "CYCLOPS", (0, -10.92, 23.08), 0.95, GOLD, CG, extrude=0.07)

# portcullis
PC = Batch("Portcullis", CG, bevel=0.04)
for i in range(9):
    x = -9 + i * 2.25
    PC.box((0.5, 0.4, 20.2), (x, -9, 10.9), IRON)
    PC.cyl(0.3, 0.9, (x, -9, 0.42), IRON, rot=(180, 0, 0), r2=0.0, verts=6)
    for _ in range(rnd.randint(1, 3)):
        zz = rnd.uniform(2, 18)
        PC.box((0.3, 0.05, rnd.uniform(0.8, 2.5)), (x + rnd.uniform(-0.08, 0.08), -9.22, zz), RUST)
for z in (3, 6.5, 10, 13.5, 17):
    PC.box((19.6, 0.4, 0.55), (0, -9.35, z), IRON)
    PC.box((19.6, 0.4, 0.55), (0, -8.65, z), IRON)
    for i in range(9):
        PC.ball(0.2, (-9 + i * 2.25, -9.6, z), IRON, seg=8)
        PC.ball(0.2, (-9 + i * 2.25, -8.4, z), IRON, seg=8)
for i in range(8):
    PC.box_between((-9 + i * 2.25, -9.62, 3.0), (-9 + (i + 1) * 2.25, -9.62, 6.5), 0.22, 0.12, RUST, side=(0, -1, 0))

# lanterns
for sx in (-1, 1):
    lx = sx * 12
    G.box((1.2, 0.25, 1.6), (lx, -10.9, 16.6), IRON)
    G.cyl_between((lx, -10.9, 16.9), (lx, -11.9, 17.2), 0.12, IRON, verts=8)
    G.cyl_between((lx, -11.9, 17.2), (lx, -12.1, 16.6), 0.12, IRON, verts=8)
    G.torus(0.35, 0.07, (lx, -11.45, 16.55), IRON, rot=(0, 90, 0), seg=12, ring=6)
    G.lathe([(0, 0), (0.85, 0), (0.85, 0.2), (0.7, 0.3), (0, 0.3)], (lx, -12.0, 13.9), IRON, seg=4, rot=(0, 0, 45))
    for cx in (-0.6, 0.6):
        for cy in (-0.6, 0.6):
            G.box((0.14, 0.14, 1.9), (lx + cx, -12.0 + cy, 15.0), IRON)
    for (dx, dy, w, d) in ((0, -0.62, 1.1, 0.06), (0, 0.62, 1.1, 0.06), (-0.62, 0, 0.06, 1.1), (0.62, 0, 0.06, 1.1)):
        G.box((w, d, 1.6), (lx + dx, -12.0 + dy, 15.0), AMBER)
        G.box((w + 0.02 if w > 0.5 else 0.08, d + 0.02 if d > 0.5 else 0.08, 0.08), (lx + dx * 1.02, -12.0 + dy * 1.02, 15.0), IRON)
    G.lathe([(0, 0), (0.95, 0), (0, 0.8)], (lx, -12.0, 15.95), IRON, seg=4, rot=(0, 0, 45))
    G.torus(0.18, 0.05, (lx, -12.0, 17.0), IRON, rot=(90, 0, 0), seg=10, ring=6)
    G.cyl(0.2, 0.6, (lx, -12.0, 14.5), CANDLE, verts=10)
    light("LanternLight", "POINT", (lx, -13.3, 15.0), CG, 130, (236, 181, 68), radius=0.15)

# cell
box("PitFloor", (20, 17, 0.4), (0, 1, -0.2), SLATE, CG, bevel=0)
box("PitBack", (24, 1.5, 24), (0, 10.25, 12), SLATE, CG, bevel=0.1)
for sx in (-1, 1):
    box("PitSide", (2, 18, 24), (sx * 11, 1, 12), SLATE, CG, bevel=0.1)
CB = Batch("Cell_Masonry", CG, bevel=0.06)
for zr in range(16):
    zc = 0.75 + zr * 1.45
    if zc > 23.4:
        break
    x = -10 - (1.1 if zr % 2 else 0)
    while x < 10:
        x0, x1 = max(x, -10), min(x + rnd.uniform(1.8, 2.8), 10)
        x = x1
        if x1 - x0 > 0.5:
            CB.box((x1 - x0 - 0.1, 0.3, 1.35), ((x0 + x1) / 2, 9.4, zc), SLATE2, rot=(0, rnd.uniform(-1, 1), 0))
    for sx in (-1, 1):
        for face_x in (sx * 10.1, sx * 12.1):
            y = -7.5 - (1.1 if zr % 2 else 0)
            while y < 10:
                y0, y1 = max(y, -7.5), min(y + rnd.uniform(1.8, 2.8), 10)
                y = y1
                if y1 - y0 > 0.5:
                    CB.box((0.3, y1 - y0 - 0.1, 1.35), (face_x, (y0 + y1) / 2, zc), SLATE2, rot=(rnd.uniform(-1, 1), 0, 0))
for gx in range(10):
    for gy in range(8):
        CB.box((1.95 + rnd.uniform(-0.1, 0.05), 2.05 + rnd.uniform(-0.1, 0.05), 0.2),
               (-9 + gx * 2 + rnd.uniform(-0.05, 0.05), -6.5 + gy * 2.1, 0.05), SLATE2, rot=(0, 0, rnd.uniform(-1.5, 1.5)))
for sx in (-1, 1):  # manacles on back wall
    mx = sx * 4.5
    CB.box((0.9, 0.2, 0.9), (mx, 9.2, 10.5), IRON)
    CB.torus(0.35, 0.09, (mx, 9.0, 10.2), IRON, rot=(0, 90, 0), seg=12, ring=6)
    chain(CB, (mx, 8.95, 9.9), (mx + sx * 0.6, 8.6, 6.6), IRON)
    CB.torus(0.55, 0.15, (mx + sx * 0.6, 8.6, 6.2), IRON, rot=(70, 0, 0), seg=16, ring=6)
CB.box((0.6, 0.6, 0.3), (0, 9.15, 15.5), IRON)
CB.cyl_between((0, 9.0, 15.4), (0, 8.2, 16.6), 0.14, WOOD, verts=8)
CB.cyl(0.24, 0.5, (0, 8.15, 16.8), IRON, verts=8, r2=0.32)
flame(CB, (0, 8.15, 17.0), FLAME, FLAMEI, 0.8)
light("CellTorch", "POINT", (0, 7.6, 17.6), CG, 140, (255, 150, 70), radius=0.3)
straw(CB, (-6.5, 6.5, 0.1), 3.2, 260, STRAW, height=0.9)
straw(CB, (6.8, 7.2, 0.1), 2.2, 120, STRAW, height=0.6)
bone(CB, (-3.5, 4.0, 0.3), (-2.0, 5.2, 0.28), BONE)
bone(CB, (4.0, 3.0, 0.28), (5.4, 2.2, 0.3), BONE)
bone(CB, (-7.0, 1.0, 0.28), (-6.0, -0.4, 0.28), BONE, r=0.11)
skull(CB, (5.8, 5.0, 0.1), BONE, DARK, s=1.0, yaw=-25)
skull(CB, (-5.5, 7.6, 0.6), BONE, DARK, s=0.9, yaw=20)
CB.lathe([(0, 0), (0.75, 0), (0.85, 1.4), (0.8, 1.45), (0.7, 0.1), (0, 0.1)], (7.8, 2.0, 0.1), WOOD, seg=16)
for zz in (0.35, 1.1):
    CB.torus(0.83 if zz > 1 else 0.79, 0.05, (7.8, 2.0, zz + 0.1), IRON, seg=20, ring=6)
CB.cyl(0.74, 0.04, (7.8, 2.0, 1.3), WATER, verts=16)
for k in range(10):
    p, n = (rnd.uniform(-9.5, 9.5), 9.3, rnd.uniform(0.2, 2.0)), (0, -1, 0)
    moss(CB, p, n, MOSS, k=10)

# front yard
FY = Batch("Gate_Yard", CG, bevel=0.05)
box("SandFloor", (30, 16, 0.2), (0, -18.5, -0.1), SAND, CG, bevel=0)
for _ in range(140):
    FY.rock(rnd.uniform(0.08, 0.3), (rnd.uniform(-14.5, 14.5), rnd.uniform(-26, -11), 0.05), PEBBLE, scale=(1, 1, 0.6))
for _ in range(16):
    cx, cy = rnd.choice([(rnd.uniform(-14, -10.5), -11.2), (rnd.uniform(10.5, 14), -11.2), (rnd.uniform(-14, 14), rnd.uniform(-25, -12))])
    for _ in range(9):
        a = rnd.uniform(0, 2 * math.pi)
        FY.cyl_between((cx, cy, 0), (cx + math.cos(a) * 0.35, cy + math.sin(a) * 0.35, rnd.uniform(0.6, 1.3)),
                       0.07, GRASS, r2=0.0, verts=4)
amphora(FY, (-12.6, -13.0, 0), CLAY, DARK, s=1.0)
amphora(FY, (12.8, -12.6, 0), CLAY, DARK, s=0.8)
FY.lathe([(r, z) for r, z in AMPHORA[:9]], (9.5, -15.5, 0.75), CLAY, rot=(90, 0, 70), seg=18)
for _ in range(7):
    FY.prism([(0, 0), (rnd.uniform(0.3, 0.6), 0), (rnd.uniform(0.1, 0.5), rnd.uniform(0.3, 0.6))], 0.06,
             (rnd.uniform(9.8, 11.5), rnd.uniform(-17, -15), 0.05), CLAY, rot=(rnd.uniform(70, 110), 0, rnd.uniform(0, 180)))
FY.lathe([(0, 0), (1.4, 0), (1.4, 2.6), (0, 2.6)], (-8.5, -18.5, 1.4), STONE, rot=(90, 0, 25), seg=24)
for k in range(16):
    a = 2 * math.pi * k / 16
    q = Euler((rad(90), 0, rad(25))).to_matrix()
    FY.box((0.28, 2.65, 0.28), Vector((-8.5, -18.5, 1.4)) + q @ Vector((math.cos(a) * 1.38, math.sin(a) * 1.38, 1.3)) - q @ Vector((0, 0, 1.3)) + q @ Vector((0, 0, 1.3)) - q @ Vector((0, 0, 0)), DARK,
           quat=(Euler((rad(90), 0, rad(25))).to_quaternion() @ Euler((0, 0, a)).to_quaternion()))
FY.cyl(2.2, 0.03, (4.0, -20.0, 0.02), WATER, verts=24, scale=(1.4, 0.8, 1))
for b_ in (G, PC, CB, FY):
    b_.finish()

# ======================================================================= CYCLOPS boss
COLL = collection("Boss_Cyclops", MY)
B = boss_root("Boss_Cyclops", CG, (0, 1.5, 0), 1.0)
MARBLE = mat("Marble", (212, 200, 178), rough=0.4, noise=0.7, dark=0.8, bump=0.18, veins=(150, 140, 126))
SHADOW = mat("Marble_Shadow", (142, 128, 112), rough=0.55, noise=1.0, bump=0.25)
BEARD = mat("Marble_Beard", (176, 162, 140), rough=0.55, noise=2.0, bump=0.3, veins=(130, 120, 106))
SCLERA = mat("Eye_Sclera", (232, 222, 200), rough=0.3)
IRIS = mat("Cyclops_Iris", (236, 181, 68), emit=3.5)
BRONZE_P = mat("Bronze_Plate", (154, 107, 52), rough=0.35, metal=0.9, noise=1.5, bump=0.25)
CRACK = mat("Crack", (40, 34, 30), rough=0.95)
NAIL = mat("Marble_Nail", (190, 176, 150), rough=0.3)

J = humanoid("Cy_", B, MARBLE, head=False, disp=0.035, foot=MARBLE)
D = Detail("Cy_", J)
anatomy(D, MARBLE, bulk=1.15)
nk = J["Neck"]
organic("Cy_Skull", (3.2, 2.7, 3.3), (0, -0.5, 11.3), MARBLE, nk, bevel=0.9, levels=3, disp=0.03)
organic("Cy_Jaw", (2.9, 2.4, 1.4), (0, -0.9, 10.0), MARBLE, nk, bevel=0.55, levels=2, disp=0.02)
organic("Cy_BrowRidge", (2.9, 0.9, 0.6), (0, -1.55, 12.3), SHADOW, nk, rot=(-12, 0, 0), bevel=0.28, levels=2)
H = D["Neck"]
H.ball(1.1, (0, -1.55, 11.45), DARK, scale=(1, 0.6, 1), seg=20)
H.ball(0.85, (0, -1.85, 11.45), SCLERA, seg=24)
H.cyl(0.52, 0.12, (0, -2.66, 11.45), IRIS, rot=(90, 0, 0), verts=24)
H.torus(0.5, 0.05, (0, -2.7, 11.45), mat("Iris_Ring", (150, 96, 30), rough=0.4), rot=(90, 0, 0), seg=24, ring=6)
H.ball(0.2, (0, -2.72, 11.45), DARK, scale=(0.7, 0.4, 2.0), seg=12)
for k in range(10):
    a = 2 * math.pi * k / 10
    H.box((0.035, 0.03, 0.3), (math.cos(a) * 0.3, -2.73, 11.45 + math.sin(a) * 0.3), mat("Iris_Fiber", (190, 120, 40), emit=1.5),
          rot=(0, -math.degrees(a) + 90, 0))
H.ball(0.95, (0, -1.92, 12.05), MARBLE, scale=(1.08, 0.75, 0.45), seg=20)
H.ball(0.95, (0, -1.92, 10.88), MARBLE, scale=(1.05, 0.7, 0.35), seg=20)
H.torus(0.92, 0.13, (0, -2.18, 11.45), SHADOW, rot=(90, 0, 0), seg=28, ring=8)
H.box((0.6, 0.5, 1.0), (0, -2.15, 10.95), MARBLE, rot=(15, 0, 0))
H.ball(0.5, (0, -2.3, 10.55), MARBLE, scale=(1.15, 0.85, 0.95), seg=16)
for sx in (-1, 1):
    H.ball(0.14, (sx * 0.24, -2.65, 10.42), DARK, seg=8)
    H.ball(0.3, (sx * 0.42, -2.45, 10.5), MARBLE, seg=10)
    H.ball(0.6, (sx * 1.05, -1.85, 10.95), MARBLE, scale=(1, 0.6, 0.7), seg=16)
    H.ball(0.55, (sx * 1.72, -0.4, 11.3), MARBLE, scale=(0.45, 0.9, 1.3), seg=14)
    H.ball(0.3, (sx * 1.85, -0.45, 11.3), SHADOW, scale=(0.3, 0.6, 0.9), seg=10)
    H.ball(0.24, (sx * 1.75, -0.4, 10.65), MARBLE, seg=8)
    pts = [Vector((sx * 0.15, -2.35, 10.32)), Vector((sx * 0.6, -2.35, 10.15)), Vector((sx * 1.0, -2.2, 9.85)), Vector((sx * 1.2, -1.95, 9.5))]
    for (p, q), r in zip(zip(pts, pts[1:]), (0.22, 0.18, 0.13)):
        H.cyl_between(p, q, r, BEARD, r2=r * 0.8, verts=10)
        H.ball(r, q, BEARD, seg=8)
    H.cyl((0.12), 0.45, (sx * 0.6, -2.18, 9.95), BONE, r2=0.0, verts=8)  # tusks
H.torus(0.22, 0.05, (1.8, -0.4, 10.4), GOLD, rot=(0, 90, 0), seg=12, ring=6)
H.cyl_between((-0.65, -2.17, 10.05), (0.65, -2.17, 10.05), 0.15, MARBLE, verts=10)
H.cyl_between((-0.6, -2.12, 9.72), (0.6, -2.12, 9.72), 0.17, MARBLE, verts=10)
H.box((1.2, 0.1, 0.28), (0, -2.08, 9.88), DARK)
for k in range(6):
    H.box((0.17, 0.1, 0.22), (-0.45 + k * 0.18, -2.13, 9.9), BONE)
for z, n, rx, ry, r in ((9.7, 7, 1.6, 1.25, 0.38), (9.15, 6, 1.4, 1.3, 0.38), (8.6, 5, 1.15, 1.32, 0.36),
                        (8.1, 4, 0.9, 1.32, 0.34), (7.65, 3, 0.6, 1.3, 0.32), (7.25, 2, 0.32, 1.25, 0.28)):
    for i in range(n):
        t = rad(-68 + 136 * (i + 0.5) / n) if n > 1 else 0
        p = Vector((rx * math.sin(t), -1.0 - ry * math.cos(t), z))
        snail_curl(H, p, (math.sin(t), -math.cos(t), -0.15), BEARD, r=r)
for el, n_ring, front in ((22, 14, 62), (42, 13, 55), (60, 10, 40), (76, 6, 0)):
    for i in range(n_ring):
        az = 360.0 * i / n_ring + (15 if el > 50 else 0)
        azn = (az + 180) % 360 - 180
        if abs(azn) < front:
            continue
        p, n = ell_point((0, -0.45, 11.45), (1.72, 1.5, 1.78), rad(az), rad(el))
        snail_curl(H, p, n, BEARD, r=0.34)
for k in range(3):
    crack_ell(H, (0, -0.5, 11.3), (1.62, 1.37, 1.66), rnd.uniform(-60, 60) + 180 * (k == 2), rnd.uniform(10, 45), CRACK)
for s, sx in SIDES:
    fingers(D, s, sx, MARBLE, NAIL)
    toes(D, s, sx, MARBLE, NAIL)
    crack_ell(D["Spine"], (sx * 1.35, -1.42, 9.3), (1.5, 0.57, 1.08), rnd.uniform(-30, 30), rnd.uniform(-20, 30), CRACK)
    crack_ell(D["Shoulder" + s], (sx * 3.62, 0, 9.35), (1.45, 1.48, 1.13), rnd.uniform(-40, 40), 30, CRACK)
    crack_ell(D["Hip" + s], (sx * 1.1, -0.7, 3.9), (0.95, 0.62, 1.4), rnd.uniform(-20, 20), rnd.uniform(0, 30), CRACK, steps=5)
    for z in (4.4, 4.75, 5.1):
        D["Elbow" + s].torus(1.04, 0.12, (sx * 3.6, -0.05, z), LEATHER, seg=18, ring=6)
    moss(D["Shoulder" + s], (sx * 3.62, 0, 10.45), (0, 0, 1), MOSS, k=16, spread=0.4)
    moss(D["Knee" + s], (sx * 1.1, -1.3, 0.95), (0, -0.5, 1), MOSS, k=8, spread=0.3)
crack_ell(D["Spine"], (0, 0, 8.4), (2.95, 1.6, 2.2), 170, 20, CRACK, steps=9)
crack_ell(D["Spine"], (0, 0, 8.4), (2.95, 1.6, 2.2), 200, -10, CRACK, steps=8)
hp = D["Hips"]
hp.box((3.95, 2.85, 0.75), (0, 0, 4.85), LEATHER)
for k in range(16):
    a = 2 * math.pi * k / 16
    hp.ball(0.11, (math.cos(a) * 2.0, math.sin(a) * 1.45, 4.85), BRONZE_P, seg=6)
hp.box((1.05, 0.2, 0.95), (0, -1.5, 4.85), BRONZE_P)
hp.box((0.65, 0.12, 0.55), (0, -1.62, 4.85), DARK)
hp.box((0.1, 0.12, 0.7), (0, -1.66, 4.85), BRONZE_P)
for i in range(5):
    x = -2.0 + i * 1.0
    ry = -x * 4
    hp.box((0.9, 0.22, 2.6), (x, -1.48, 3.35), BRONZE_P, rot=(0, ry, 0))
    for dz in (1.1, -1.1):
        hp.box((0.8, 0.06, 0.1), (x, -1.62, 3.35 + dz), GOLD, rot=(0, ry, 0))
    hp.ball(0.1, (x, -1.62, 4.2), GOLD, seg=6)
    hp.ball(0.1, (x, -1.62, 2.55), GOLD, seg=6)
    hp.box((0.3, 0.06, 0.3), (x, -1.62, 3.3), BRONZE_P, rot=(0, 45, 0))
    hp.cyl(0.12, 0.35, (x, -1.48, 1.9), CLOTH, r2=0.0, verts=6, rot=(180, 0, 0))
for sx in (-1, 1):
    for y in (-0.6, 0.6):
        hp.box((0.22, 0.9, 2.4), (sx * 2.05, y, 3.45), BRONZE_P)
for i in range(3):
    hp.box((0.9, 0.22, 2.4), (-1.0 + i * 1.0, 1.48, 3.45), BRONZE_P)
organic("Cy_Loincloth", (3.6, 2.6, 2.3), (0, 0, 3.85), CLOTH, J["Hips"], bevel=0.5, levels=2)
kr = D["KneeR"]
kr.torus(1.05, 0.26, (-1.1, 0, 1.05), IRON, seg=24, ring=8)
kr.box((0.45, 0.4, 0.75), (-2.15, 0, 1.05), IRON)
kr.box((0.65, 0.35, 0.75), (-1.1, -1.3, 1.0), IRON)
kr.box((0.12, 0.05, 0.3), (-1.1, -1.48, 1.0), DARK)
for dz in (0.8, 1.3):
    kr.ball(0.08, (-1.35, -1.3, dz), IRON, seg=6)
    kr.ball(0.08, (-0.85, -1.3, dz), IRON, seg=6)
pose(J, Spine=(18, 0, 0), Neck=(-16, 0, 0), Hips=(4, 0, 0),
     ShoulderR=(-16, 8, 0), ShoulderL=(-16, -8, 0), ElbowR=(-8, 0, 0), ElbowL=(-12, 0, 0),
     HipR=(-6, 0, 0), HipL=(-6, 0, 0), KneeR=(8, 0, 0), KneeL=(8, 0, 0))
chain(D["KneeR"], (-2.3, -0.1, 0.85), (-3.0, -0.9, 0.14), IRON, R=0.38, r=0.11, link=0.72)
D["KneeR"].torus(0.38, 0.11, (-3.15, -1.15, 0.12), IRON, rot=(0, 0, 30), arc=250, seg=12, ring=6)
CX = Batch("Cell_Anchor", CG, bevel=0.04)  # the anchor stays in the cell; rubble round the boss's spot
CX.box((1.4, 1.4, 0.25), (-6.6, 7.9, 0.12), IRON)
CX.torus(0.45, 0.12, (-6.6, 7.9, 0.4), IRON, rot=(90, 0, 0), seg=14, ring=6)
chain(CX, (-6.6, 7.6, 0.3), (-5.2, 5.6, 0.12), IRON, R=0.38, r=0.11, link=0.72)
for dx in (-0.5, 0.5):
    for dy in (-0.5, 0.5):
        CX.ball(0.1, (-6.6 + dx, 7.9 + dy, 0.27), IRON, seg=6)
for _ in range(26):
    CX.rock(rnd.uniform(0.15, 0.5), (rnd.uniform(-7, 7), rnd.uniform(-2.5, 6.5), 0.1), MARBLE, scale=(1, 1, 0.7))
COLL = bpy.data.collections["Cage_Cyclops"]
CX.finish()
COLL = bpy.data.collections["Boss_Cyclops"]
D.finish()

# ======================================================================= MINOTAUR labyrinth box (x = 0)
COLL = collection("Cage_Minotaur", MY)
CM = cage_root("Cage_Minotaur", 0)
LIME = mat("Limestone", (94, 90, 82), rough=0.88, noise=0.9, dark=0.72, bump=0.45)
LIME2 = mat("Limestone_Light", (122, 116, 104), rough=0.85, noise=1.2, dark=0.75, bump=0.45)
LATT = mat("Iron_Lattice", (35, 39, 43), rough=0.55, metal=0.8, noise=1.5, dark=0.65, bump=0.2)
INLAY = mat("Bronze_Inlay", (176, 136, 64), rough=0.35, metal=1.0, noise=2.0, dark=0.7)
K = Batch("Lab_Plinth", CM, bevel=0.1)
K.box((26, 25, 0.6), (0, 0, 0.3), LIME)
K.box((24.8, 23.8, 0.6), (0, 0, 0.9), LIME)
K.box((23, 22, 2.8), (0, 0, 2.6), LIME)
K.box((23.6, 22.6, 0.5), (0, 0, 4.0), LIME2)
for sx in (-1, 1):
    for sy in (-1, 1):
        K.box((1.7, 1.7, 2.6), (sx * 11.3, sy * 10.8, 2.5), LIME2)
        K.box((2.1, 2.1, 0.3), (sx * 11.3, sy * 10.8, 3.65), LIME2)
        K.box((2.1, 2.1, 0.3), (sx * 11.3, sy * 10.8, 1.35), LIME2)
        for k in range(4):
            K.box((0.18, 0.1, 2.0), (sx * 11.3 + (k - 1.5) * 0.36, sy * 10.8 + sy * 0.88, 2.5), LIME)
KM = Batch("Lab_Meander", CM, bevel=0.02)
meander(KM, (-10.4, -11.0, 0), (1, 0, 0), (0, -1, 0), 20.8, GOLD, z0=1.75, h=1.5)
meander(KM, (-11.5, 10.0, 0), (0, -1, 0), (-1, 0, 0), 20.0, GOLD, z0=1.75, h=1.5)
meander(KM, (11.5, -10.0, 0), (0, 1, 0), (1, 0, 0), 20.0, GOLD, z0=1.75, h=1.5)
for _ in range(6):
    crack_plane(KM, (0, -11.03, 0), (1, 0, 0), (0, 0, 1), (0, -1, 0), rnd.uniform(-10, 10), rnd.uniform(1.4, 3.8), CRACK, steps=6, step=0.4)
for _ in range(14):
    sx, sy = rnd.choice((-1, 1)), rnd.choice((-1, 1))
    moss(KM, (sx * rnd.uniform(9, 12.4), sy * rnd.uniform(9, 11.9), 0.62), (0, 0, 1), MOSS, k=14, spread=0.5)
for _ in range(24):
    KM.rock(rnd.uniform(0.15, 0.45), (rnd.uniform(-13, 13), rnd.choice((-1, 1)) * rnd.uniform(12.4, 13.5), 0.1), LIME)
# labyrinth inlay on the cage floor
NM, CS = 10, 1.9
walls = {(x, y, d) for x in range(NM) for y in range(NM) for d in "ES"}
seen, stack = {(0, 0)}, [(0, 0)]
while stack:
    cx, cy = stack[-1]
    nbr = [(cx + dx, cy + dy, dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
           if 0 <= cx + dx < NM and 0 <= cy + dy < NM and (cx + dx, cy + dy) not in seen]
    if not nbr:
        stack.pop()
        continue
    nx, ny, dx, dy = rnd.choice(nbr)
    if dx == 1: walls.discard((cx, cy, "E"))
    if dx == -1: walls.discard((nx, ny, "E"))
    if dy == 1: walls.discard((cx, cy, "S"))
    if dy == -1: walls.discard((nx, ny, "S"))
    seen.add((nx, ny))
    stack.append((nx, ny))
o = -NM * CS / 2
for (x, y, d) in walls:
    if d == "E" and x < NM - 1:
        KM.box((0.16, CS + 0.16, 0.1), (o + (x + 1) * CS, o + (y + 0.5) * CS, 4.3), INLAY)
    if d == "S" and y < NM - 1:
        KM.box((CS + 0.16, 0.16, 0.1), (o + (x + 0.5) * CS, o + (y + 1) * CS, 4.3), INLAY)
for k in range(4):
    a = (k % 2 == 0)
    KM.box((NM * CS + 0.16 if a else 0.16, 0.16 if a else NM * CS + 0.16, 0.1),
           (0 if a else (o if k == 1 else -o), (o if k == 0 else -o) if a else 0, 4.3), INLAY)

XL, YL, Z0, H = 10.5, 10.0, 4.25, 15.0
LT = Batch("Lab_Lattice", CM, bevel=0.035)
LG = Batch("Lab_Gate", CM, bevel=0.035)  # the front face: sinks into the plinth when the Minotaur is released
for face in ("front", "back", "left", "right"):
    if face in ("front", "back"):
        y = -YL if face == "front" else YL
        FB = LG if face == "front" else LT
        for k in range(12):
            x = -9.9 + k * 1.8
            if face == "front" and abs(x) < 3.2:
                continue
            FB.box((0.5, 0.35, H), (x, y, Z0 + H / 2), LATT)
        for k in range(1, 9):
            yy = y + (-0.3 if y < 0 else 0.3)
            FB.box((2 * XL, 0.35, 0.5), (0, yy, Z0 + k * 1.8), LATT)
            for j in range(12):
                FB.ball(0.16, (-9.9 + j * 1.8, yy + (-0.22 if y < 0 else 0.22), Z0 + k * 1.8), LATT, seg=8)
    else:
        x = -XL if face == "left" else XL
        for k in range(12):
            yy = -9.9 + k * 1.8
            if abs(yy) < YL:
                LT.box((0.35, 0.5, H), (x, yy, Z0 + H / 2), LATT)
        for k in range(1, 9):
            xx = x + (-0.3 if x < 0 else 0.3)
            LT.box((0.35, 2 * YL, 0.5), (xx, 0, Z0 + k * 1.8), LATT)
            for j in range(11):
                LT.ball(0.16, (xx + (-0.22 if x < 0 else 0.22), -9.0 + j * 1.8, Z0 + k * 1.8), LATT, seg=8)
for sx in (-1, 1):  # door
    LG.box((0.8, 0.6, H), (sx * 3.2, -YL - 0.1, Z0 + H / 2), LATT)
    LG.box((0.4, 0.35, H - 3), (sx * 1.15, -YL - 0.5, Z0 + (H - 3) / 2), LATT)
    for zz in (Z0 + 2, Z0 + 6.5, Z0 + 11):
        LG.cyl(0.28, 0.9, (-3.2, -YL - 0.55, zz), LATT, verts=10)
        LG.box((2.2, 0.15, 0.4), (-2.2, -YL - 0.6, zz), LATT)
for k in range(1, 7):
    LG.box((6.4, 0.3, 0.45), (0, -YL - 0.45, Z0 + k * 1.75), LATT)
    for j in range(4):
        LG.ball(0.15, (-2.3 + j * 1.53, -YL - 0.65, Z0 + k * 1.75), LATT, seg=8)
LG.box((1.2, 0.5, 1.3), (0.6, -YL - 1.1, Z0 + 6.2), GOLD)
LG.torus(0.42, 0.11, (0.6, -YL - 1.1, Z0 + 6.9), LATT, rot=(90, 0, 0), arc=180, seg=12, ring=6)
LG.box((0.12, 0.05, 0.35), (0.6, -YL - 1.37, Z0 + 6.05), DARK)
LG.box((0.9, 0.12, 0.25), (0.6, -YL - 0.7, Z0 + 6.85), LATT)
for sx in (-1, 1):
    for sy in (-1, 1):
        LT.box((1.2, 1.2, H + 1.0), (sx * XL, sy * YL, Z0 + H / 2 + 0.2), LATT)
        LT.lathe([(0, 0), (0.75, 0), (0.75, 0.2), (0.5, 0.35), (0.62, 0.7), (0.3, 1.0), (0, 1.6)],
                 (sx * XL, sy * YL, Z0 + H + 0.7), LATT, seg=12)
        sag_chain(LT, (sx * XL, sy * YL, Z0 + H + 1.6), (sx * 9.0, 0, 25.3), IRON, sag=0.0, segs=1)
        LT.torus(0.5, 0.12, (sx * 9.0, 0, 25.0), IRON, rot=(90, 0, 0), seg=14, ring=6)
for (w, d, pos) in (((2 * XL + 1.2, 1.0, 0.8), None, (0, -YL, Z0 + H)), ((2 * XL + 1.2, 1.0, 0.8), None, (0, YL, Z0 + H)),
                    ((1.0, 2 * YL, 0.8), None, (-XL, 0, Z0 + H)), ((1.0, 2 * YL, 0.8), None, (XL, 0, Z0 + H))):
    LT.box(w, pos, LATT)
for k in range(-2, 3):
    LT.box((0.5, 2 * YL, 0.35), (k * 3.6, 0, Z0 + H), LATT)
for k in range(23):
    for y in (-YL, YL):
        LT.cyl(0.18, 0.9, (-10.0 + k * 0.91, y, Z0 + H + 0.8), LATT, r2=0.0, verts=6)
for k in range(21):
    for x in (-XL, XL):
        LT.cyl(0.18, 0.9, (x, -9.1 + k * 0.91, Z0 + H + 0.8), LATT, r2=0.0, verts=6)
# gantry
LT.box((28.5, 1.4, 0.35), (0, 0, 26.55), LATT)
LT.box((28.5, 1.4, 0.35), (0, 0, 25.45), LATT)
LT.box((28.5, 0.5, 0.8), (0, 0, 26.0), LATT)
for k in range(19):
    LT.ball(0.14, (-13.5 + k * 1.5, -0.3, 26.0), LATT, seg=6)
for sx in (-1, 1):
    LT.box((1.4, 1.4, 26.7), (sx * 13.6, 0, 13.35), LATT)
    K.box((2.6, 2.6, 1.0), (sx * 13.6, 0, 0.5), LIME2)
    LT.box_between((sx * 13.6, 0, 20.0), (sx * 9.6, 0, 25.4), 0.6, 0.6, LATT, side=(0, -1, 0))
    for zz in range(2, 26, 4):
        LT.box((1.7, 1.7, 0.35), (sx * 13.6, 0, zz), LATT)
    # banners
    LT.box((0.3, 1.6, 0.3), (sx * 13.6, -1.4, 23.0), LATT)
    LT.cyl_between((sx * 13.6 - 1.7, -2.3, 23.0), (sx * 13.6 + 1.7, -2.3, 23.0), 0.1, WOOD, verts=8)
    LT.box((3.0, 0.12, 8.0), (sx * 13.6, -2.3, 18.9), CLOTH)
    for dz in (22.6, 15.2):
        LT.box((3.0, 0.16, 0.25), (sx * 13.6, -2.32, dz), GOLD)
    meander(LT, (sx * 13.6 - 1.4, -2.3, 0), (1, 0, 0), (0, -1, 0), 2.8, GOLD, z0=15.6, h=0.7, unit=1.4, w=0.1)
    LT.cyl(0.8, 0.1, (sx * 13.6, -2.4, 19.6), GOLD, rot=(90, 0, 0), verts=20)
    for hx in (-1, 1):
        LT.cyl_between((sx * 13.6 + hx * 0.5, -2.45, 20.0), (sx * 13.6 + hx * 1.0, -2.45, 20.9), 0.12, GOLD, r2=0.03, verts=6)
    for k in range(5):
        LT.cyl((0.16), 0.6, (sx * 13.6 - 1.2 + k * 0.6, -2.3, 14.65), GOLD, r2=0.0, verts=6, rot=(180, 0, 0))
LT.torus(1.2, 0.18, (0, 0, 24.3), LATT, rot=(90, 0, 0), seg=24, ring=6)
for k in range(6):
    a = k * math.pi / 3
    LT.cyl_between((0, 0, 24.3), (math.cos(a) * 1.15, 0, 24.3 + math.sin(a) * 1.15), 0.08, LATT, verts=6)
LT.cyl(0.3, 0.6, (0, 0, 24.3), LATT, rot=(90, 0, 0), verts=12)
LT.box((0.4, 0.8, 1.0), (0, 0, 25.2), LATT)
# braziers
for sx in (-1, 1):
    bx, by = sx * 15.5, -14.5
    for k in range(3):
        a = 2 * math.pi * k / 3
        LT.cyl_between((bx + math.cos(a) * 1.3, by + math.sin(a) * 1.3, 0), (bx + math.cos(a) * 0.5, by + math.sin(a) * 0.5, 3.4), 0.13, IRON, verts=8)
    LT.lathe([(0, 0), (0.6, 0), (1.5, 0.7), (1.6, 0.9), (1.45, 0.9), (0.6, 0.15), (0, 0.15)], (bx, by, 3.3), IRON, seg=20)
    for _ in range(26):
        a, d = rnd.uniform(0, 2 * math.pi), rnd.uniform(0, 1.2)
        LT.rock(rnd.uniform(0.12, 0.25), (bx + math.cos(a) * d, by + math.sin(a) * d, 4.0), rnd.choice((COALH, COAL, COALH)))
    flame(LT, (bx, by, 4.05), FLAME, FLAMEI, 1.5)
    light("BrazierLight", "POINT", (bx, by, 6.0), CM, 260, (255, 140, 60), radius=0.6)
straw(LT, (-6.5, 6.5, 4.3), 2.6, 160, STRAW, height=0.6)
bone(LT, (5.0, -5.0, 4.45), (6.6, -4.0, 4.45), BONE)
skull(LT, (-6.0, -6.0, 4.3), BONE, DARK, s=1.0, yaw=35)
bone(LT, (6.5, 6.0, 4.45), (7.6, 4.6, 4.45), BONE, r=0.11)
light("LabKey", "AREA", (0, -14, 24), CM, 380, (255, 226, 196), rot=(40, 0, 0), size=8)
light("LabInside", "POINT", (0, -6, 15), CM, 240, (255, 200, 160), radius=1.0)
light("LabTop", "AREA", (0, 0, 22), CM, 300, (255, 230, 210), size=10)
for b_ in (K, KM, LT, LG):
    b_.finish()

# ======================================================================= MINOTAUR boss
COLL = collection("Boss_Minotaur", MY)
B = boss_root("Boss_Minotaur", CM, (0, 0, 4.5), 0.85)
MBRZ = mat("Bronze_Dark", (78, 90, 82), rough=0.42, metal=0.75, noise=1.0, dark=0.6, bump=0.3)
ARMOR = mat("Bronze_Armor", (150, 108, 58), rough=0.32, metal=0.92, noise=1.6, dark=0.65, bump=0.2)
PATINA = mat("Patina", (111, 156, 138), rough=0.85, noise=3.0, dark=0.75, bump=0.3)
SCRATCH = mat("Bronze_Scratch", (205, 168, 110), rough=0.2, metal=1.0)
MUZZ = mat("Muzzle", (106, 120, 110), rough=0.5, metal=0.6, noise=1.5, bump=0.3)
NOSEP = mat("Muzzle_Dark", (62, 70, 64), rough=0.35, metal=0.5)
FUR = mat("Fur", (50, 59, 54), rough=1.0, noise=4.0, dark=0.55)
FUR2 = mat("Fur_Dark", (34, 38, 35), rough=1.0, noise=4.0, dark=0.6)
HOOF = mat("Hoof", (40, 36, 32), rough=0.3, noise=2.0, dark=0.7)
EMBER = mat("Ember_Neon", (234, 108, 73), emit=12.0)
HORN = mat("Horn_Bone", (196, 182, 156), rough=0.45, noise=2.0, dark=0.75, bump=0.2)
HORNG = mat("Horn_Groove", (120, 108, 90), rough=0.6)

J = humanoid("Mi_", B, MBRZ, head=False, disp=0.02, foot=False)
D = Detail("Mi_", J)
anatomy(D, MBRZ, bulk=1.2)
sp = D["Spine"]
sp.ball(2.3, (0, 0.45, 10.3), MBRZ, scale=(1.3, 0.9, 0.75), seg=24)
nk = J["Neck"]
organic("Mi_Skull", (3.1, 2.8, 3.0), (0, -0.5, 11.5), MBRZ, nk, bevel=0.9, levels=3, disp=0.02)
organic("Mi_Muzzle", (2.6, 2.4, 2.2), (0, -1.85, 10.45), MUZZ, nk, rot=(-10, 0, 0), bevel=0.75, levels=3)
organic("Mi_Jaw", (2.2, 2.0, 0.8), (0, -1.65, 9.3), MUZZ, nk, bevel=0.35, levels=2)
H = D["Neck"]
H.ball(0.9, (0, -2.95, 10.55), NOSEP, scale=(1.4, 0.5, 0.8), seg=20)
for sx in (-1, 1):
    H.torus(0.27, 0.09, (sx * 0.45, -3.33, 10.6), NOSEP, rot=(90, 0, 0), seg=14, ring=6)
    H.ball(0.21, (sx * 0.45, -3.3, 10.6), DARK, seg=8)
    H.ball(0.7, (sx * 0.85, -1.95, 12.15), MBRZ, scale=(1.2, 0.7, 0.5), rot=(0, 0, sx * 15), seg=16)
    H.ball(0.32, (sx * 0.95, -1.98, 11.75), EMBER, seg=12)
    H.ball(0.4, (sx * 0.95, -1.9, 11.95), MBRZ, scale=(1.2, 0.8, 0.4), seg=10)
    H.cyl_between((sx * 1.5, -0.2, 11.9), (sx * 2.8, 0.05, 11.55), 0.45, MBRZ, r2=0.12, verts=12)
    H.ball(0.3, (sx * 2.15, -0.25, 11.75), FUR2, scale=(1.6, 0.4, 0.7), seg=10)
    H.box((0.5, 0.08, 0.06), (sx * 0.95, -3.0, 9.8), DARK, rot=(0, 0, sx * -15))
H.torus(0.5, 0.11, (0, -3.42, 10.0), GOLD, rot=(90, 0, 0), seg=20, ring=8)
H.ball(0.14, (0, -3.42, 9.5), GOLD, seg=8)
H.torus(0.25, 0.06, (2.6, 0.05, 11.3), GOLD, rot=(0, 90, 0), seg=12, ring=6)
H.box((2.0, 0.1, 0.1), (0, -2.85, 9.75), DARK)
zig = [(0, 11.95), (0.22, 12.25), (-0.15, 12.5), (0.2, 12.8), (-0.1, 13.05), (0.12, 13.25)]
for (x1, z1), (x2, z2) in zip(zig, zig[1:]):
    H.box_between((x1, -1.95, z1), (x2, -1.95, z2), 0.16, 0.1, EMBER, side=(0, -1, 0), extend=0.12)
H.box_between((0.22, -1.93, 12.25), (0.6, -1.88, 12.4), 0.09, 0.08, EMBER, side=(0, -1, 0))
H.box_between((-0.15, -1.93, 12.5), (-0.55, -1.86, 12.62), 0.09, 0.08, EMBER, side=(0, -1, 0))
light("Mi_CrackGlow", "POINT", (0, -2.8, 12.4), nk, 40, (234, 108, 73), radius=0.2)
light("Mi_EyeGlow", "POINT", (0, -3.0, 11.8), nk, 25, (234, 108, 73), radius=0.2)
for sx in (-1, 1):
    p0, p1, p2 = Vector((sx * 1.45, -0.5, 12.6)), Vector((sx * 3.8, -0.2, 13.2)), Vector((sx * 4.1, -2.3, 14.7))
    pts = [(1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t * t * p2 for t in [i / 12 for i in range(13)]]
    for i, (a, c) in enumerate(zip(pts, pts[1:])):
        r1 = 0.62 * (1 - i / 12) + 0.05
        r2 = 0.62 * (1 - (i + 1) / 12) + 0.05
        m = GOLD if i >= 9 else HORN
        H.cyl_between(a, c, r1, m, r2=r2, verts=14)
        if i < 9 and i % 3 == 1:
            q = Vector((0, 0, 1)).rotation_difference(c - a)
            H.torus(r1 * 0.97, 0.03, a, HORNG, quat=q, seg=14, ring=5)
        else:
            q = Vector((0, 0, 1)).rotation_difference(c - a)
            H.torus(r1 * 1.05, 0.05, a, GOLD, quat=q, seg=14, ring=5)
    H.ball(0.07, pts[-1], GOLD, seg=8)
    for k in range(10):
        a = 2 * math.pi * k / 10
        nrm = Vector((sx * 0.6, math.cos(a), math.sin(a))).normalized()
        tuft(H, p0 + nrm * 0.45, nrm, rnd.uniform(0.5, 0.8), 0.2, FUR, droop=0.3)
for _ in range(55):
    az, el = rnd.uniform(95, 265), rnd.uniform(-5, 70)
    p, n = ell_point((0, -0.5, 11.5), (1.6, 1.45, 1.55), rad(az), rad(el))
    tuft(H, p, n, rnd.uniform(0.6, 1.1), rnd.uniform(0.2, 0.3), rnd.choice((FUR, FUR2)))
for _ in range(22):
    az, el = rnd.uniform(-35, 35), rnd.uniform(48, 85)
    p, n = ell_point((0, -0.5, 11.5), (1.6, 1.45, 1.55), rad(az), rad(el))
    tuft(H, p, n, rnd.uniform(0.6, 1.0), 0.22, FUR, droop=0.55)
for _ in range(150):
    az, el = rnd.uniform(70, 290), rnd.uniform(5, 80)
    p, n = ell_point((0, 0.45, 10.3), (2.95, 2.0, 1.7), rad(az), rad(el))
    tuft(sp, p, n, rnd.uniform(0.7, 1.3), rnd.uniform(0.22, 0.32), rnd.choice((FUR, FUR2, FUR)))
for _ in range(40):
    az, el = rnd.uniform(-60, 60), rnd.uniform(25, 75)
    p, n = ell_point((0, -0.4, 9.9), (2.2, 1.6, 1.2), rad(az), rad(el))
    tuft(sp, p, n, rnd.uniform(0.6, 1.0), 0.22, FUR, droop=0.6)
for s, sx in SIDES:
    shb = D["Shoulder" + s]
    for _ in range(22):
        az, el = rnd.uniform(-180, 180), rnd.uniform(35, 85)
        p, n = ell_point((sx * 3.62, 0, 9.35), (1.45, 1.48, 1.13), rad(az), rad(el))
        tuft(shb, p, n, rnd.uniform(0.5, 0.9), 0.22, FUR)
    el_ = D["Elbow" + s]
    for k in range(14):
        a = 2 * math.pi * k / 14
        n = Vector((math.cos(a), math.sin(a), 0))
        tuft(el_, Vector((sx * 3.6, 0, 4.25)) + n * 1.0, n, rnd.uniform(0.5, 0.8), 0.2, FUR, droop=0.7)
    kn_ = D["Knee" + s]
    for k in range(14):
        a = 2 * math.pi * k / 14
        n = Vector((math.cos(a), math.sin(a), 0))
        tuft(kn_, Vector((sx * 1.1, 0, 1.15)) + n * 0.85, n, rnd.uniform(0.5, 0.75), 0.2, FUR2, droop=0.8)
    for dx in (-0.47, 0.47):
        kn_.box((0.85, 2.4, 0.95), (sx * 1.1 + dx, -0.4, 0.48), HOOF)
        kn_.ball(0.42, (sx * 1.1 + dx, -1.55, 0.45), HOOF, scale=(1, 0.8, 1), seg=12)
    kn_.box((0.08, 2.6, 0.7), (sx * 1.1, -0.45, 0.45), DARK)
    fingers(D, s, sx, MBRZ, HOOF)
    eb = D["Elbow" + s]
    eb.cyl(1.08, 1.8, (sx * 3.6, -0.1, 5.25), ARMOR, verts=16)
    for zz in (4.45, 6.05):
        eb.torus(1.12, 0.1, (sx * 3.6, -0.1, zz), GOLD, seg=20, ring=6)
    for k in range(8):
        a = 2 * math.pi * k / 8
        eb.ball(0.09, (sx * 3.6 + math.cos(a) * 1.1, -0.1 + math.sin(a) * 1.1, 5.25), GOLD, seg=6)
    eb.cyl_between((sx * 3.6 + sx * 1.05, -0.1, 5.25), (sx * 3.6 + sx * 1.75, -0.1, 5.45), 0.22, ARMOR, r2=0.0, verts=8)
    eb.torus(1.22, 0.24, (sx * 3.6, 0, 4.0), IRON, seg=22, ring=8)
    eb.box((0.4, 0.5, 0.6), (sx * 3.6 + sx * 1.3, 0, 4.0), IRON)
    chain(eb, (sx * 3.6 + sx * 1.35, -0.2, 3.7), (sx * 3.6 + sx * 1.7, -0.7, 1.8), IRON)
    eb.torus(0.32, 0.09, (sx * 3.6 + sx * 1.75, -0.75, 1.55), IRON, rot=(0, 90, 30), arc=260, seg=12, ring=6)
    D["Knee" + s].box((1.7, 0.5, 1.2), (sx * 1.1, -0.95, 2.6), ARMOR)
    for dx in (-0.6, 0.6):
        D["Knee" + s].ball(0.09, (sx * 1.1 + dx, -1.22, 2.6), GOLD, seg=6)
shL = D["ShoulderL"]
shL.ball(1.75, (3.6, 0, 9.75), ARMOR, scale=(1.05, 1.05, 0.6), seg=24)
shL.torus(1.75, 0.12, (3.6, 0, 9.6), GOLD, seg=28, ring=6)
for k in range(3):
    shL.cyl_between((3.0 + k * 0.6, -0.3 + k * 0.3, 10.6), (3.2 + k * 0.85, -0.2 + k * 0.3, 11.9 - k * 0.2), 0.28, ARMOR, r2=0.0, verts=10)
for k in range(8):
    a = 2 * math.pi * k / 8
    shL.ball(0.1, (3.6 + math.cos(a) * 1.5, math.sin(a) * 1.5, 10.0), GOLD, seg=6)
for (a, c) in (((2.4, -2.0, 10.0), (0.0, -2.08, 8.4)), ((0.0, -2.08, 8.4), (-1.8, -1.68, 6.6))):
    sp.box_between(a, c, 0.6, 0.2, LEATHER, side=(0, -1, 0), extend=0.3)
    for t in (0.25, 0.5, 0.75):
        sp.ball(0.09, Vector(a).lerp(Vector(c), t) + Vector((0, -0.12, 0)), GOLD, seg=6)
sp.torus(0.35, 0.08, (0.0, -2.2, 8.4), GOLD, rot=(90, 0, 0), seg=12, ring=6)
for _ in range(26):
    az, el = rnd.uniform(-60, 60), rnd.uniform(-10, 45)
    a_, e_ = rad(az), rad(el)
    w = rnd.uniform(0.18, 0.26)
    p, n = ell_point((0, 0, 8.4), (2.95, 1.62, 2.2), a_, e_)
    for k in range(3):
        e2 = e_ - 0.12 * (k + 1)
        q, nq = ell_point((0, 0, 8.4), (2.95, 1.62, 2.2), a_ + rnd.uniform(-0.02, 0.02), e2)
        sp.box_between(p, q, w, 0.1, PATINA, side=n, extend=w * 0.5)
        p, n, w = q, nq, w * 0.8
    sp.ball(w * 0.8, p, PATINA, seg=6)
for _ in range(24):
    az, el = rnd.uniform(-70, 70), rnd.uniform(-15, 50)
    p, n = ell_point((0, 0, 8.4), (2.95, 1.62, 2.2), rad(az), rad(el))
    t = n.orthogonal().normalized()
    t = Quaternion(n, rnd.uniform(0, math.pi)) @ t
    sp.box_between(p - t * 0.35, p + t * 0.35, 0.05, 0.1, SCRATCH, side=n)
hp = D["Hips"]
hp.box((4.0, 2.95, 0.95), (0, 0, 4.9), LEATHER)
hp.cyl(0.62, 0.2, (0, -1.55, 4.9), GOLD, rot=(90, 0, 0), verts=20)
hp.ball(0.35, (0, -1.68, 4.85), GOLD, scale=(1, 0.5, 1.2), seg=12)
for hx in (-1, 1):
    hp.cyl_between((hx * 0.35, -1.7, 5.1), (hx * 0.85, -1.75, 5.5), 0.1, GOLD, r2=0.03, verts=6)
cyl_ob = organic("Mi_Kilt", (4.2, 3.2, 2.2), (0, 0, 3.9), FUR, J["Hips"], bevel=0.8, levels=2)
for ring_z, n_, L_, rx, ry in ((4.55, 30, 2.0, 2.15, 1.65), (3.7, 28, 1.5, 2.05, 1.55)):
    for k in range(n_):
        a = 2 * math.pi * k / n_ + rnd.uniform(-0.05, 0.05)
        p = Vector((math.cos(a) * rx, math.sin(a) * ry, ring_z))
        d = Vector((math.cos(a) * 0.3, math.sin(a) * 0.3, -1)).normalized()
        hp.cyl_between(p, p + d * rnd.uniform(L_ * 0.8, L_ * 1.1), rnd.uniform(0.28, 0.36), rnd.choice((FUR, FUR2)), r2=0.03, verts=5)
tail = [Vector((0, 1.3, 5.4)), Vector((0.2, 2.1, 4.8)), Vector((0.45, 2.7, 3.7)), Vector((0.55, 2.9, 2.5)), Vector((0.5, 2.8, 1.7))]
for i, (a, c) in enumerate(zip(tail, tail[1:])):
    hp.cyl_between(a, c, 0.3 - i * 0.05, MBRZ, r2=0.25 - i * 0.05, verts=10)
    hp.ball(0.3 - i * 0.05, c, MBRZ, seg=10)
for k in range(12):
    a = 2 * math.pi * k / 12
    tuft(hp, tail[-1], (math.cos(a) * 0.5, math.sin(a) * 0.5, -1), rnd.uniform(0.6, 1.0), 0.18, FUR2, droop=0.6)
# labrys on the back
hd0, hd1 = Vector((-2.0, 2.15, 4.4)), Vector((2.3, 2.15, 11.2))
sp.cyl_between(hd0, hd1, 0.2, WOOD, verts=10)
hdir = (hd1 - hd0).normalized()
for k in range(10):
    q = Vector((0, 0, 1)).rotation_difference(hdir)
    sp.torus(0.22, 0.05, hd0 + hdir * (0.6 + k * 0.25), LEATHER, quat=q, seg=10, ring=5)
sp.lathe([(0, 0), (0.3, 0), (0.32, 0.3), (0, 0.5)], hd1, ARMOR, quat=Vector((0, 0, 1)).rotation_difference(hdir), seg=10)
blade = [(0.25, -0.55), (0.9, -0.95)] + [(2.1 * math.cos(rad(a)), 2.1 * math.sin(rad(a))) for a in range(-48, 49, 8)] + [(0.9, 0.95), (0.25, 0.55)]
perp = hdir.cross(Vector((0, 1, 0))).normalized()
center = hd0 + hdir * 6.4
for sgn in (-1, 1):
    q = axes_quat(perp * sgn, hdir)
    sp.prism(blade, 0.18, center + Vector((0, 0.05, 0)), ARMOR, quat=q)
    sp.prism([(1.85 * math.cos(rad(a)), 1.85 * math.sin(rad(a))) for a in range(-44, 45, 8)] +
             [(2.12 * math.cos(rad(a)), 2.12 * math.sin(rad(a))) for a in range(44, -45, -8)], 0.2, center + Vector((0, 0.05, 0)), SCRATCH, quat=q)
sp.cyl(0.45, 0.3, center, GOLD, quat=Vector((0, 0, 1)).rotation_difference(Vector((0, 1, 0))), verts=16)
sp.box_between((2.6, 1.9, 10.2), (-2.2, 1.95, 6.0), 0.5, 0.15, LEATHER, side=(0, 1, 0))
pose(J, Spine=(14, 0, 0), Neck=(-6, 0, 0), ShoulderR=(-30, 10, 0), ShoulderL=(-20, -10, 0),
     ElbowR=(-30, 0, 0), ElbowL=(-24, 0, 0), HipR=(-16, 0, 0), KneeR=(14, 0, 0), HipL=(12, 0, 0), KneeL=(6, 0, 0))
D.finish()

# ======================================================================= TALOS forge gallows (x = +56)
COLL = collection("Cage_Talos", MY)
CT = cage_root("Cage_Talos", 56)
TBRZ = mat("Bronze_Talos", (168, 116, 58), rough=0.36, metal=0.9, noise=1.0, dark=0.66, bump=0.2)
WORN = mat("Bronze_Worn", (217, 165, 91), rough=0.26, metal=0.95, noise=2.0, dark=0.8)
RECESS = mat("Bronze_Recess", (91, 58, 28), rough=0.6, metal=0.6, noise=2.0, dark=0.6)
STRAP = mat("Bronze_Strap", (120, 84, 46), rough=0.5, metal=0.85, noise=1.4, dark=0.6, bump=0.2)
SLITM = mat("Visor_Slit", (26, 18, 10), rough=0.9)
SLATEH = mat("Slate_Hammer", (74, 70, 64), rough=0.8, noise=2.0, dark=0.7, bump=0.5)
GLOW = mat("Floor_Glow", (92, 210, 190), emit=1.4)
ANVIL = mat("Anvil_Steel", (58, 60, 64), rough=0.35, metal=0.95, noise=2.0, dark=0.7)
F = Batch("Forge_Base", CT, bevel=0.05)
F.cyl(10.5, 0.6, (0, 0, 0.3), RECESS, verts=72)
F.torus(10.5, 0.22, (0, 0, 0.6), WORN, seg=72, ring=6)
for k in range(48):
    a = 2 * math.pi * k / 48
    F.ball(0.13, (math.cos(a) * 10.52, math.sin(a) * 10.52, 0.3), WORN, seg=6)
for R_ in (4.2, 6.2, 8.9):
    F.torus(R_, 0.08, (0, 0, 0.62), TEALD, seg=64, ring=5)
for k in range(24):
    a = 2 * math.pi * k / 24
    r0, r1 = (4.2, 6.2) if k % 2 else (6.2, 8.9)
    F.box_between((math.cos(a) * r0, math.sin(a) * r0, 0.62), (math.cos(a) * r1, math.sin(a) * r1, 0.62), 0.06, 0.12, TEALD, side=(0, 0, 1))
F.cyl(3.9, 0.06, (0, 0, 0.63), GLOW, verts=48)
light("FloorGlowLight", "POINT", (0, -2, 2.5), CT, 200, (92, 210, 190), radius=2.0)
for sx in (-1, 1):
    F.box((3.4, 3.4, 1.2), (sx * 14, 0, 0.6), STONE)
    F.box((1.6, 1.6, 24), (sx * 14, 0, 12.6), TBRZ)
    for zz in range(3, 24, 4):
        F.box((1.95, 1.95, 0.45), (sx * 14, 0, zz), WORN)
        for d in ((0, -1), (0, 1), (-1, 0), (1, 0)):
            for o_ in (-0.5, 0.5):
                F.ball(0.09, (sx * 14 + d[0] * 0.99 + (o_ if d[0] == 0 else 0), d[1] * 0.99 + (o_ if d[1] == 0 else 0), zz), RECESS, seg=6)
    F.box((2.3, 2.3, 0.5), (sx * 14, 0, 24.4), WORN)
    F.box_between((sx * 14, 0, 18.5), (sx * 8.5, 0, 24.0), 0.9, 0.9, TBRZ, side=(0, -1, 0))
    for t in (0.2, 0.4, 0.6, 0.8):
        F.ball(0.1, Vector((sx * 14, -0.47, 18.5)).lerp(Vector((sx * 8.5, -0.47, 24.0)), t), WORN, seg=6)
F.box((30.2, 2.4, 0.4), (0, 0, 25.75), TBRZ)
F.box((30.2, 2.4, 0.4), (0, 0, 24.15), TBRZ)
F.box((30.2, 0.7, 1.3), (0, 0, 24.95), RECESS)
for k in range(21):
    F.ball(0.12, (-15 + k * 1.5, -1.15, 25.75), WORN, seg=6)
    F.ball(0.12, (-15 + k * 1.5, -1.15, 24.15), WORN, seg=6)
for sx in (-1, 1):
    F.box((0.4, 2.6, 2.1), (sx * 15.2, 0, 24.95), WORN)
# pulley + winch
F.box((0.5, 1.0, 1.2), (0, 0, 23.4), RECESS)
F.torus(1.1, 0.2, (0, 0, 22.4), WORN, rot=(90, 0, 0), seg=28, ring=8)
for k in range(6):
    a = k * math.pi / 3
    F.cyl_between((0, 0, 22.4), (math.cos(a) * 1.05, 0, 22.4 + math.sin(a) * 1.05), 0.08, TBRZ, verts=6)
F.cyl(0.3, 0.5, (0, 0, 22.4), RECESS, rot=(90, 0, 0), verts=12)
WX, WY, WZ = 14, -2.2, 6.5
for dx in (-1.3, 1.3):
    F.box((0.3, 1.2, 1.8), (WX + dx, WY + 0.6, WZ), RECESS)
F.cyl(0.7, 2.3, (WX, WY, WZ), WOOD, rot=(0, 90, 0), verts=16)
for k in range(6):
    F.torus(0.78, 0.1, (WX - 0.9 + k * 0.36, WY, WZ), IRON, rot=(0, 90, 0), seg=14, ring=5)
F.prism(gear_pts(1.25, 1.0, 14), 0.25, (WX + 1.55, WY, WZ), WORN, rot=(0, 0, 90))
F.cyl(0.3, 0.4, (WX + 1.55, WY, WZ), RECESS, rot=(0, 90, 0), verts=10)
F.box_between((WX + 1.8, WY, WZ), (WX + 1.8, WY, WZ - 1.6), 0.25, 0.25, RECESS, side=(1, 0, 0))
F.cyl_between((WX + 1.8, WY, WZ - 1.6), (WX + 2.6, WY, WZ - 1.6), 0.15, WOOD, verts=8)
chain(F, (WX - 0.2, WY - 0.1, WZ + 0.75), (0.9, -0.1, 22.0), IRON, link=0.7)
# hanging cage
R0, ZB, HC = 8.0, 0.9, 17.0
CA = Batch("Talos_Cage", CT, bevel=0.035)
CA.cyl(8.6, 0.5, (0, 0, ZB), RECESS, verts=64)
for k in range(16):
    a = 360.0 * k / 16
    ca, sa = math.cos(rad(a)), math.sin(rad(a))
    CA.box((0.35, 0.9, HC), (ca * R0, sa * R0, ZB + HC / 2), STRAP, rot=(0, 0, a))
    for j in range(9):
        CA.ball(0.12, (ca * (R0 + 0.2), sa * (R0 + 0.2), ZB + 1 + j * 1.95), WORN, seg=6)
for z in (ZB + 0.3, ZB + HC / 3, ZB + 2 * HC / 3, ZB + HC):
    CA.torus(R0 + 0.05, 0.3, (0, 0, z), WORN, seg=64, ring=8)
APEX = ZB + HC + 4.6
for k in range(8):
    a = rad(45 * k + 22.5)
    pts = [(R0 * math.cos(t) * math.cos(a), R0 * math.cos(t) * math.sin(a), ZB + HC + 4.6 * math.sin(t))
           for t in [rad(v) for v in range(0, 91, 10)]]
    curve("DomeArc", pts, 0.3, STRAP, CT)
    for p in pts[1:-1:2]:
        CA.ball(0.13, p, WORN, seg=6)
CA.lathe([(0, 0), (1.0, 0), (1.0, 0.25), (0.6, 0.45), (0.75, 0.9), (0.35, 1.3), (0, 1.5)], (0, 0, APEX - 0.6), WORN, seg=16)
CA.torus(0.75, 0.2, (0, 0, APEX + 1.8), WORN, rot=(90, 0, 0), seg=18, ring=8)
chain(CA, (0, 0, APEX + 2.5), (0, 0, 21.4), IRON)
for sx in (-1, 1):  # cage door
    a = rad(270 + sx * 22.5)
    for zz in (ZB + 3, ZB + 13):
        CA.cyl(0.25, 1.0, (math.cos(a) * (R0 + 0.35), math.sin(a) * (R0 + 0.35), zz), WORN, verts=10)
CA.box((1.1, 0.6, 1.3), (0, -R0 - 0.6, ZB + 8.5), RECESS)
CA.torus(0.4, 0.1, (0, -R0 - 0.6, ZB + 9.2), IRON, rot=(90, 0, 0), arc=180, seg=12, ring=6)
CA.box((0.12, 0.05, 0.3), (0, -R0 - 0.92, ZB + 8.4), DARK)
# forge props
anvil = [(-1.9, 0.0), (1.4, 0.0), (1.4, 0.5), (0.9, 0.7), (0.9, 1.3), (1.6, 1.5), (1.6, 2.1), (-1.2, 2.1), (-2.6, 1.85), (-1.4, 1.5), (-0.9, 1.3), (-0.9, 0.7), (-1.9, 0.5)]
F.lathe([(0, 0), (1.25, 0), (1.15, 2.6), (1.25, 2.7), (0, 2.7)], (-19, -7, 0), WOOD, seg=18)
for zz in (0.4, 2.2):
    F.torus(1.22, 0.08, (-19, -7, zz), IRON, seg=20, ring=5)
F.prism(anvil, 1.3, (-19, -7, 2.7), ANVIL)
F.cyl_between((-18.6, -7.9, 4.85), (-19.6, -6.9, 4.85), 0.12, WOOD, verts=8)
F.box((0.8, 0.5, 0.5), (-18.4, -8.1, 4.95), IRON)
for k in range(2):
    F.cyl_between((-20.4, -7.2 + k * 0.3, 4.85), (-18.2, -7.6 + k * 0.5, 4.88), 0.06, IRON, verts=6)
FX, FY_ = 20, -6
for k in range(4):
    a = math.pi / 4 + k * math.pi / 2
    F.cyl_between((FX + math.cos(a) * 2.2, FY_ + math.sin(a) * 2.2, 0), (FX + math.cos(a) * 1.4, FY_ + math.sin(a) * 1.4, 2.6), 0.18, IRON, verts=8)
F.lathe([(0, 0), (1.0, 0), (2.3, 0.9), (2.5, 1.3), (2.3, 1.3), (1.0, 0.25), (0, 0.25)], (FX, FY_, 2.5), IRON, seg=24)
for _ in range(46):
    a, d = rnd.uniform(0, 2 * math.pi), rnd.uniform(0, 1.9)
    F.rock(rnd.uniform(0.15, 0.3), (FX + math.cos(a) * d, FY_ + math.sin(a) * d, 3.1), rnd.choice((COALH, COAL, COALH, COALH)))
flame(F, (FX, FY_, 3.15), FLAME, FLAMEI, 1.6)
for _ in range(40):
    F.ball(rnd.uniform(0.04, 0.09), (FX + rnd.gauss(0, 1.2), FY_ + rnd.gauss(0, 1.2), rnd.uniform(4.5, 10)), FLAMEI, seg=6)
light("ForgeFire", "POINT", (FX, FY_, 5.0), CT, 420, (255, 130, 50), radius=0.8)
BX, BY = 21.5, 3.5
for k in range(18):
    a = 360 * k / 18
    F.box((0.6, 0.18, 3.2), (BX + math.cos(rad(a)) * 1.5, BY + math.sin(rad(a)) * 1.5, 1.6), WOOD, rot=(0, 0, a + 90))
for zz in (0.5, 1.6, 2.8):
    F.torus(1.6, 0.07, (BX, BY, zz), IRON, seg=24, ring=5)
F.cyl(1.4, 0.05, (BX, BY, 2.9), WATER, verts=20)
RX, RY = -20.5, 4.0
for dx in (-1.6, 1.6):
    F.box((0.3, 0.3, 4.5), (RX + dx, RY, 2.25), WOOD)
F.box((3.6, 0.3, 0.3), (RX, RY, 4.3), WOOD)
for k, dx in enumerate((-1.0, 0.0, 1.0)):
    F.cyl_between((RX + dx, RY - 0.2, 4.2), (RX + dx, RY - 0.2, 1.6 + k * 0.3), 0.07, IRON, verts=6)
    if k == 1:
        F.box((0.8, 0.4, 0.45), (RX + dx, RY - 0.2, 1.5), IRON)
    else:
        F.cyl_between((RX + dx + 0.12, RY - 0.2, 4.2), (RX + dx + 0.25, RY - 0.2, 1.8), 0.07, IRON, verts=6)
for _ in range(40):
    F.rock(rnd.uniform(0.2, 0.45), (rnd.gauss(23.5, 1.0), rnd.gauss(-1.0, 0.8), 0.15), COAL, scale=(1, 1, 0.7))
light("ForgeKey", "AREA", (0, -15, 23), CT, 380, (255, 220, 180), rot=(42, 0, 0), size=8)
F.finish()
CA.finish()

# ======================================================================= TALOS boss
COLL = collection("Boss_Talos", MY)
B = boss_root("Boss_Talos", CT, (0, 0, 0.66), 1.08)
J = humanoid("Ta_", B, TBRZ, head=False, mech=True)
D = Detail("Ta_", J, bevel=0.03)

def seam_ring(b, c, size, z, m, rivm, rivets=3):
    c = Vector(c)
    hx, hy = size[0] / 2 + 0.01, size[1] / 2 + 0.01
    b.box((size[0] + 0.04, 0.07, 0.09), (c.x, c.y - hy, z), m)
    b.box((size[0] + 0.04, 0.07, 0.09), (c.x, c.y + hy, z), m)
    b.box((0.07, size[1] + 0.04, 0.09), (c.x - hx, c.y, z), m)
    b.box((0.07, size[1] + 0.04, 0.09), (c.x + hx, c.y, z), m)
    for k in range(rivets):
        x = c.x - size[0] / 2 + size[0] * (k + 0.5) / rivets
        b.ball(0.1, (x, c.y - hy - 0.03, z + 0.22), rivm, seg=6)

sp = D["Spine"]
for sx in (-1, 1):
    sp.ball(1.5, (sx * 1.35, -1.38, 9.3), TBRZ, scale=(1, 0.36, 0.72), seg=24)
    sp.torus(1.35, 0.06, (sx * 1.35, -1.72, 9.3), WORN, rot=(90, 0, 0), seg=28, ring=5)
    for z in (8.05, 7.25, 6.5):
        sp.box((1.05, 0.32, 0.72), (sx * 0.62, -1.58, z), TBRZ)
        sp.box((1.12, 0.1, 0.08), (sx * 0.62, -1.76, z + 0.4), WORN)
    sp.box((0.4, 0.4, 3.6), (sx * 2.95, -1.4, 8.4), WORN)
    for k in range(7):
        sp.ball(0.1, (sx * 2.98, -1.62, 6.6 + k * 0.6), RECESS, seg=6)
sp.box((5.9, 3.3, 0.5), (0, 0, 10.4), WORN)
sp.box((0.14, 0.12, 3.9), (0, -1.66, 8.3), RECESS)
sp.cyl(0.75, 0.18, (0, -1.82, 9.85), WORN, rot=(90, 0, 0), verts=24)
sp.torus(0.7, 0.07, (0, -1.92, 9.85), GOLD, rot=(90, 0, 0), seg=24, ring=5)
sp.ball(0.4, (0, -1.9, 9.85), TBRZ, scale=(1, 0.5, 1.1), seg=14)
for k in range(10):
    a = 2 * math.pi * k / 10
    sp.ball(0.12, (math.cos(a) * 0.55, -1.98, 9.85 + math.sin(a) * 0.55), WORN, seg=6)
for z in (10.15, 6.45):
    for k in range(11):
        sp.ball(0.12, (-2.5 + k * 0.5, -1.62, z), WORN, seg=6)
for k in range(5):
    sp.box((3.0, 0.1, 0.22), (0, 1.62, 8.0 + k * 0.5), SLITM)
    sp.box((3.0, 0.05, 0.12), (0, 1.58, 8.0 + k * 0.5), TEALD)
for sx in (-1, 1):
    sp.cyl(0.32, 2.4, (sx * 1.8, 1.75, 10.6), RECESS, verts=12)
    sp.torus(0.34, 0.06, (sx * 1.8, 1.75, 11.75), WORN, seg=12, ring=5)
meander(sp, (-2.8, -1.6, 0), (1, 0, 0), (0, -1, 0), 5.6, GOLD, z0=6.5, h=0.0, unit=1.0, w=0.0) if False else None
nkb = D["Neck"]
for k, z in enumerate((9.95, 10.35, 10.75)):
    nkb.cyl(1.15 - k * 0.08, 0.32, (0, -0.35, z), RECESS if k % 2 else TBRZ, verts=20)
nkb.torus(1.05, 0.06, (0, -0.35, 10.55), TEALD, seg=24, ring=5)
for s, sx in SIDES:
    sh = D["Shoulder" + s]
    sh.cyl(1.2, 1.2, (sx * 3.0, 0, 9.35), RECESS, rot=(0, 90, 0), verts=20)
    for k in range(8):
        a = 2 * math.pi * k / 8
        sh.ball(0.11, (sx * 2.38, math.cos(a) * 0.9, 9.35 + math.sin(a) * 0.9), WORN, seg=6)
    for k, (r_, z_) in enumerate(((1.75, 9.9), (1.65, 9.35), (1.55, 8.8))):
        sh.ball(r_, (sx * 3.65, 0, z_), WORN if k == 0 else TBRZ, scale=(1, 1.02, 0.42), seg=24)
        sh.torus(r_ * 0.97, 0.06, (sx * 3.65, 0, z_ - 0.1), RECESS, seg=28, ring=5)
    seam_ring(sh, (sx * 3.6, 0, 8.0), (2.3, 2.4), 7.3, RECESS, WORN)
    el = D["Elbow" + s]
    el.cyl(0.85, 2.1, (sx * 3.6, 0, 6.7), RECESS, rot=(0, 90, 0), verts=18)
    el.cyl(0.45, 2.4, (sx * 3.6, 0, 6.7), WORN, rot=(0, 90, 0), verts=12)
    el.cyl_between((sx * 3.6, 1.05, 6.3), (sx * 3.6, 1.05, 4.6), 0.18, WORN, verts=10)
    el.cyl_between((sx * 3.6, 1.05, 4.6), (sx * 3.6, 1.05, 4.0), 0.26, RECESS, verts=10)
    el.box((2.05, 2.15, 1.0), (sx * 3.6, 0, 4.4), WORN)
    for k in range(3):
        el.box((1.2, 0.1, 0.12), (sx * 3.6, -1.06, 5.4 + k * 0.35), SLITM)
    seam_ring(el, (sx * 3.6, 0, 5.3), (1.9, 2.0), 6.0, RECESS, WORN)
    fingers(D, s, sx, TBRZ, WORN, mech=True, pin=RECESS)
    hp_ = D["Hip" + s]
    hp_.ball(1.0, (sx * 1.1, 0, 5.0), RECESS, seg=16)
    seam_ring(hp_, (sx * 1.1, 0, 3.6), (1.7, 2.0), 3.0, RECESS, WORN, rivets=2)
    hp_.box((1.5, 0.3, 2.0), (sx * 1.1, -1.05, 3.8), TBRZ)
    kn = D["Knee" + s]
    kn.cyl(0.78, 1.9, (sx * 1.1, 0, 2.6), RECESS, rot=(0, 90, 0), verts=16)
    kn.box((1.4, 0.45, 1.1), (sx * 1.1, -0.95, 2.6), WORN, rot=(10, 0, 0))
    kn.ball(0.12, (sx * 1.1, -1.2, 2.6), RECESS, seg=6)
    kn.box((1.75, 0.5, 2.0), (sx * 1.1, -0.85, 1.55), WORN)
    kn.box((0.12, 0.1, 1.9), (sx * 1.1, -1.12, 1.55), RECESS)
    for dz in (0.75, 2.35):
        for dx in (-0.6, 0.6):
            kn.ball(0.1, (sx * 1.1 + dx, -1.12, dz), RECESS, seg=6)
    kn.torus(0.85, 0.12, (sx * 1.1, 0, 1.0), WORN, seg=18, ring=6)
    for k in range(3):
        kn.box((1.9, 0.9, 0.25), (sx * 1.1, -0.9 - k * 0.55, 0.95 - k * 0.12), WORN if k % 2 == 0 else TBRZ, rot=(-12, 0, 0))
nkb.box((3.2, 3.0, 3.6), (0, -0.4, 11.4), TBRZ)
nkb.ball(1.72, (0, -0.4, 13.0), TBRZ, scale=(0.98, 0.92, 0.5), seg=24)
for sx in (-1, 1):
    nkb.box((0.45, 1.7, 2.2), (sx * 1.5, -1.35, 10.75), WORN, rot=(0, 0, sx * -12))
    for z in (10.0, 10.75, 11.5):
        nkb.ball(0.1, (sx * 1.74, -1.6, z), RECESS, seg=6)
nkb.box((2.4, 0.2, 0.42), (0, -1.92, 11.9), SLITM)
nkb.box((0.55, 0.2, 1.8), (0, -1.92, 10.95), SLITM)
nkb.box((2.3, 0.05, 0.3), (0, -1.88, 11.9), TEALD)
nkb.box((0.45, 0.05, 1.7), (0, -1.88, 10.95), TEALD)
for (sz, pos) in (((2.8, 0.16, 0.16), (0, -2.0, 12.2)), ((2.8, 0.16, 0.16), (0, -2.0, 11.6)),
                  ((0.16, 0.16, 1.9), (-0.38, -2.0, 10.8)), ((0.16, 0.16, 1.9), (0.38, -2.0, 10.8))):
    nkb.box(sz, pos, WORN)
nkb.box((3.4, 3.2, 0.35), (0, -0.4, 12.95), WORN)
for k in range(20):
    a = 2 * math.pi * k / 20
    nkb.ball(0.1, (math.cos(a) * 1.72, -0.4 + math.sin(a) * 1.62, 12.95), RECESS, seg=6)
nkb.box((0.6, 3.4, 0.45), (0, -0.2, 13.75), RECESS)
crest = [(-2.0 + 4.0 * t, 0.2 + 2.6 * math.sin(math.pi * t) ** 0.7) for t in [i / 16 for i in range(17)]] + [(2.0, -0.1), (-2.0, -0.1)]
nkb.prism(crest, 0.45, (0, -0.2, 13.95), WORN, rot=(0, 0, 90))
for k in range(15):
    t = (k + 1) / 16
    y = -2.0 + 4.0 * t
    h = 0.2 + 2.6 * math.sin(math.pi * t) ** 0.7
    nkb.box((0.5, 0.06, h * 0.85), (0, -0.2 + y, 13.95 + h * 0.45), RECESS)
light("Ta_VisorGlow", "POINT", (0, -2.6, 11.4), J["Neck"], 18, (92, 210, 190), radius=0.2)
hp = D["Hips"]
hp.box((3.95, 2.85, 0.6), (0, 0, 4.95), WORN)
hp.cyl(0.55, 0.2, (0, -1.5, 4.95), GOLD, rot=(90, 0, 0), verts=20)
hp.torus(0.5, 0.06, (0, -1.6, 4.95), RECESS, rot=(90, 0, 0), seg=20, ring=5)
for k in range(14):
    a = 2 * math.pi * k / 14
    hp.ball(0.1, (math.cos(a) * 2.0, math.sin(a) * 1.45, 4.95), RECESS, seg=6)

def pteruges_row(b, pts_, normal, L, y_off, mats):
    for i, p in enumerate(pts_):
        p = Vector(p)
        n = Vector(normal)
        q = basis_quat((n.y, -n.x, 0), n) if False else None
        rotz = math.degrees(math.atan2(n.x, -n.y))
        m = mats[i % len(mats)]
        b.box((0.6, 0.2, L), p, m, rot=(0, 0, rotz))
        for dz in (L * 0.3, -L * 0.1):
            b.ball(0.08, p + n * 0.13 + Vector((0, 0, dz)), GOLD, seg=6)
        for dx in (-0.18, 0.0, 0.18):
            off = Vector((math.cos(rad(rotz)), math.sin(rad(rotz)), 0)) * dx
            b.cyl(0.05, 0.4, p + off + Vector((0, 0, -L / 2 - 0.2)), LEATHER, verts=5)

for layer, (L, inset, zc) in enumerate(((2.5, 0.0, 3.7), (2.1, 0.1, 3.95))):
    off = 0.0 if layer == 0 else 0.3
    pteruges_row(hp, [(-2.4 + off + k * 0.62, -1.38 + inset, zc) for k in range(8 - layer)], (0, -1, 0), L, 0, (WORN, RECESS))
    pteruges_row(hp, [(-2.4 + off + k * 0.62, 1.38 - inset, zc) for k in range(8 - layer)], (0, 1, 0), L, 0, (RECESS,))
    for sx in (-1, 1):
        pteruges_row(hp, [(sx * (1.95 - inset), -0.9 + off + k * 0.6, zc) for k in range(4 - layer)], (sx, 0, 0), L, 0, (WORN, RECESS))
curve("Ta_IchorVein", [(-0.5, -1.7, 10.3), (-1.2, -1.75, 8.6), (-1.55, -1.45, 6.5), (-1.3, -1.35, 5.2),
                       (-1.15, -1.12, 3.8), (-1.1, -1.15, 2.2), (-1.1, -1.0, 1.25)], 0.1, TEALD, B)
for pts in ([(-1.2, -1.75, 8.6), (-0.6, -1.78, 8.0), (-0.2, -1.65, 7.4)],
            [(-1.55, -1.45, 6.5), (-2.1, -1.3, 6.9), (-2.6, -1.2, 7.2)],
            [(-1.2, -1.75, 8.6), (-1.9, -1.7, 9.3), (-2.3, -1.4, 10.0)],
            [(-1.15, -1.12, 3.8), (-0.7, -1.1, 3.3), (-0.5, -1.05, 2.9)]):
    curve("Ta_IchorBranch", pts, 0.05, TEALD, B)
for p in [(-1.2, -1.82, 8.6), (-1.55, -1.52, 6.5), (-1.15, -1.2, 3.8)]:
    D["Root"].ball(0.22, p, TEAL, seg=10)
kr = D["KneeR"]
kr.cyl(0.5, 0.4, (-1.1, -1.0, 1.15), TEAL, rot=(90, 0, 0), verts=24)
kr.torus(0.58, 0.1, (-1.1, -1.08, 1.15), WORN, rot=(90, 0, 0), seg=24, ring=6)
for k in range(6):
    a = 2 * math.pi * k / 6
    kr.ball(0.08, (-1.1 + math.cos(a) * 0.72, -1.05, 1.15 + math.sin(a) * 0.72), RECESS, seg=6)
kr.torus(0.3, 0.04, (-1.1, -1.22, 1.15), WORN, rot=(90, 0, 0), seg=16, ring=5)
light("Ta_SealGlow", "POINT", (-1.1, -2.0, 1.2), J["KneeR"], 45, (92, 210, 190), radius=0.2)
pose(J, ShoulderR=(-12, 10, 0), ElbowR=(-78, 0, 0), ShoulderL=(4, -8, 0), ElbowL=(-10, 0, 0))
hx, hy, hz = posed(B, J["ElbowR"], (-3.6, 0, 3.4))
R_ = Batch("Ta_Hammer", J["ElbowR"], bevel=0.03)
R_.cyl(0.3, 6.6, (hx, hy, hz + 1.2), RECESS, verts=12)
for k in range(12):
    R_.torus(0.32, 0.06, (hx, hy, hz - 0.6 + k * 0.22), LEATHER, seg=12, ring=5)
R_.lathe([(0, 0), (0.4, 0), (0.5, 0.25), (0.35, 0.5), (0.3, 0.5)], (hx, hy, hz - 2.4), WORN, seg=14)
R_.box((4.0, 2.4, 2.4), (hx - 0.4, hy, hz + 5.4), SLATEH)
for bx in (-1.25, 0.45):
    R_.box((0.38, 2.6, 2.6), (hx - 0.4 + bx, hy, hz + 5.4), TBRZ)
    for dz in (-0.9, 0.0, 0.9):
        R_.ball(0.1, (hx - 0.4 + bx, hy - 1.32, hz + 5.4 + dz), WORN, seg=6)
for sx in (-1, 1):
    R_.box((0.3, 2.2, 2.2), (hx - 0.4 + sx * 2.1, hy, hz + 5.4), WORN)
    R_.ball(0.3, (hx - 0.4 + sx * 2.27, hy, hz + 5.4), WORN, scale=(0.4, 1, 1), seg=10)
R_.box((0.8, 2.5, 0.6), (hx, hy, hz + 4.0), TBRZ)
meander(R_, (hx - 1.85, hy - 1.21, 0), (1, 0, 0), (0, -1, 0), 1.0, GOLD, z0=hz + 4.6, h=1.4, unit=1.0, w=0.07)
meander(R_, (hx - 0.1, hy - 1.21, 0), (1, 0, 0), (0, -1, 0), 1.3, GOLD, z0=hz + 4.6, h=1.4, unit=1.3, w=0.07)
bpy.context.view_layer.update()
_M_el = B.matrix_world.inverted() @ J["ElbowR"].matrix_world  # forearm, posed, in boss space
bmesh.ops.transform(R_.bm, matrix=_M_el.inverted() @ Matrix.Translation(R_.base), verts=R_.bm.verts[:])
R_.finish()
D.finish()

# ======================================================================= environment, studio, cameras
COLL = collection("Env", MY)
GROUND = mat("Yard_Stone", (78, 72, 64), rough=0.95, noise=0.15, dark=0.7, bump=0.3, nscale=3)
COBBLE = [mat(f"Cobble_{i}", c, rough=0.85, noise=2.0, dark=0.7, bump=0.4) for i, c in enumerate([(96, 90, 82), (84, 80, 74), (108, 98, 86)])]
box("Ground", (300, 160, 1), (0, 10, -0.55), GROUND, WORLD, bevel=0)
EB = Batch("Yard_Cobbles", WORLD, bevel=0.12)
gx = -92.0
while gx < 92:
    gy = -41.0
    while gy < -28.5:
        w, d = rnd.uniform(1.15, 1.45), rnd.uniform(1.05, 1.35)
        EB.box((w, d, 0.32), (gx + rnd.uniform(-0.08, 0.08), gy + rnd.uniform(-0.08, 0.08), 0.06 + rnd.uniform(-0.03, 0.03)),
               rnd.choice(COBBLE), rot=(rnd.uniform(-2, 2), rnd.uniform(-2, 2), rnd.uniform(-8, 8)))
        gy += 1.5
    gx += 1.5
for k in range(18):
    EB.box((2.2, 0.8, 0.5), (-92 + k * 10.8, -27.8, 0.2), STONE, rot=(0, 0, rnd.uniform(-2, 2)))
for _ in range(110):
    EB.rock(rnd.uniform(0.2, 0.8), (rnd.uniform(-100, 100), rnd.uniform(-60, 40), 0.05), PEBBLE, scale=(1, 1, 0.6))
for tx in (-84, -28, 28, 84):
    EB.cyl(0.35, 9.0, (tx, -31, 4.5), WOOD, verts=10)
    EB.cyl(0.6, 0.8, (tx, -31, 9.2), IRON, r2=0.85, verts=12)
    flame(EB, (tx, -31, 9.6), FLAME, FLAMEI, 1.0)
    light("YardTorch", "POINT", (tx, -31, 10.6), WORLD, 220, (255, 150, 70), radius=0.4)
EB.finish()
light("Sun", "SUN", (0, 0, 80), WORLD, 2.4, (255, 222, 186), rot=(52, 0, -28))
light("Fill", "AREA", (0, -110, 60), WORLD, 9000, (170, 190, 230), rot=(60, 0, 0), size=60)

COLL = collection("Studio", MY)
STUDIO = COLL
for name, x, yb in (("Cyclops", -56, 1.5), ("Minotaur", 0, 0), ("Talos", 56, 0)):
    light(f"Studio_{name}_Key", "AREA", (x - 9, yb - 16, 16), WORLD, 900, (255, 236, 214), rot=(55, 0, -30), size=6)
    light(f"Studio_{name}_Rim", "AREA", (x + 10, yb + 12, 14), WORLD, 1100, (190, 210, 255), rot=(-60, 0, 140), size=5)
    light(f"Studio_{name}_Fill", "AREA", (x + 12, yb - 14, 5), WORLD, 250, (255, 220, 190), rot=(80, 0, 40), size=8)
STUDIO.hide_render = True

world = bpy.data.worlds.new("MythYard_World")
scene.world = world
bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs["Color"].default_value = lin((52, 60, 78))
bg.inputs["Strength"].default_value = 0.7

COLL = MY
def camera(name, pos, target, lens, fstop=None):
    cd = bpy.data.cameras.new(name)
    cd.lens = lens
    cd.clip_end = 400
    cam = place(bpy.data.objects.new(name, cd), WORLD, pos)
    tgt = empty(name + "_target", target, WORLD, size=0.5)
    c = cam.constraints.new("TRACK_TO")
    c.target, c.track_axis, c.up_axis = tgt, "TRACK_NEGATIVE_Z", "UP_Y"
    if fstop:
        cd.dof.use_dof = True
        cd.dof.focus_object = tgt
        cd.dof.aperture_fstop = fstop
    return cam

CAMS = {
    "wide": (camera("CAM_Wide", (0, -118, 42), (0, 0, 9), 28), (1600, 900)),
    "cyclops": (camera("CAM_Cyclops", (-50, -44, 13), (-56, 0, 10.5), 32), (1600, 900)),
    "minotaur": (camera("CAM_Minotaur", (5, -44, 17), (0, 0, 12), 32), (1600, 900)),
    "talos": (camera("CAM_Talos", (62, -44, 15), (56, 0, 11), 32), (1600, 900)),
    "boss_cyclops": (camera("CAM_Boss_Cyclops", (-56 + 9, -26, 9.5), (-56, 1.5, 7.2), 55, fstop=4), (1080, 1350)),
    "boss_minotaur": (camera("CAM_Boss_Minotaur", (9, -26, 9.0), (0, 0, 6.6), 55, fstop=4), (1080, 1350)),
    "boss_talos": (camera("CAM_Boss_Talos", (56 + 9, -28, 10.5), (56, 0, 8.6), 55, fstop=4), (1080, 1350)),
    "face_cyclops": (camera("CAM_Face_Cyclops", (-56 + 3.5, -11, 11.2), (-56, -0.6, 10.6), 60, fstop=2.8), (1600, 900)),
    "face_minotaur": (camera("CAM_Face_Minotaur", (3.5, -12, 9.4), (0, -2.0, 8.6), 60, fstop=2.8), (1600, 900)),
    "face_talos": (camera("CAM_Face_Talos", (56 + 4.5, -14, 15.0), (56, -1.2, 13.4), 60, fstop=2.8), (1600, 900)),
}

try:
    scene.render.engine = "BLENDER_EEVEE"
except TypeError as e:
    print("engine:", e)
try:
    scene.eevee.taa_render_samples = 64
    scene.eevee.use_raytracing = True
except Exception as e:
    print("eevee:", e)
try:
    scene.eevee.shadow_pool_size = "1024"
except Exception as e:
    print("eevee:", e)
try:
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
except TypeError:
    pass

# ---------------------------------------------------------------- stats
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
stats = {}
total = 0
for c in MY.children:
    tris, n = 0, 0
    for ob in c.all_objects:
        n += 1
        if ob.type not in ("MESH", "CURVE", "FONT"):
            continue
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        tris += len(me.loop_triangles)
        ev.to_mesh_clear()
    total += tris
    stats[c.name] = {"objects": n, "tris": tris}
for name in ("Boss_Cyclops", "Boss_Minotaur", "Boss_Talos"):
    root = bpy.data.objects[name]
    zs = []
    for ob in root.children_recursive:
        if ob.type == "MESH":
            ev = ob.evaluated_get(dg)
            zs += [(ev.matrix_world @ Vector(b)).z for b in ev.bound_box]
    stats[name]["height_studs"] = round((max(zs) - min(zs)) / S, 1)
stats["total_tris"] = total
stats["primitives"] = STATS["prims"]
stats["objects"] = len(bpy.data.objects)
stats["materials"] = len(bpy.data.materials)

os.makedirs(os.path.join(OUT, "renders"), exist_ok=True)
scene.camera = CAMS["wide"][0]
scene.render.resolution_x, scene.render.resolution_y = CAMS["wide"][1]
blend = os.path.join(OUT, "myth_yard.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend)
stats["blend"] = blend

if RENDER:
    only = os.environ.get("MY_ONLY")
    cages = [bpy.data.collections[n] for n in ("Cage_Cyclops", "Cage_Minotaur", "Cage_Talos")]
    lift = {"Boss_Minotaur": 4.5, "Boss_Talos": 0.66}
    for key, (cam, res) in CAMS.items():
        if only and key not in only.split(","):
            continue
        boss_shot = key.startswith(("boss_", "face_"))
        for c in cages:
            c.hide_render = boss_shot
        STUDIO.hide_render = not boss_shot
        for bn, z0 in lift.items():
            bpy.data.objects[bn].location.z = 0.0 if boss_shot else z0
        scene.camera = cam
        scene.render.resolution_x, scene.render.resolution_y = res
        scene.render.filepath = os.path.join(OUT, "renders", f"myth_yard_{key}.png")
        bpy.ops.render.render(write_still=True)
    for c in cages:
        c.hide_render = False
    STUDIO.hide_render = True
    for bn, z0 in lift.items():
        bpy.data.objects[bn].location.z = z0
    scene.camera = CAMS["wide"][0]
    scene.render.resolution_x, scene.render.resolution_y = CAMS["wide"][1]
    bpy.ops.wm.save_mainfile()
print("@@JSON@@" + json.dumps(stats))
