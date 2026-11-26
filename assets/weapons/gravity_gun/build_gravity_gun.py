# Gravity manipulator, 90s comic NPR. Run inside Blender (exec), rebuilds the whole scene.
# +X = emitter/claws, +Z = up, -Y = left side (side grip). Metres.
import bpy, bmesh, math, random
from mathutils import Matrix, Vector

random.seed(7)
PI = math.pi

# ---------------------------------------------------------------- scene reset
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
for c in list(bpy.data.collections):
    bpy.data.collections.remove(c)
for blocks in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights,
               bpy.data.grease_pencils, bpy.data.node_groups, bpy.data.curves):
    for b in list(blocks):
        blocks.remove(b)
sc = bpy.context.scene
for s in list(bpy.data.scenes):
    if s != sc:
        bpy.data.scenes.remove(s)

COLL = {}
for n in ("01_Rear_Handle_And_Drums", "02_Main_Chassis", "03_Glowing_Core_And_Cage",
          "04_Claws_And_Emitter", "05_Line_Art_And_FX", "06_Studio_Lights_Camera"):
    COLL[n] = bpy.data.collections.new(n)
    sc.collection.children.link(COLL[n])
C1, C2, C3, C4, C5, C6 = COLL.values()
CUT = bpy.data.collections.new("_cutters")
C2.children.link(CUT)

# ---------------------------------------------------------------- materials
def lin(h):
    h = h.lstrip('#')
    def f(c):
        c = int(c, 16) / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (f(h[0:2]), f(h[2:4]), f(h[4:6]), 1.0)

MATS = {}

def toon(name, base, light, rust="#5A3424", rust_amt=0.67, spec=0.93, bounce=True):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree; N = nt.nodes; L = nt.links
    N.clear()
    def node(t, x, y, **kw):
        n = N.new(t); n.location = (x * 200, y * 200)
        for k, v in kw.items(): setattr(n, k, v)
        return n
    def math_(op, a, b=None, x=0, y=0):
        n = node('ShaderNodeMath', x, y, operation=op)
        for i, v in enumerate((a, b)):
            if v is None: continue
            if isinstance(v, (int, float)): n.inputs[i].default_value = v
            else: L.new(v, n.inputs[i])
        return n.outputs[0]
    def mix(fac, a, b, x=0, y=0):
        n = node('ShaderNodeMix', x, y, data_type='RGBA')
        L.new(fac, n.inputs['Factor'])
        for sock, v in ((6, a), (7, b)):
            if isinstance(v, tuple): n.inputs[sock].default_value = v
            else: L.new(v, n.inputs[sock])
        return n.outputs[2]

    # light level, hard cel steps
    dif = node('ShaderNodeBsdfDiffuse', -8, 2)
    s2r = node('ShaderNodeShaderToRGB', -7, 2)
    L.new(dif.outputs[0], s2r.inputs[0])
    bw = node('ShaderNodeRGBToBW', -6, 2)
    L.new(s2r.outputs[0], bw.inputs[0])
    lum = bw.outputs[0]

    # dirty base: noise rust patches + streak scratches
    tc = node('ShaderNodeTexCoord', -10, 0)
    nz = node('ShaderNodeTexNoise', -8, 0)
    nz.inputs['Scale'].default_value = 22; nz.inputs['Detail'].default_value = 6
    L.new(tc.outputs['Object'], nz.inputs['Vector'])
    rustm = math_('GREATER_THAN', nz.outputs[0], rust_amt, -6, 0)
    sc_ = node('ShaderNodeTexWave', -8, -1, wave_type='BANDS', bands_direction='X')
    sc_.inputs['Scale'].default_value = 9; sc_.inputs['Distortion'].default_value = 14
    sc_.inputs['Detail'].default_value = 8
    L.new(tc.outputs['Object'], sc_.inputs['Vector'])
    scr = math_('GREATER_THAN', sc_.outputs[1], 0.97, -6, -1)
    col = mix(rustm, lin(base), lin(rust), -4, 0)
    col = mix(scr, col, lin(light), -3, 0)

    # cel steps: >0.78 light tone, <0.35 ink black
    lit = math_('GREATER_THAN', lum, 1.05, -4, 2)
    col = mix(lit, col, lin(light), -2, 1)
    # hatching band 0.35-0.45, screen-space diagonal lines
    win = node('ShaderNodeTexCoord', -8, 4)
    wv = node('ShaderNodeTexWave', -7, 4, wave_type='BANDS', bands_direction='DIAGONAL')
    wv.inputs['Scale'].default_value = 55
    L.new(win.outputs['Window'], wv.inputs['Vector'])
    line = math_('GREATER_THAN', wv.outputs[1], 0.72, -6, 4)
    band = math_('MULTIPLY', math_('GREATER_THAN', lum, 0.24, -5, 3),
                 math_('LESS_THAN', lum, 0.4, -5, 4), -4, 4)
    hatch = math_('MULTIPLY', band, line, -3, 4)
    shadow = math_('MAXIMUM', math_('LESS_THAN', lum, 0.24, -3, 3), hatch, -2, 3)

    # fake core bounce: faces turned toward the X axis inside the core zone go hard orange
    if bounce:
        geo = node('ShaderNodeNewGeometry', -10, -3)
        sep = node('ShaderNodeSeparateXYZ', -9, -3)
        L.new(geo.outputs['Position'], sep.inputs[0])
        rad = node('ShaderNodeCombineXYZ', -8, -3)
        L.new(sep.outputs[1], rad.inputs[1]); L.new(sep.outputs[2], rad.inputs[2])
        nrm = node('ShaderNodeVectorMath', -7, -3, operation='NORMALIZE')
        L.new(rad.outputs[0], nrm.inputs[0])
        dot = node('ShaderNodeVectorMath', -6, -3, operation='DOT_PRODUCT')
        L.new(nrm.outputs[0], dot.inputs[0]); L.new(geo.outputs['Normal'], dot.inputs[1])
        facing = math_('LESS_THAN', dot.outputs['Value'], -0.6, -5, -3)
        rlen = node('ShaderNodeVectorMath', -7, -4, operation='LENGTH')
        L.new(rad.outputs[0], rlen.inputs[0])
        near = math_('LESS_THAN', rlen.outputs['Value'], 0.165, -6, -4)
        inx = math_('MULTIPLY', math_('GREATER_THAN', sep.outputs[0], 0.02, -6, -5),
                    math_('LESS_THAN', sep.outputs[0], 0.56, -6, -6), -5, -5)
        b1 = math_('MULTIPLY', math_('MULTIPLY', facing, near, -4, -4), inx, -3, -4)
        # chassis/collar front faces looking down +X at the core
        sepn = node('ShaderNodeSeparateXYZ', -6, -7)
        L.new(geo.outputs['Normal'], sepn.inputs[0])
        front = math_('MULTIPLY', math_('GREATER_THAN', sepn.outputs[0], 0.6, -5, -7),
                      math_('MULTIPLY', math_('LESS_THAN', sep.outputs[0], 0.1, -5, -8),
                            math_('GREATER_THAN', sep.outputs[0], 0.0, -5, -9), -4, -8), -3, -7)
        bmask = math_('MAXIMUM', b1, front, -2, -5)
        col = mix(bmask, col, lin("#FF6A00"), -1, 0)
        shadow = math_('MULTIPLY', shadow, math_('SUBTRACT', 1.0, bmask, -1, 2), 0, 3)

    col = mix(shadow, col, (0, 0, 0, 1), 0, 1)

    # hard specular pop
    if spec:
        gl = node('ShaderNodeBsdfGlossy', -8, 6)
        gl.inputs['Roughness'].default_value = 0.18
        g2 = node('ShaderNodeShaderToRGB', -7, 6)
        L.new(gl.outputs[0], g2.inputs[0])
        gbw = node('ShaderNodeRGBToBW', -6, 6)
        L.new(g2.outputs[0], gbw.inputs[0])
        hi = math_('GREATER_THAN', gbw.outputs[0], spec, -4, 6)
        col = mix(hi, col, (1, 1, 1, 1), 1, 1)

    em = node('ShaderNodeEmission', 2, 1)
    L.new(col, em.inputs[0])
    out = node('ShaderNodeOutputMaterial', 3, 1)
    L.new(em.outputs[0], out.inputs[0])
    MATS[name] = m
    return m

