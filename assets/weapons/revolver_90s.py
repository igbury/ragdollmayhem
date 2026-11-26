# 90s-comic snub revolver (showcase render, not the in-game mesh): modular parts in named collections,
# procedural toon shader (hard bands, hatching, halftone), inverted-hull + Grease Pencil Line Art ink.
# Metres, barrel +X, top +Z, side profile seen from -Y. Run inside Blender:
#   ns = {"__file__": r"<repo>/assets/weapons/revolver_90s.py"}; exec(open(ns["__file__"]).read(), ns); ns["build"]()
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "revolver_90s.blend")


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple((v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4) for v in c) + (1.0,)


RED, TEAL, STEEL, YELLOW = srgb("C61A21"), srgb("0CA29B"), srgb("C6C9C9"), srgb("E5C514")
BLACK = (0, 0, 0, 1)

COLLS = ["01_Receiver", "02_Cylinder", "03_Shroud", "04_Grip", "05_Controls",
         "06_Line_Art_And_FX", "07_Studio_Lights_Camera"]


# ---------------------------------------------------------------- scene

def reset():
    bpy.ops.wm.read_homefile(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.resolution_x, sc.render.resolution_y = 1600, 1200
    sc.render.film_transparent = False
    for k, v in (("shadow_resolution_scale", 1.0), ("use_shadow_jitter_viewport", False), ("taa_render_samples", 64)):
        try:
            setattr(sc.eevee, k, v)
        except AttributeError:
            pass
    sc.unit_settings.system = "METRIC"
    w = bpy.data.worlds.new("World")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = srgb("24262B")  # flat backdrop
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    sc.world = w
    for n in COLLS:
        sc.collection.children.link(bpy.data.collections.new(n))


def coll(n):
    return bpy.data.collections[n]


# ---------------------------------------------------------------- materials

def toon_group():
    if "ComicToon" in bpy.data.node_groups:
        return bpy.data.node_groups["ComicToon"]
    g = bpy.data.node_groups.new("ComicToon", "ShaderNodeTree")
    g.interface.new_socket("Base", in_out="INPUT", socket_type="NodeSocketColor")
    g.interface.new_socket("Shader", in_out="OUTPUT", socket_type="NodeSocketShader")
    N, L = g.nodes, g.links
    gi, go = N.new("NodeGroupInput"), N.new("NodeGroupOutput")

    diff = N.new("ShaderNodeBsdfDiffuse")
    diff.inputs[0].default_value = (1, 1, 1, 1)
    s2r = N.new("ShaderNodeShaderToRGB")
    L.new(diff.outputs[0], s2r.inputs[0])
    bw = N.new("ShaderNodeRGBToBW")
    L.new(s2r.outputs[0], bw.inputs[0])
    # specular glint: glossy through its own Shader->RGB, thresholded later
    gl = N.new("ShaderNodeBsdfGlossy")
    gl.inputs["Roughness"].default_value = 0.3
    s2g = N.new("ShaderNodeShaderToRGB")
    L.new(gl.outputs[0], s2g.inputs[0])
    gbw = N.new("ShaderNodeRGBToBW")
    L.new(s2g.outputs[0], gbw.inputs[0])

    def math(op, a, b=None, clamp=False):
        m = N.new("ShaderNodeMath")
        m.operation = op
        m.use_clamp = clamp
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                m.inputs[i].default_value = v
            else:
                L.new(v, m.inputs[i])
        return m.outputs[0]

    lum = bw.outputs[0]
    # screen-space pattern coordinates, so hatching/dots read like print, not like a texture
    tc = N.new("ShaderNodeTexCoord")
    mp = N.new("ShaderNodeMapping")
    mp.inputs["Rotation"].default_value = (0, 0, math_rad(45))
    mp.inputs["Scale"].default_value = (1.0, 0.75, 1.0)
    L.new(tc.outputs["Window"], mp.inputs[0])
    wave = N.new("ShaderNodeTexWave")
    wave.wave_profile = "SAW"
    wave.inputs["Scale"].default_value = 45
    wave.inputs["Distortion"].default_value = 0.6
    wave.inputs["Detail"].default_value = 0
    L.new(mp.outputs[0], wave.inputs["Vector"])
    hatch = math("LESS_THAN", wave.outputs["Fac"], 0.42)          # 1 = ink line
    mp2 = N.new("ShaderNodeMapping")
    mp2.inputs["Rotation"].default_value = (0, 0, math_rad(-45))
    mp2.inputs["Scale"].default_value = (1.0, 0.75, 1.0)
    L.new(tc.outputs["Window"], mp2.inputs[0])
    wave2 = N.new("ShaderNodeTexWave")
    wave2.wave_profile = "SAW"
    wave2.inputs["Scale"].default_value = 45
    wave2.inputs["Distortion"].default_value = 0.6
    wave2.inputs["Detail"].default_value = 0
    L.new(mp2.outputs[0], wave2.inputs["Vector"])
    hatch2 = math("LESS_THAN", wave2.outputs["Fac"], 0.35)
    vor = N.new("ShaderNodeTexVoronoi")
    vor.inputs["Scale"].default_value = 85
    vor.inputs["Randomness"].default_value = 0.0
    L.new(mp.outputs[0], vor.inputs["Vector"])
    # dot radius grows as light falls: 0.55 lum -> no dots, 0.45 -> big dots
    rad = math("MULTIPLY", math("SUBTRACT", 0.6, lum, clamp=True), 2.6)
    dots = math("LESS_THAN", vor.outputs["Distance"], rad)

    shadow = math("LESS_THAN", lum, 0.30)
    dark = math("LESS_THAN", lum, 0.45)
    lit = math("GREATER_THAN", lum, 0.86)
    glint = math("GREATER_THAN", gbw.outputs[0], 0.55)

    def mix(fac, a, b):
        m = N.new("ShaderNodeMix")
        m.data_type = "RGBA"
        L.new(fac, m.inputs["Factor"])
        for sock, v in ((m.inputs[6], a), (m.inputs[7], b)):
            if isinstance(v, tuple):
                sock.default_value = v
            else:
                L.new(v, sock)
        return m.outputs[2]

    base = gi.outputs["Base"]
    darker = N.new("ShaderNodeMix")
    darker.data_type = "RGBA"
    darker.blend_type = "MULTIPLY"
    darker.inputs["Factor"].default_value = 1
    L.new(base, darker.inputs[6])
    darker.inputs[7].default_value = (0.38, 0.38, 0.42, 1)
    lighter = N.new("ShaderNodeMix")
    lighter.data_type = "RGBA"
    lighter.inputs["Factor"].default_value = 0.6
    L.new(base, lighter.inputs[6])
    lighter.inputs[7].default_value = (1, 1, 1, 1)

    c = mix(dots, base, darker.outputs[2])                         # mid band, halftone toward the terminator
    c = mix(dark, c, mix(math("MAXIMUM", hatch, hatch2), darker.outputs[2], BLACK))  # cross-hatched dark band
    c = mix(shadow, c, BLACK)                                      # spotted blacks
    c = mix(lit, c, lighter.outputs[2])
    c = mix(glint, c, (1, 1, 1, 1))
    # battle wear: sparse ink scratches from thin noise contours in object space
    nz = N.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 14
    nz.inputs["Detail"].default_value = 3
    nz.inputs["Distortion"].default_value = 1.5
    L.new(tc.outputs["Object"], nz.inputs["Vector"])
    scratch = math("LESS_THAN", math("ABSOLUTE", math("SUBTRACT", nz.outputs["Fac"], 0.5)), 0.0012)
    c = mix(scratch, c, BLACK)
    em = N.new("ShaderNodeEmission")
    L.new(c, em.inputs[0])
    L.new(em.outputs[0], go.inputs[0])
    return g


def math_rad(d):
    return math.radians(d)


def toon(name, col):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    grp = nt.nodes.new("ShaderNodeGroup")
    grp.node_tree = toon_group()
    grp.inputs["Base"].default_value = col
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(grp.outputs[0], out.inputs[0])
    m.diffuse_color = col
    return m


def ink_mat():
    if "Ink" in bpy.data.materials:
        return bpy.data.materials["Ink"]
    m = bpy.data.materials.new("Ink")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = BLACK
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs[0])
    m.use_backface_culling = True
    m.diffuse_color = BLACK
    return m