def glow(name, mode="core"):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree; N = nt.nodes; L = nt.links
    N.clear()
    em = N.new('ShaderNodeEmission'); out = N.new('ShaderNodeOutputMaterial')
    L.new(em.outputs[0], out.inputs[0])
    lw = N.new('ShaderNodeLayerWeight'); lw.inputs['Blend'].default_value = 0.35
    ramp = N.new('ShaderNodeValToRGB'); ramp.color_ramp.interpolation = 'CONSTANT'
    st = N.new('ShaderNodeValToRGB'); st.color_ramp.interpolation = 'CONSTANT'
    if mode == "core":
        # longitudinal stripes: angle around X -> sine
        tc = N.new('ShaderNodeTexCoord'); sep = N.new('ShaderNodeSeparateXYZ')
        L.new(tc.outputs['Object'], sep.inputs[0])
        at = N.new('ShaderNodeMath'); at.operation = 'ARCTAN2'
        L.new(sep.outputs[2], at.inputs[0]); L.new(sep.outputs[1], at.inputs[1])
        k = N.new('ShaderNodeMath'); k.operation = 'MULTIPLY'; k.inputs[1].default_value = 12
        L.new(at.outputs[0], k.inputs[0])
        sn = N.new('ShaderNodeMath'); sn.operation = 'SINE'; L.new(k.outputs[0], sn.inputs[0])
        f = N.new('ShaderNodeMath'); f.operation = 'MULTIPLY_ADD'
        f.inputs[1].default_value = 0.22; f.inputs[2].default_value = 0.0
        L.new(sn.outputs[0], f.inputs[0])
        fac = N.new('ShaderNodeMath'); fac.operation = 'ADD'
        L.new(lw.outputs['Facing'], fac.inputs[0]); L.new(f.outputs[0], fac.inputs[1])
        inv = N.new('ShaderNodeMath'); inv.operation = 'SUBTRACT'; inv.inputs[0].default_value = 1.0
        L.new(fac.outputs[0], inv.inputs[1])
        v = inv.outputs[0]
    else:
        inv = N.new('ShaderNodeMath'); inv.operation = 'SUBTRACT'; inv.inputs[0].default_value = 1.0
        L.new(lw.outputs['Facing'], inv.inputs[1])
        v = inv.outputs[0]
    L.new(v, ramp.inputs[0]); L.new(v, st.inputs[0])
    e = ramp.color_ramp.elements
    e[0].position = 0.0; e[0].color = lin("#D92B00")
    e[1].position = 0.45; e[1].color = lin("#FF7A00")
    e.new(0.78).color = lin("#FFF7B2")
    s = st.color_ramp.elements
    s[0].color = (1, 1, 1, 1); s[1].position = 0.78; s[1].color = (2.6, 2.6, 2.6, 1)
    bw = N.new('ShaderNodeRGBToBW'); L.new(st.outputs[0], bw.inputs[0])
    L.new(ramp.outputs[0], em.inputs['Color']); L.new(bw.outputs[0], em.inputs['Strength'])
    MATS[name] = m
    return m

def flat(name, hexcol, strength=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    N = m.node_tree.nodes; N.clear()
    em = N.new('ShaderNodeEmission'); out = N.new('ShaderNodeOutputMaterial')
    em.inputs[0].default_value = lin(hexcol); em.inputs[1].default_value = strength
    m.node_tree.links.new(em.outputs[0], out.inputs[0])
    MATS[name] = m
    return m

STEEL  = toon("M_Steel",  "#4E5A63", "#9AA8B0")
ARMOR  = toon("M_Armor",  "#3A444F", "#7D8B95", rust_amt=0.58)
CAGE   = toon("M_Cage",   "#5E6B73", "#A9B5BC", rust_amt=0.66)
DARK   = toon("M_Dark",   "#1E222B", "#3E4655", rust="#2F2422", rust_amt=0.7, spec=0.97)
YOKE   = toon("M_Yoke",   "#2F2422", "#5A4038", rust="#1E222B", rust_amt=0.7, spec=0.96)
COPPER = toon("M_Copper", "#8C5230", "#B9784A", rust="#3F5A4A", rust_amt=0.7, spec=0.88, bounce=False)
RED    = toon("M_Red",    "#D92323", "#FF7A6A", rust_amt=2.0, spec=0.85, bounce=False)
TAPE   = toon("M_DuctTape", "#9EA5AB", "#E8ECEF", rust="#6E747A", rust_amt=0.68, spec=0.8, bounce=False)
GAUGE  = toon("M_GaugeFace", "#E2DCC2", "#FFFBEA", rust_amt=2.0, spec=0, bounce=False)
CORE   = glow("M_CoreGlow", "core")
GLOW   = glow("M_SlotGlow", "slot")
LED    = flat("M_LED", "#FFE066", 2.2)
INK    = flat("M_Ink", "#000000", 1.0)
INK.use_backface_culling = True
INK.use_backface_culling_shadow = True   # hull must not shadow the model it wraps

# ---------------------------------------------------------------- geometry helpers
def finish(bm, name, coll, mats, bevel=True, outline=True, frame=Matrix()):
    bm.transform(frame)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    for m in (mats if isinstance(mats, (list, tuple)) else [mats]):
        me.materials.append(m)
    if bevel:
        bv = ob.modifiers.new("Bevel", 'BEVEL')
        bv.width = 0.0012; bv.segments = 1; bv.limit_method = 'ANGLE'
        bv.angle_limit = math.radians(35); bv.harden_normals = False
    if outline:
        add_outline(ob)
    return ob

def add_outline(ob, t=0.0022):
    n = len(ob.data.materials)
    ob.data.materials.append(INK)
    so = ob.modifiers.new("InkHull", 'SOLIDIFY')
    so.thickness = t; so.offset = 1.0; so.use_flip_normals = True
    so.use_rim = False; so.material_offset = n; so.material_offset_rim = n

def lathe(name, prof, coll, mat, segs=32, frame=Matrix(), closed=False, start=0.0, **kw):
    """prof = [(axial, radius)], revolved about local X, then frame -> world."""
    bm = bmesh.new()
    rings = []
    for a, r in prof:
        ring = []
        for i in range(segs):
            t = start + 2 * PI * i / segs
            ring.append(bm.verts.new((a, r * math.cos(t), r * math.sin(t))))
        rings.append(ring)
    pairs = list(zip(rings, rings[1:]))
    if closed: pairs.append((rings[-1], rings[0]))
    for r0, r1 in pairs:
        for i in range(segs):
            j = (i + 1) % segs
            bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
    if not closed:
        bm.faces.new(rings[0]); bm.faces.new(rings[-1])
    return finish(bm, name, coll, mat, frame=frame, **kw)

def box(name, size, coll, mat, frame=Matrix(), jitter=0.0, **kw):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.transform(Matrix.Diagonal((*size, 1)))
    if jitter:
        for v in bm.verts:
            v.co += Vector([random.uniform(-jitter, jitter) for _ in range(3)])
    return finish(bm, name, coll, mat, frame=frame, **kw)

def T(x, y, z): return Matrix.Translation((x, y, z))
def RX(a): return Matrix.Rotation(math.radians(a), 4, 'X')
def RY(a): return Matrix.Rotation(math.radians(a), 4, 'Y')
def RZ(a): return Matrix.Rotation(math.radians(a), 4, 'Z')
AXIS_Y = RZ(90)     # local X -> world Y
AXIS_Z = RY(-90)    # local X -> world Z

def beam_frame(p0, p1, up=Vector((0, 0, 1))):
    """frame whose local X runs p0->p1, origin at the midpoint; returns (frame, length)."""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0; ln = d.length; x = d.normalized()
    y = up.cross(x)
    if y.length < 1e-6: y = Vector((0, 1, 0)).cross(x)
    y.normalize(); z = x.cross(y)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = (p0 + p1) / 2
    return m, ln

def beam(name, p0, p1, w, h, coll, mat, up=Vector((0, 0, 1)), **kw):
    f, ln = beam_frame(p0, p1, up)
    return box(name, (ln, w, h), coll, mat, frame=f, **kw)

def rod(name, p0, p1, r, coll, mat, segs=10, **kw):
    f, ln = beam_frame(p0, p1)
    return lathe(name, [(-ln / 2, r), (ln / 2, r)], coll, mat, segs=segs, frame=f, **kw)

def parent_keep(child, parent):
    child.parent = parent
    child.matrix_parent_inverse = parent.matrix_world.inverted()

def empty(name, coll, mw, size=0.03):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = 'ARROWS'; e.empty_display_size = size
    coll.objects.link(e); e.matrix_world = mw
    return e

# ================================================================= 01 rear: yoke, drums, grips
YX = -0.17          # yoke / drum centre x
# yoke: two thick rounded plates with a groove between
for side, s in (("L", -1), ("R", 1)):
    lathe(f"Yoke_Plate_{side}", [(0.006, 0.0), (0.006, 0.082), (0.010, 0.088), (0.026, 0.088), (0.031, 0.082), (0.031, 0.0)],
          C1, YOKE, segs=40, frame=T(YX, 0, 0) @ AXIS_Y @ Matrix.Diagonal((s, 1, 1, 1)), closed=True)
lathe("Yoke_Groove", [(-0.0065, 0.07), (0.0065, 0.07)], C1, DARK, segs=40, frame=T(YX, 0, 0) @ AXIS_Y)
# drums: brushed steel, stepped outer flange
for side, s in (("L", -1), ("R", 1)):
    prof = [(0.030, 0.0), (0.030, 0.074), (0.036, 0.079), (0.092, 0.079), (0.098, 0.072),
            (0.104, 0.072), (0.104, 0.060), (0.112, 0.056), (0.112, 0.0)]
    lathe(f"Drum_{side}", prof, C1, STEEL, segs=44, closed=True,
          frame=T(YX, 0, 0) @ AXIS_Y @ Matrix.Diagonal((s, 1, 1, 1)))
    lathe(f"Drum_Hub_{side}", [(0.110, 0.0), (0.110, 0.03), (0.118, 0.026), (0.118, 0.0)], C1, DARK,
          segs=24, closed=True, frame=T(YX, 0, 0) @ AXIS_Y @ Matrix.Diagonal((s, 1, 1, 1)))

# side grip on the left drum, ribbed, sticking out -Y
prof = [(0.116, 0.0), (0.116, 0.024)]
y = 0.124
while y < 0.225:
    prof += [(y, 0.024), (y + 0.003, 0.0215), (y + 0.006, 0.0215), (y + 0.009, 0.024)]
    y += 0.009
prof += [(0.232, 0.024), (0.24, 0.02), (0.244, 0.012), (0.244, 0.0)]
lathe("SideGrip_Ribbed", prof, C1, DARK, segs=24, closed=True,
      frame=T(YX, 0, -0.008) @ AXIS_Y @ Matrix.Diagonal((-1, 1, 1, 1)))
lathe("SideGrip_Collar", [(0.104, 0.0), (0.104, 0.032), (0.12, 0.032), (0.12, 0.0)], C1, STEEL,
      segs=24, closed=True, frame=T(YX, 0, -0.008) @ AXIS_Y @ Matrix.Diagonal((-1, 1, 1, 1)))
box("Switch_Red", (0.014, 0.014, 0.02), C1, RED, frame=T(YX + 0.040, -0.118, 0.026))
box("Switch_Base", (0.022, 0.006, 0.028), C1, DARK, frame=T(YX + 0.040, -0.112, 0.026))

# gauge on the top edge of the left drum, taped on
GZ = 0.079
gx, gy = YX - 0.004, -0.072
lathe("Gauge_Body", [(-0.004, 0.0), (-0.004, 0.024), (0.016, 0.024), (0.019, 0.021), (0.019, 0.0)],
      C1, STEEL, segs=28, closed=True, frame=T(gx, gy, GZ) @ AXIS_Z)
lathe("Gauge_Face", [(0.0186, 0.0), (0.0186, 0.019), (0.0196, 0.019), (0.0196, 0.0)], C1, GAUGE,
      segs=28, closed=True, frame=T(gx, gy, GZ) @ AXIS_Z, bevel=False, outline=False)
beam("Gauge_Needle", (gx, gy, GZ + 0.0205), (gx + 0.012, gy - 0.009, GZ + 0.0205), 0.0018, 0.0012, C1, RED,
     bevel=False, outline=False)
# duct tape: a strip draped over the drum top across the gauge base, crinkled
bm = bmesh.new()
pts = []
for i in range(17):
    a = math.radians(40 + 100 * i / 16)                # around drum axis (Y), 40..140 deg
    r = 0.0805
    x, z = math.cos(a) * r, math.sin(a) * r
    if abs(x - (gx - YX)) < 0.03: z = max(z, GZ + 0.004)  # rides over the gauge rim
    pts.append((x, z))
rows = []
for x, z in pts:
    row = []
    for w in (-0.017, 0.017):
        row.append(bm.verts.new((YX + x + random.uniform(-0.0012, 0.0012), gy + w + random.uniform(-0.0015, 0.0015),
                                 z + random.uniform(0, 0.0012))))
    rows.append(row)
for r0, r1 in zip(rows, rows[1:]):
    bm.faces.new((r0[0], r0[1], r1[1], r1[0]))
bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.0016)
finish(bm, "DuctTape_Strip", C1, TAPE, bevel=False)