# ---------------------------------------------------------------- geometry helpers

def obj_from_bm(bm, name, collection, mat, bevel=0.0012, segs=2, hull=0.0012):
    me = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll(collection).objects.link(ob)
    me.materials.append(mat)
    me.materials.append(ink_mat())
    for p in me.polygons:
        p.use_smooth = False
    if bevel:
        b = ob.modifiers.new("Bevel", "BEVEL")
        b.width = bevel
        b.segments = segs
        b.limit_method = "ANGLE"
        b.angle_limit = math.radians(35)
        b.miter_outer = "MITER_ARC"
    if hull:
        s = ob.modifiers.new("InkHull", "SOLIDIFY")
        s.thickness = hull
        s.offset = 1
        s.use_flip_normals = True
        s.use_rim = False
        s.material_offset = 1
    return ob


def prism(pts, y0, y1, bm=None):
    """Extrude a closed (x, z) outline between y0 and y1."""
    bm = bm or bmesh.new()
    a = [bm.verts.new((x, y0, z)) for x, z in pts]
    b = [bm.verts.new((x, y1, z)) for x, z in pts]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    n = len(pts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], a[j], b[j], b[i]))
    return bm


def box(c, s, bm=None):
    bm = bm or bmesh.new()
    r = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=s, verts=r["verts"])
    bmesh.ops.translate(bm, vec=c, verts=r["verts"])
    return bm