# rear main grip: chunky, pitched down, black tape collar, light spine, rounded foot
GR = T(YX - 0.068, 0, -0.012) @ RY(-28)          # local -X runs back/down
box("RearGrip_Body", (0.09, 0.042, 0.052), C1, DARK, frame=GR @ T(-0.05, 0, 0))
box("RearGrip_TapeWrap", (0.026, 0.05, 0.06), C1, DARK, frame=GR @ T(-0.012, 0, 0), jitter=0.0018)
box("RearGrip_Spine", (0.07, 0.022, 0.006), C1, STEEL, frame=GR @ T(-0.055, 0, 0.028))
lathe("RearGrip_Foot", [(0.0, 0.0), (0.0, 0.03), (0.012, 0.032), (0.02, 0.028), (0.024, 0.016),
                        (0.020, 0.016), (0.020, 0.0)],
      C1, DARK, segs=24, closed=True, frame=GR @ T(-0.095, 0, 0) @ RZ(180))
box("RearGrip_Mount", (0.04, 0.05, 0.07), C1, YOKE, frame=GR @ T(0.012, 0, 0))

# ================================================================= 02 chassis
ch = lathe("Chassis_Armor", [(-0.125, 0.07), (-0.108, 0.094), (0.030, 0.094), (0.050, 0.078)],
           C2, ARMOR, segs=8, start=PI / 8)
for v in ch.data.vertices:          # trapezoid: narrower and taller on top
    if v.co.z > 0.01: v.co.y *= 0.82; v.co.z *= 1.08
box("Chassis_TopPlate", (0.11, 0.07, 0.016), C2, ARMOR, frame=T(-0.04, 0, 0.098) @ RY(-4))
box("Chassis_TopLamp", (0.018, 0.026, 0.006), C2, GLOW, frame=T(-0.005, 0, 0.108), outline=False)
# side vent slots: boolean cuts with glowing inserts inside
for side, s in (("L", -1), ("R", 1)):
    for i in range(3):
        x = -0.07 + 0.032 * i
        f = T(x, s * 0.094, -0.004) @ RY(-22)
        cut = box(f"Cut_Vent_{side}{i}", (0.012, 0.03, 0.062), CUT, ARMOR, frame=f, bevel=False, outline=False)
        cut.hide_viewport = cut.hide_render = True
        bo = ch.modifiers.new(f"Vent_{side}{i}", 'BOOLEAN')
        bo.operation = 'DIFFERENCE'; bo.object = cut; bo.solver = 'EXACT'
        box(f"Vent_Glow_{side}{i}", (0.010, 0.004, 0.058), C2, GLOW,
            frame=T(x, s * (0.094 - 0.0135), -0.004) @ RY(-22), bevel=False, outline=False)
# reorder: booleans before bevel/outline
for m in [m for m in ch.modifiers if m.type == 'BOOLEAN']:
    while ch.modifiers.find(m.name) > 0:
        with bpy.context.temp_override(object=ch):
            bpy.ops.object.modifier_move_up(modifier=m.name)
# radiator fins underneath
for i in range(9):
    box(f"Radiator_Fin_{i:02d}", (0.0045, 0.084, 0.026), C2, STEEL, frame=T(-0.1 + i * 0.015, 0, -0.098))