def cyl(c, r, depth, axis="X", segs=24, bm=None, r2=None):
    bm = bm or bmesh.new()
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r,
                                radius2=r if r2 is None else r2, depth=depth)
    rot = {"X": Matrix.Rotation(math.pi / 2, 3, "Y"), "Y": Matrix.Rotation(math.pi / 2, 3, "X"),
           "Z": Matrix.Identity(3)}[axis]
    bmesh.ops.rotate(bm, verts=res["verts"], matrix=rot)
    bmesh.ops.translate(bm, vec=c, verts=res["verts"])
    return bm


def screw(c, r=0.0042, axis="Y", sign=1, bm=None):
    """Domed screw head with a slot, facing +axis*sign."""
    bm = bm or bmesh.new()
    d = Vector({"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[axis]) * sign
    cyl(Vector(c) + d * 0.0012, r, 0.0024, axis, 12, bm, r2=r * 0.75)
    slot = Vector((0.0009, 0.0009, 0.0009))
    s = Vector((r * 1.7, r * 1.7, r * 1.7))
    for i in range(3):
        if d[i]:
            s[i] = 0.0016
        elif i == 2 or (axis == "Z" and i == 0):
            s[i] = 0.0011
    box(Vector(c) + d * 0.0026, s, bm)
    return bm


def join_bm(*bms):
    out = bmesh.new()
    for b in bms:
        me = bpy.data.meshes.new("_tmp")
        b.to_mesh(me)
        out.from_mesh(me)
        bpy.data.meshes.remove(me)
        b.free()
    return out


def boolean(ob, cutter_bm, op="DIFFERENCE"):
    cme = bpy.data.meshes.new("_cut")
    cutter_bm.to_mesh(cme)
    cutter_bm.free()
    cut = bpy.data.objects.new("_cut", cme)
    bpy.context.scene.collection.objects.link(cut)
    m = ob.modifiers.new("Bool", "BOOLEAN")
    m.object = cut
    m.operation = op
    m.solver = "EXACT"
    # move it ahead of bevel/hull and apply
    while ob.modifiers.find("Bool") > 0:
        with bpy.context.temp_override(object=ob):
            bpy.ops.object.modifier_move_up(modifier="Bool")
    with bpy.context.temp_override(object=ob, active_object=ob):
        bpy.ops.object.modifier_apply(modifier="Bool")
    bpy.data.objects.remove(cut)
    bpy.data.meshes.remove(cme)
    while len(ob.data.materials) > 2:  # the exact solver appends the cutter's empty slot
        ob.data.materials.pop(index=len(ob.data.materials) - 1)


# ---------------------------------------------------------------- layout (m)
CYL_C = Vector((0.0, 0.0, 0.052))   # cylinder centre
CYL_R, CYL_L = 0.036, 0.066
BORE_Z = 0.062                      # shroud axis sits above the cylinder axis, like the reference
SH_X0, SH_X1, SH_R = 0.052, 0.17, 0.045


def build_shroud():
    m = toon("M_Red", RED)
    # octagon profile, slightly taller than wide, flat front
    oct_pts = [(SH_R * math.cos(math.radians(22.5 + 45 * i)) * 0.92,
                SH_R * math.sin(math.radians(22.5 + 45 * i))) for i in range(8)]
    bm = bmesh.new()
    back = [bm.verts.new((SH_X0, y, z + BORE_Z)) for y, z in oct_pts]
    front = [bm.verts.new((SH_X1, y * 0.94, z * 0.94 + BORE_Z)) for y, z in oct_pts]
    bm.faces.new(list(reversed(back)))
    ff = bm.faces.new(front)
    for i in range(8):
        j = (i + 1) % 8
        bm.faces.new((back[i], back[j], front[j], front[i]))
    # front ring step + deep muzzle
    r = bmesh.ops.inset_individual(bm, faces=[ff], thickness=0.006, depth=-0.004)
    bm.faces.ensure_lookup_table()
    r2 = bmesh.ops.inset_individual(bm, faces=[ff], thickness=0.011, depth=0.0)
    r3 = bmesh.ops.inset_individual(bm, faces=[ff], thickness=0.0, depth=-0.03)
    # side panels: recessed panel on both flat sides
    side_faces = [f for f in bm.faces if abs(f.normal.y) > 0.9 and f is not ff]
    bmesh.ops.inset_individual(bm, faces=side_faces, thickness=0.009, depth=-0.0025)
    ob = obj_from_bm(bm, "Shroud_Body", "03_Shroud", m)
    # round the muzzle bore: cut a true cylinder through the octagon hole
    boolean(ob, cyl((SH_X1 - 0.02, 0, BORE_Z), 0.0145, 0.06, "X", 24))
    # ink the whole muzzle well (inner octagon walls + bore) solid black
    for poly in ob.data.polygons:
        c = poly.center
        if c.x < SH_X1 - 0.006 and math.hypot(c.y, c.z - BORE_Z) < 0.031:
            poly.material_index = 1
    bore = obj_from_bm(cyl((SH_X1 - 0.035, 0, BORE_Z), 0.0146, 0.002, "X", 24), "Shroud_BoreBottom",
                       "03_Shroud", ink_mat(), bevel=0, hull=0)

    # under-lug: angular wedge under the shroud (hides the ejector rod)
    lug = prism([(SH_X0 + 0.012, BORE_Z - 0.03), (SH_X1 - 0.008, BORE_Z - 0.03),
                 (SH_X1 - 0.008, BORE_Z - 0.052), (SH_X1 - 0.03, BORE_Z - 0.066),
                 (SH_X0 + 0.045, BORE_Z - 0.066), (SH_X0 + 0.012, BORE_Z - 0.045)], -0.019, 0.019)
    obj_from_bm(lug, "Shroud_UnderLug", "03_Shroud", m)

    # front sight blade
    obj_from_bm(prism([(SH_X1 - 0.03, BORE_Z + 0.04), (SH_X1 - 0.004, BORE_Z + 0.04),
                       (SH_X1 - 0.008, BORE_Z + 0.054), (SH_X1 - 0.026, BORE_Z + 0.054)], -0.004, 0.004),
                "Shroud_Sight", "03_Shroud", m)

    # rivets along the upper/lower side chamfers and on the panels
    rv = bmesh.new()
    for x in (SH_X0 + 0.016, SH_X0 + 0.05, SH_X0 + 0.085, SH_X1 - 0.014):
        for sgn in (-1, 1):
            screw((x, sgn * 0.040, BORE_Z + 0.028), 0.0038, "Y", sgn, rv)
            screw((x, sgn * 0.040, BORE_Z - 0.028), 0.0038, "Y", sgn, rv)
    for x in (SH_X0 + 0.03, SH_X1 - 0.04):
        for sgn in (-1, 1):
            screw((x, sgn * 0.0195, BORE_Z - 0.052), 0.0034, "Y", sgn, rv)
    obj_from_bm(rv, "Shroud_Rivets", "03_Shroud", m, bevel=0, hull=0.0008)


def build_cylinder():
    m = toon("M_Teal", TEAL)
    x0, x1 = CYL_C.x - CYL_L / 2, CYL_C.x + CYL_L / 2
    bm = cyl(CYL_C, CYL_R, CYL_L, "X", 36)
    ob = obj_from_bm(bm, "Cylinder_Drum", "02_Cylinder", m)
    # six fat round flutes, stopping short of the rear face
    cut = bmesh.new()
    for i in range(6):
        a = math.radians(30 + 60 * i)
        c = CYL_C + Vector((0.004, math.cos(a) * CYL_R * 1.02, math.sin(a) * CYL_R * 1.02))
        cyl(c, 0.0105, CYL_L * 0.62, "X", 16, cut)
    boolean(ob, cut)
    # front chamfer ring + rear ratchet star
    ring = cyl((x1 + 0.0015, 0, CYL_C.z), CYL_R * 0.9, 0.003, "X", 36)
    obj_from_bm(ring, "Cylinder_FrontRing", "02_Cylinder", m, hull=0.0008)
    rat = bmesh.new()
    pts = []
    for i in range(12):
        a = math.radians(30 * i)
        rr = 0.016 if i % 2 == 0 else 0.011
        pts.append((math.cos(a) * rr, math.sin(a) * rr))
    a_ = [rat.verts.new((x0 - 0.0005, y, z + CYL_C.z)) for y, z in pts]
    b_ = [rat.verts.new((x0 - 0.004, y, z + CYL_C.z)) for y, z in pts]
    rat.faces.new(a_)
    rat.faces.new(list(reversed(b_)))
    for i in range(12):
        j = (i + 1) % 12
        rat.faces.new((a_[i], a_[j], b_[j], b_[i]))
    obj_from_bm(rat, "Cylinder_Ratchet", "02_Cylinder", toon("M_Steel", STEEL), bevel=0.0005, hull=0.0006)
    # axis pin (centre) and ejector rod running forward into the under-lug
    obj_from_bm(cyl((x1 + 0.01, 0, CYL_C.z), 0.0062, 0.022, "X", 16), "Cylinder_Axis", "02_Cylinder",
                toon("M_Steel", STEEL), hull=0.0008)
    # cylinder stop notches on the rear rim (small dark slots)
    notch = bmesh.new()
    for i in range(6):
        a = math.radians(60 * i)
        box((x0 + 0.008, math.cos(a) * (CYL_R + 0.0002), CYL_C.z + math.sin(a) * (CYL_R + 0.0002)),
            (0.006, 0.0035 if abs(math.cos(a)) < 0.6 else 0.0012, 0.0035 if abs(math.cos(a)) >= 0.6 else 0.0012),
            notch)
    obj_from_bm(notch, "Cylinder_StopNotches", "02_Cylinder", ink_mat(), bevel=0, hull=0)


def build_receiver():
    m = toon("M_Steel", STEEL)
    T = 0.017
    x0, x1 = CYL_C.x - CYL_L / 2, CYL_C.x + CYL_L / 2
    # one side outline with the cylinder window cut out by boolean afterwards
    pts = [(-0.098, 0.074), (-0.07, 0.098), (SH_X0 + 0.004, 0.103), (SH_X0 + 0.004, 0.022),
           (0.03, 0.012), (0.03, -0.006),
           (-0.052, -0.006), (-0.062, -0.016), (-0.09, -0.02), (-0.11, 0.02), (-0.112, 0.05)]
    bm = prism(pts, -T, T)
    ob = obj_from_bm(bm, "Receiver_Frame", "01_Receiver", m)
    boolean(ob, box((CYL_C.x, 0, CYL_C.z), (CYL_L + 0.002, 0.2, CYL_R * 2 + 0.003)))
    # top strap swelling over the window + rear sight groove
    obj_from_bm(prism([(x0 - 0.004, 0.09), (x1 + 0.004, 0.092), (x1 + 0.004, 0.103), (x0 - 0.01, 0.103)],
                      -0.012, 0.012), "Receiver_TopStrap", "01_Receiver", m)
    # trigger guard: chunky D ring
    outer, inner = [], []
    for i in range(19):
        a = math.radians(180 + 10 * i)
        outer.append((math.cos(a) * 0.034, -0.004 + math.sin(a) * 0.04))
        inner.append((math.cos(a) * 0.022, -0.004 + math.sin(a) * 0.028))
    g = prism(outer + list(reversed(inner)), -0.008, 0.008)  # one concave outline, no internal faces
    obj_from_bm(g, "Receiver_TriggerGuard", "01_Receiver", m)
    # crane / yoke plate on the left (-Y) side, plus release latch
    obj_from_bm(prism([(x1 - 0.002, 0.02), (SH_X0 + 0.003, 0.02), (SH_X0 + 0.003, 0.004), (x1 - 0.016, 0.004)],
                      -T - 0.003, -T + 0.001), "Receiver_Crane", "01_Receiver", m, hull=0.0008)
    obj_from_bm(prism([(-0.062, 0.058), (-0.04, 0.058), (-0.04, 0.05), (-0.058, 0.046), (-0.064, 0.05)],
                      -T - 0.005, -T + 0.001), "Receiver_Latch", "01_Receiver", toon("M_Teal", TEAL),
                hull=0.0008)
    # side plate seam (thin inked groove) and screws on both sides
    seam = bmesh.new()
    for sgn in (-1, 1):
        y = sgn * (T + 0.0004)
        box((-0.07, y, 0.035), (0.0012, 0.0012, 0.08), seam)
        box((-0.045, y, -0.001), (0.05, 0.0012, 0.0012), seam)
    obj_from_bm(seam, "Receiver_PlateSeams", "01_Receiver", ink_mat(), bevel=0, hull=0)
    sc = bmesh.new()
    for x, z in ((-0.088, 0.072), (-0.05, -0.0), (0.018, 0.004), (-0.082, 0.004), (SH_X0 - 0.006, 0.096)):
        for sgn in (-1, 1):
            screw((x, sgn * T, z), 0.0046, "Y", sgn, sc)
    obj_from_bm(sc, "Receiver_Screws", "01_Receiver", m, bevel=0, hull=0.0008)


def grip_frame(t):
    """Curved spine of the grip (x, z bezier) -> centre, front normal N (in XZ), tangent T."""
    p0, p1, p2 = Vector((-0.086, 0, 0.014)), Vector((-0.086, 0, -0.085)), Vector((-0.12, 0, -0.152))
    c = (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t * t * p2
    T = (2 * (1 - t) * (p1 - p0) + 2 * t * (p2 - p1)).normalized()
    N = Vector((-T.z, 0, T.x))  # rotate T by +90 in XZ -> points to the gun's front (+X)
    if N.x < 0:
        N = -N
    return c, N, T


def grip_ring(t, a, grow=0.0):
    """Point on the grip surface: superellipse section, palm swell, finger bumps, flared butt."""
    c, N, T = grip_frame(t)
    w = 0.054 + 0.009 * math.sin(math.pi * min(t, 1) * 0.9) + 0.006 * max(t, 0) ** 4   # front-back depth
    d = 0.043 + 0.009 * math.sin(math.pi * min(t, 1))                                   # side-side thickness
    ca, sa = math.cos(a), math.sin(a)
    ex = 2 / 3.2  # superellipse: chunky, not a tube
    sx = math.copysign(abs(ca) ** ex, ca)
    sy = math.copysign(abs(sa) ** ex, sa)
    front = 0.0
    if ca > 0 and 0.12 < t < 0.78:  # three finger swells on the front strap
        front = 0.0028 * max(0.0, math.sin(math.pi * 3 * (t - 0.12) / 0.66)) * ca
    return c + N * ((w / 2 + front) * sx + grow * sx) + Vector((0, 1, 0)) * ((d / 2) * sy + grow * sy)


def build_grip():
    t_ = toon("M_Teal", TEAL)
    yel = toon("M_Yellow", YELLOW)
    R, S = 26, 32
    bm = bmesh.new()
    rings = []
    for i in range(R + 1):
        t = i / R
        rings.append([bm.verts.new(grip_ring(t, 2 * math.pi * j / S)) for j in range(S)])
    # rounded butt: two shrinking rings along the spine, then a fan
    c, N, T = grip_frame(1.0)
    for k, (off, sc) in enumerate(((0.005, 0.86), (0.0085, 0.55))):
        ring = []
        for j in range(S):
            p = grip_ring(1.0, 2 * math.pi * j / S)
            ring.append(bm.verts.new(c + (p - c) * sc + T * off))
        rings.append(ring)
    tip = bm.verts.new(c + T * 0.0098)
    for r0, r1 in zip(rings, rings[1:]):
        for j in range(S):
            k = (j + 1) % S
            bm.faces.new((r0[j], r0[k], r1[k], r1[j]))
    for j in range(S):
        bm.faces.new((rings[-1][j], rings[-1][(j + 1) % S], tip))
    bm.faces.new(list(reversed(rings[0])))  # top cap, hidden in the frame
    ob = obj_from_bm(bm, "Grip_Body", "04_Grip", t_, bevel=0, hull=0.0014)
    for poly in ob.data.polygons:
        poly.use_smooth = True

    def shell(name, t0, t1, a0, a1, mat, rows=14, cols=10, inset=0.12):
        """Curved panel lying on the grip surface, with rounded-off ends, thickened by Solidify."""
        b = bmesh.new()
        grid = []
        for i in range(rows + 1):
            u = i / rows
            t = t0 + (t1 - t0) * u
            row = []
            for j in range(cols + 1):
                v = j / cols
                # pinch the panel's ends so it reads as an inlaid pad, not a band
                pinch = 1 - inset * (1 - math.sin(math.pi * u) ** 0.5)
                am = (a0 + a1) / 2
                a = am + (a1 - a0) / 2 * (2 * v - 1) * pinch
                row.append(b.verts.new(grip_ring(t, a, grow=0.0006)))
            grid.append(row)
        for i in range(rows):
            for j in range(cols):
                b.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
        o = obj_from_bm(b, name, "04_Grip", mat, bevel=0, hull=0)
        sol = o.modifiers.new("Thick", "SOLIDIFY")
        sol.thickness = 0.0032
        sol.offset = 1
        o.modifiers.move(o.modifiers.find("Thick"), 0)
        h = o.modifiers.new("InkHull", "SOLIDIFY")
        h.thickness, h.offset, h.use_flip_normals, h.use_rim, h.material_offset = 0.001, 1, True, False, 1
        for poly in o.data.polygons:
            poly.use_smooth = True
        return o

    # side inserts face +-Y (a = +-90 deg), back strap faces the rear (a = 180 deg)
    shell("Grip_Insert_R", 0.2, 0.86, math.radians(64), math.radians(116), yel, inset=0.3)
    shell("Grip_Insert_L", 0.2, 0.86, math.radians(244), math.radians(296), yel, inset=0.3)
    shell("Grip_BackStrap", 0.1, 0.96, math.radians(160), math.radians(200), yel, cols=6, inset=0.0)
    # grip screw through the left/right panels
    sc = bmesh.new()
    for sgn in (-1, 1):
        p = grip_ring(0.55, math.radians(90 * sgn), grow=0.0036)
        screw((p.x, p.y, p.z), 0.0052, "Y", sgn, sc)
    obj_from_bm(sc, "Grip_Screw", "04_Grip", toon("M_Steel", STEEL), bevel=0, hull=0.0008)


def build_controls():
    y = toon("M_Yellow", YELLOW)
    # hammer: big spur sticking up/back, serrated top
    ham = [(-0.09, 0.05), (-0.086, 0.088), (-0.108, 0.11), (-0.142, 0.118), (-0.146, 0.106), (-0.122, 0.096),
           (-0.104, 0.07), (-0.1, 0.05)]  # base buried in the frame's rear
    obj_from_bm(prism(ham, -0.007, 0.007), "Hammer", "05_Controls", y, bevel=0.0012)
    ser = bmesh.new()
    for i in range(5):
        x = -0.138 + i * 0.0068
        z = 0.118 - (0.118 - 0.106) * 0 + (0.0 if i else 0)
        box((x, 0, 0.1185 - i * 0.0012), (0.0025, 0.016, 0.004), ser)
    obj_from_bm(ser, "Hammer_Serrations", "05_Controls", y, bevel=0, hull=0.0006)
    # trigger: curved blade
    tr = []
    for i in range(9):
        a = i / 8
        tr.append((0.004 - 0.012 * a - 0.006 * math.sin(a * math.pi), -0.002 - 0.036 * a))
    back = [(px - 0.009 + 0.004 * (k / 8), pz) for k, (px, pz) in enumerate(tr)]
    obj_from_bm(prism(tr + list(reversed(back)), -0.0055, 0.0055), "Trigger", "05_Controls", y, bevel=0.001)


def build_fx():
    sc = bpy.context.scene
    # cameras
    cs = bpy.data.cameras.new("Cam_Side_Ortho")
    cs.type = "ORTHO"
    cs.ortho_scale = 0.46
    co = bpy.data.objects.new("Cam_Side_Ortho", cs)
    co.location = (0.005, -1.0, -0.02)
    co.rotation_euler = (math.radians(90), 0, 0)
    ch = bpy.data.cameras.new("Cam_Hero_3_4")
    ch.lens = 35
    ho = bpy.data.objects.new("Cam_Hero_3_4", ch)
    ho.location = (0.34, -0.34, 0.065)
    for o in (co, ho):
        coll("07_Studio_Lights_Camera").objects.link(o)
    tgt = Vector((0.012, 0.0, 0.002))
    ho.rotation_euler = (tgt - ho.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = ho
    # lights: hard key sun from top-front-left, coloured rim area below/behind
    sun = bpy.data.lights.new("Key_Sun", "SUN")
    sun.energy = 2.8  # full-facing ~0.89 lum: highlight band only on faces square to the sun
    sun.angle = 0.0
    so = bpy.data.objects.new("Key_Sun", sun)
    so.rotation_euler = (-Vector((0.45, -0.7, 0.6))).to_track_quat("-Z", "Y").to_euler()
    rim = bpy.data.lights.new("Rim_Area", "AREA")
    rim.energy = 25
    rim.size = 0.3
    rim.color = (1.0, 0.55, 0.25)
    ro = bpy.data.objects.new("Rim_Area", rim)
    ro.location = (-0.3, 0.35, -0.25)
    ro.rotation_euler = (Vector((0, 0, 0)) - ro.location).to_track_quat("-Z", "Y").to_euler()
    for o in (so, ro):
        coll("07_Studio_Lights_Camera").objects.link(o)


def build_lineart():
    """Grease Pencil Line Art for creases/intersections on top of the inverted hull silhouette."""
    sc = bpy.context.scene
    try:
        gp = bpy.data.grease_pencils_v3.new("Ink_LineArt")
    except AttributeError:
        gp = bpy.data.grease_pencils.new("Ink_LineArt")
    ob = bpy.data.objects.new("Ink_LineArt", gp)
    coll("06_Line_Art_And_FX").objects.link(ob)
    lay = gp.layers.new("Lines")
    mat = bpy.data.materials.new("GP_Ink")
    bpy.data.materials.create_gpencil_data(mat)
    mat.grease_pencil.color = BLACK
    gp.materials.append(mat)
    md = ob.modifiers.new("LineArt", "LINEART")
    md.source_type = "SCENE"
    md.target_layer = lay.name
    md.target_material = mat
    md.radius = 0.0008  # GPv3: world-space radius, not pixels
    md.use_contour = True
    md.use_crease = True
    md.crease_threshold = math.radians(140)
    md.use_intersection = True
    md.use_material = False
    md.use_edge_mark = False
    md.use_loose = False
    # the ink hulls / bore caps would draw doubled lines
    for n in ("06_Line_Art_And_FX", "07_Studio_Lights_Camera"):
        coll(n).lineart_usage = "EXCLUDE"
    try:
        nm = ob.modifiers.new("Wobble", "GREASE_PENCIL_NOISE")
        nm.factor = 0.0012  # tiny: hand-drawn wobble, not scribble
        nm.factor_thickness = 0.35
        nm.noise_scale = 0.6
    except Exception as e:
        print("noise modifier skipped:", e)
    return ob


def finish():
    for ob in bpy.data.objects:
        if ob.type == "MESH":
            ob.data.validate()
    print({c: len(coll(c).objects) for c in COLLS})


def build(save=True):
    reset()
    build_shroud()
    build_cylinder()
    build_receiver()
    build_grip()
    build_controls()
    build_fx()
    try:
        build_lineart()
    except Exception as e:
        print("line art failed:", repr(e))
    finish()
    if save:
        bpy.ops.wm.save_as_mainfile(filepath=OUT)