box("Radiator_Rail", (0.135, 0.012, 0.008), C2, DARK, frame=T(-0.04, 0, -0.108))
lathe("Copper_Collar", [(0.040, 0.06), (0.040, 0.088), (0.050, 0.094), (0.078, 0.094), (0.084, 0.086), (0.084, 0.06)],
      C2, COPPER, segs=40, closed=True)

# ================================================================= 03 core + cage
CX0, CX1 = 0.06, 0.335
core = lathe("Core_Glow", [(CX0, 0.052), (CX1, 0.052)], C3, CORE, segs=36, bevel=False, outline=False)
for i in range(12):
    a = 360 * i / 12
    box(f"Core_Rib_{i:02d}", (CX1 - CX0 - 0.02, 0.008, 0.006), C3, CORE,
        frame=RX(a) @ T((CX0 + CX1) / 2, 0, 0.054), bevel=False, outline=False)
for o in [o for o in C3.objects if o.name.startswith("Core")]:
    o.visible_shadow = False

CAGE_A = (90, 210, 330)
for k, a in enumerate(CAGE_A):
    R = RX(a - 90)          # local +Z = this frame's radial direction
    for t in (-1, 1):
        box(f"Cage{k}_Rail_{'AB'[t > 0]}", (0.25, 0.012, 0.012), C3, CAGE, frame=R @ T(0.205, t * 0.022, 0.074))
    for x in (0.088, 0.205, 0.322):
        box(f"Cage{k}_Cross_{int(x*1000)}", (0.014, 0.056, 0.012), C3, CAGE, frame=R @ T(x, 0, 0.074))
        for t in (-1, 1):
            if x != 0.205:
                lathe(f"Cage{k}_Bolt_{int(x*1000)}_{t}", [(0.0, 0.0), (0.0, 0.0045), (0.004, 0.0045), (0.006, 0.0025), (0.006, 0.0)],
                      C3, STEEL, segs=6, closed=True, frame=R @ T(x, t * 0.022, 0.08) @ AXIS_Z, bevel=False)
    # parallel steel rods between frames
    Rr = RX(a - 90 + 60)
    rod(f"Cage_Rod_{k}", Rr @ Vector((0.075, 0, 0.068)), Rr @ Vector((0.335, 0, 0.068)), 0.005, C3, STEEL)
# front collar: chunky faceted ring
lathe("Front_Collar", [(0.325, 0.05), (0.325, 0.088), (0.333, 0.098), (0.352, 0.098), (0.36, 0.088), (0.36, 0.05)],
      C3, ARMOR, segs=12, closed=True, start=PI / 12)

# ================================================================= 04 emitter + claws
lathe("Emitter_Plate", [(0.34, 0.0), (0.34, 0.052), (0.358, 0.052), (0.364, 0.046), (0.364, 0.0)],
      C4, DARK, segs=12, closed=True, start=PI / 12)
lathe("Emitter_Ring_Outer", [(0.362, 0.040), (0.362, 0.046), (0.368, 0.046), (0.368, 0.040)], C4, STEEL, segs=36, closed=True)
lathe("Emitter_Ring_Glow", [(0.362, 0.026), (0.362, 0.034), (0.367, 0.034), (0.367, 0.026)], C4, GLOW, segs=36,
      closed=True, bevel=False, outline=False)
lathe("Emitter_Ring_Inner", [(0.362, 0.014), (0.362, 0.020), (0.369, 0.020), (0.369, 0.014)], C4, STEEL, segs=28, closed=True)
lathe("Emitter_Core_Dot", [(0.362, 0.0), (0.362, 0.010), (0.370, 0.008), (0.372, 0.0)], C4, CORE, segs=20,
      closed=True, bevel=False, outline=False)

HX, HR = 0.352, 0.104                 # hinge, local claw frame: +X forward, +Z radial, Y tangent
def P(x, r, t=0.0): return Vector((x, t, r))
a1, l1 = math.radians(58), 0.11
E = P(HX + l1 * math.cos(a1), HR + l1 * math.sin(a1))
a2, l2 = math.radians(-36), 0.09
Tp = E + Vector((l2 * math.cos(a2), 0, l2 * math.sin(a2)))
Tip = Tp + Vector((0.010, 0, -0.03))

def build_claw(k, ang):
    R = RX(ang - 90)
    root = empty(f"Claw{k}_Root", C4, R, 0.02)
    hinge = empty(f"Claw{k}_Hinge", C4, R @ Matrix.Translation(P(HX, HR)) , 0.03)
    elbow = empty(f"Claw{k}_Elbow", C4, R @ Matrix.Translation(E), 0.025)
    parent_keep(hinge, root); parent_keep(elbow, hinge)
    W = lambda v: R @ Vector(v)
    up = W((0, 1, 0))      # tangent as 'up' keeps beam faces aligned to the claw plane
    parts_root, parts_h, parts_e = [], [], []
    # bracket + axle on the collar
    parts_root.append(box(f"Claw{k}_Bracket", (0.034, 0.04, 0.02), C4, ARMOR, frame=R @ T(HX - 0.008, 0, HR - 0.008)))
    parts_root.append(rod(f"Claw{k}_Axle", W(P(HX, HR, -0.026)), W(P(HX, HR, 0.026)), 0.0085, C4, STEEL, segs=12))
    # wire guard loop on the outside of the hinge
    g = [P(HX - 0.012, HR + 0.004, -0.03), P(HX - 0.03, HR + 0.07, -0.03),
         P(HX - 0.03, HR + 0.07, 0.03), P(HX - 0.012, HR + 0.004, 0.03)]
    for i in range(3):
        parts_root.append(rod(f"Claw{k}_Guard_{i}", W(g[i]), W(g[i + 1]), 0.0038, C4, STEEL, segs=8))
    for i, p in enumerate(g[1:3]):
        parts_root.append(lathe(f"Claw{k}_GuardKnee_{i}", [(-0.0045, 0.0), (-0.0045, 0.0045), (0.0045, 0.0045), (0.0045, 0.0)],
                                C4, STEEL, segs=8, closed=True, frame=R @ Matrix.Translation(p) @ AXIS_Y, bevel=False))
    # arm 1: two converging rails + rungs (truss)
    for t in (-1, 1):
        parts_h.append(beam(f"Claw{k}_Arm1_Rail_{t}", W(P(HX, HR, t * 0.017)), W(E + Vector((0, t * 0.007, 0))),
                            0.009, 0.01, C4, CAGE, up=W((0, 0, 1))))
    for f in (0.3, 0.62):
        c = P(HX, HR).lerp(E, f); half = 0.017 + (0.007 - 0.017) * f
        parts_h.append(beam(f"Claw{k}_Arm1_Rung_{int(f*100)}", W(c + Vector((0, -half, 0))), W(c + Vector((0, half, 0))),
                            0.007, 0.007, C4, CAGE))
    parts_h.append(rod(f"Claw{k}_ElbowPin", W(E + Vector((0, -0.014, 0))), W(E + Vector((0, 0.014, 0))), 0.009, C4, STEEL, segs=12))
    # arm 2: bent forward and in, pointed, LED at the tip
    for t in (-1, 1):
        parts_e.append(beam(f"Claw{k}_Arm2_Rail_{t}", W(E + Vector((0, t * 0.007, 0))), W(Tp + Vector((0, t * 0.003, 0))),
                            0.008, 0.009, C4, CAGE))
    parts_e.append(beam(f"Claw{k}_Arm2_Rung", W(E.lerp(Tp, 0.5) + Vector((0, -0.005, 0))), W(E.lerp(Tp, 0.5) + Vector((0, 0.005, 0))),
                        0.006, 0.006, C4, CAGE))
    parts_e.append(beam(f"Claw{k}_Tip", W(Tp), W(Tip), 0.009, 0.008, C4, CAGE))
    led = lathe(f"Claw{k}_LED", [(-0.004, 0.0), (-0.004, 0.0045), (0.003, 0.0045), (0.005, 0.0)], C4, LED, segs=10,
                closed=True, frame=R @ Matrix.Translation(Tip + Vector((0, 0, 0.004))) @ AXIS_Z, bevel=False, outline=False)
    parts_e.append(led)
    for o in parts_root: parent_keep(o, root)
    for o in parts_h: parent_keep(o, hinge)
    for o in parts_e: parent_keep(o, elbow)

for k, a in enumerate(CAGE_A):
    build_claw(k, a)

# ================================================================= 06 lights + cameras
def look_at(ob, target):
    d = Vector(target) - ob.location
    ob.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()

def light(name, kind, loc, energy, color, size=0.0, target=None, **kw):
    ld = bpy.data.lights.new(name, kind); ld.energy = energy; ld.color = color[:3]
    if hasattr(ld, "shadow_soft_size"): ld.shadow_soft_size = size
    for k, v in kw.items(): setattr(ld, k, v)
    ob = bpy.data.objects.new(name, ld); C6.objects.link(ob); ob.location = loc
    if target: look_at(ob, target)
    return ob

light("Key_Sun", 'SUN', (0.3, -0.8, 1.2), 4.5, (1, 0.97, 0.92), target=(0.05, 0, 0), angle=math.radians(0.5))
for i, x in enumerate((0.11, 0.2, 0.29)):
    light(f"Core_Bounce_{i}", 'POINT', (x, 0, 0), 6.0, lin("#FF6A00"), size=0.0)
light("Fill_Sun", 'SUN', (1.0, -0.3, 0.1), 1.1, (0.85, 0.9, 1.0), target=(0, 0, 0))
light("Rim_Cyan", 'AREA', (-0.5, 0.7, 0.35), 60.0, lin("#3FD0FF"), target=(0.05, 0, 0), size=0.3)

def cam(name, loc, target, lens=38, ortho=None):
    cd = bpy.data.cameras.new(name)
    if ortho: cd.type = 'ORTHO'; cd.ortho_scale = ortho
    else: cd.lens = lens
    cd.clip_start = 0.01
    ob = bpy.data.objects.new(name, cd); C6.objects.link(ob); ob.location = loc
    look_at(ob, target)
    return ob

cam("Cam_Side_Ortho", (0.08, -2.0, 0.03), (0.08, 0, 0.03), ortho=1.05)
cam("Cam_Rear_3_4", (-0.62, -0.62, 0.34), (-0.07, 0, 0.0), lens=40)
hero = cam("Cam_Front_Hero", (0.78, -0.62, 0.27), (0.1, 0, 0.0), lens=36)
cam("Cam_Top", (0.08, 0, 2.0), (0.08, 0, 0), ortho=1.05)
sc.camera = hero

# ================================================================= world, render, colour
world = sc.world or bpy.data.worlds.new("World"); sc.world = world
world.use_nodes = True
wn = world.node_tree.nodes; wl = world.node_tree.links; wn.clear()
lp = wn.new('ShaderNodeLightPath')
bg_dark = wn.new('ShaderNodeBackground'); bg_dark.inputs[0].default_value = lin("#8090A0"); bg_dark.inputs[1].default_value = 0.45
bg_paper = wn.new('ShaderNodeBackground'); bg_paper.inputs[0].default_value = lin("#EDE4CC")
mx = wn.new('ShaderNodeMixShader'); wo = wn.new('ShaderNodeOutputWorld')
wl.new(lp.outputs['Is Camera Ray'], mx.inputs[0]); wl.new(bg_dark.outputs[0], mx.inputs[1])
wl.new(bg_paper.outputs[0], mx.inputs[2]); wl.new(mx.outputs[0], wo.inputs[0])

sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x, sc.render.resolution_y = 1600, 1000
sc.view_settings.view_transform = 'Standard'
sc.view_settings.look = 'None'
sc.render.film_transparent = False
sc.unit_settings.system = 'METRIC'
ee = sc.eevee
for attr, val in (("taa_render_samples", 32), ("use_shadows", True), ("shadow_ray_count", 1), ("shadow_step_count", 6)):
    if hasattr(ee, attr): setattr(ee, attr, val)

# compositor: glare only on very bright pixels (core whites), black ink untouched
try:
    ng = bpy.data.node_groups.new("Comic_Glow", 'CompositorNodeTree')
    sc.compositing_node_group = ng
    rl = ng.nodes.new('CompositorNodeRLayers')
    gl = ng.nodes.new('CompositorNodeGlare')
    for k, v in (("glare_type", 'FOG_GLOW'), ("quality", 'HIGH'), ("threshold", 1.2), ("size", 7)):
        if hasattr(gl, k): setattr(gl, k, v)
    for k, v in (("Type", 'Fog Glow'), ("Threshold", 1.2), ("Size", 0.4), ("Strength", 0.7)):
        if k in gl.inputs:
            try: gl.inputs[k].default_value = v
            except Exception: pass
    ng.interface.new_socket("Image", in_out='OUTPUT', socket_type='NodeSocketColor')
    go = ng.nodes.new('NodeGroupOutput')
    ng.links.new(rl.outputs['Image'], gl.inputs['Image'])
    ng.links.new(gl.outputs['Image'], go.inputs[0])
    print("compositor ok")
except Exception as ex:
    print("compositor skipped:", ex)

# ================================================================= 05 Line Art (crease + intersection ink)
try:
    gpd = bpy.data.grease_pencils.new("InkLines")
    gpo = bpy.data.objects.new("LineArt_Ink", gpd); C5.objects.link(gpo)
    gpd.layers.new("Ink")
    gm = bpy.data.materials.new("GP_Ink"); bpy.data.materials.create_gpencil_data(gm)
    gm.grease_pencil.color = (0, 0, 0, 1); gpd.materials.append(gm)
    weapon = bpy.data.collections.new("Weapon_All"); C5.children.link(weapon)
    weapon.hide_viewport = False
    la = gpo.modifiers.new("LineArt", 'LINEART')
    la.source_type = 'SCENE'
    la.target_layer = "Ink"; la.target_material = gm
    la.use_contour = True; la.use_crease = True; la.crease_threshold = math.radians(125)
    la.use_intersection = True; la.use_material = False; la.use_edge_mark = False
    la.radius = 0.0009; la.opacity = 1.0
    la.use_back_face_culling = True
    bpy.data.collections.remove(weapon)
    for o in list(C6.objects) + list(C5.objects):
        if o.type == 'MESH': o.lineart.usage = 'EXCLUDE'
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.data.materials and o.data.materials[0] in (CORE, GLOW, LED):
            o.lineart.usage = 'EXCLUDE'
    print("lineart ok")
except Exception as ex:
    print("lineart skipped:", ex)

# report
meshes = [o for o in bpy.data.objects if o.type == 'MESH' and not o.hide_render]
from mathutils import Vector as V
lo = V((9, 9, 9)); hi = V((-9, -9, -9))
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ V(c)
        lo = V(map(min, lo, w)); hi = V(map(max, hi, w))
print("objects", len(meshes), "bbox", tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi),
      "size", tuple(round(v, 3) for v in hi - lo))
