# The PLAY animation of the main menu, keyframed in Blender: the avatar on its chair hears the click,
# pumps a fist, leans, stands up, takes its headphones off, cracks its neck, turns round and struts off
# into the arena while the camera follows it in and pushes into the back of its head (first person).
#
#   blender -b -P assets/menu/play_intro.py -- [--save assets/menu/play_intro.blend]
#                                               [--frames DIR] [--bake src/client/PlayIntro.luau]
#
# --save   the scene: an R15 proxy (the real rig's joints, measured off a player's character in Studio),
#          the menu's chair, the keyed action and the keyed camera. Edit the keys there and run --bake.
# --frames every frame as DIR/NNNN.png at 1280x720 (assets/menu/make_mp4.sh turns them into the MP4).
# --bake   the clip as Luau data for client/MenuPuppet: per frame the root, 14 joint rotations and the
#          camera, all in the menu scene's own space (Roblox axes, before its 28-degree turn).
#
# Poses are written in the menu's own convention (MenuPuppet: shoulder / hip +X swings the limb
# forward, elbow +X bends it, knee -X bends it, waist -X bends forward; left mirrors y and z) and keyed
# onto the bones through the axis change, so the bake reads back exactly what was keyed.
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

FPS = 30
LEAD = 15  # frames of sitting before the click, in the MP4 only (the clip starts at the click)
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def opt(name):
    return argv[argv.index(name) + 1] if name in argv else None


# Roblox <-> Blender axes. Roblox: +Y up, the character faces -Z. Blender: +Z up, faces -Y.
# C maps either way (it is its own inverse): (x, y, z) -> (-x, z, y).
C = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))


def to_b(p):
    return C @ Vector(p)


# The R15 rig, measured in Studio (attachment positions in their part, all unrotated) ------------------
ATT = {  # part: {attachment: position}
    "HumanoidRootPart": {"Root": (0, -1, 0)},
    "LowerTorso": {"Root": (0, -0.328, -0.02), "Waist": (0, 0.072, -0.02), "LeftHip": (-0.5, -0.328, -0.02), "RightHip": (0.5, -0.328, -0.02)},
    "UpperTorso": {"Waist": (0, -0.65, 0.019), "Neck": (0, 0.95, 0.019), "LeftShoulder": (-0.916, 0.603, 0.019), "RightShoulder": (0.916, 0.603, 0.019)},
    "Head": {"Neck": (0, -0.586, 0.001)},
    "LeftUpperArm": {"LeftShoulder": (0.232, 0.339, -0.075), "LeftElbow": (-0.107, -0.239, -0.075)},
    "LeftLowerArm": {"LeftElbow": (0.139, 0.295, 0.001), "LeftWrist": (-0.069, -0.45, -0.204)},
    "LeftHand": {"LeftWrist": (0.044, 0.234, 0.124)},
    "RightUpperArm": {"RightShoulder": (-0.232, 0.339, -0.075), "RightElbow": (0.106, -0.239, -0.075)},
    "RightLowerArm": {"RightElbow": (-0.14, 0.295, 0.001), "RightWrist": (0.068, -0.451, -0.204)},
    "RightHand": {"RightWrist": (-0.044, 0.233, 0.124)},
    "LeftUpperLeg": {"LeftHip": (-0.11, 0.436, -0.01), "LeftKnee": (-0.11, -0.523, -0.01)},
    "LeftLowerLeg": {"LeftKnee": (-0.08, 0.283, -0.01), "LeftAnkle": (-0.08, -0.285, -0.01)},
    "LeftFoot": {"LeftAnkle": (-0.08, 0.061, 0.184)},
    "RightUpperLeg": {"RightHip": (0.11, 0.436, -0.01), "RightKnee": (0.11, -0.523, -0.01)},
    "RightLowerLeg": {"RightKnee": (0.08, 0.284, -0.01), "RightAnkle": (0.08, -0.285, -0.01)},
    "RightFoot": {"RightAnkle": (0.08, 0.061, 0.185)},
}
SIZE = {
    "HumanoidRootPart": (2, 2, 1), "LowerTorso": (1.672, 0.632, 1.037), "UpperTorso": (1.839, 1.901, 1.073), "Head": (1.198, 1.202, 1.199),
    "LeftUpperArm": (0.942, 1.213, 0.759), "LeftLowerArm": (0.812, 1.161, 0.902), "LeftHand": (0.753, 0.891, 0.773),
    "RightUpperArm": (0.943, 1.213, 0.759), "RightLowerArm": (0.812, 1.161, 0.902), "RightHand": (0.753, 0.891, 0.773),
    "LeftUpperLeg": (0.781, 1.742, 0.854), "LeftLowerLeg": (0.721, 1.263, 0.854), "LeftFoot": (0.721, 0.82, 1.243),
    "RightUpperLeg": (0.781, 1.742, 0.854), "RightLowerLeg": (0.721, 1.263, 0.854), "RightFoot": (0.721, 0.82, 1.243),
}
HIP_HEIGHT = 2.0
# part, parent, joint attachment, pose key (MenuPuppet.JOINTS order: the bake writes them in this order)
JOINTS = [
    ("UpperTorso", "LowerTorso", "Waist", "waist"),
    ("Head", "UpperTorso", "Neck", "neck"),
    ("LeftUpperArm", "UpperTorso", "LeftShoulder", "lShoulder"),
    ("LeftLowerArm", "LeftUpperArm", "LeftElbow", "lElbow"),
    ("LeftHand", "LeftLowerArm", "LeftWrist", "lWrist"),
    ("RightUpperArm", "UpperTorso", "RightShoulder", "rShoulder"),
    ("RightLowerArm", "RightUpperArm", "RightElbow", "rElbow"),
    ("RightHand", "RightLowerArm", "RightWrist", "rWrist"),
    ("LeftUpperLeg", "LowerTorso", "LeftHip", "lHip"),
    ("LeftLowerLeg", "LeftUpperLeg", "LeftKnee", "lKnee"),
    ("LeftFoot", "LeftLowerLeg", "LeftAnkle", "lAnkle"),
    ("RightUpperLeg", "LowerTorso", "RightHip", "rHip"),
    ("RightLowerLeg", "RightUpperLeg", "RightKnee", "rKnee"),
    ("RightFoot", "RightLowerLeg", "RightAnkle", "rAnkle"),
]
STAND_Y = HIP_HEIGHT + SIZE["HumanoidRootPart"][1] / 2  # the root's height standing (MenuPuppet standY)

# rest centres of the parts (Roblox, root standing at (0, STAND_Y, 0)) and the joints' pivots
CENTRE = {"HumanoidRootPart": Vector((0, STAND_Y, 0))}
CENTRE["LowerTorso"] = CENTRE["HumanoidRootPart"] + Vector(ATT["HumanoidRootPart"]["Root"]) - Vector(ATT["LowerTorso"]["Root"])
PIVOT = {"LowerTorso": CENTRE["HumanoidRootPart"] + Vector(ATT["HumanoidRootPart"]["Root"])}
for part, parent, att, _ in JOINTS:
    PIVOT[part] = CENTRE[parent] + Vector(ATT[parent][att])
    CENTRE[part] = PIVOT[part] - Vector(ATT[part][att])

# the menu's chair and sitting root (MenuPuppet.new, same formulas)
HIP_Y = (PIVOT["LeftUpperLeg"] - CENTRE["HumanoidRootPart"]).y  # left hip relative to the root
THIGH = SIZE["LeftUpperLeg"][2]
SEAT_TOP = STAND_Y + HIP_Y - 0.6
SIT_ROOT = (0, SEAT_TOP + THIGH / 2 - HIP_Y, 0.45)
STAND_ROOT = (0, STAND_Y, -0.3)


# Poses in the menu's convention ----------------------------------------------------------------------
def pose(base=None, **keys):
    p = dict(base or {})
    for k, val in keys.items():
        if k.startswith("both"):  # bothHip=(x, y, z): right as given, left mirrored
            name = k[4:]
            p["r" + name] = val
            p["l" + name] = (val[0], -val[1], -val[2])
        else:
            p[k] = val
    return p


def V(x, y=0, z=0):
    return (x, y, z)


SIT = pose(root=(SIT_ROOT, 0), waist=V(-9), neck=V(2), bothHip=V(88, 0, 4), bothKnee=V(-62), bothAnkle=V(12),
           bothShoulder=V(27, 0, -7), bothElbow=V(8), bothWrist=V(10))


def at(p, dx=0, dy=0, dz=0, yaw=None):
    (x, y, z), w = p["root"]
    return ((x + dx, y + dy, z + dz), w if yaw is None else yaw)


KEYS = []  # (clip frame, pose)


def key(f, p):
    KEYS.append((f, p))


# lead-in (MP4 only): bobbing to the music
key(-LEAD, SIT)
key(-8, pose(SIT, neck=V(-10)))
# the click: a startle, then a fist pump
key(0, SIT)
key(3, pose(SIT, root=at(SIT, dy=0.12), waist=V(-2), neck=V(14), bothShoulder=V(18, 0, -14), bothElbow=V(25), bothWrist=V(0), bothKnee=V(-55)))
FIST_UP = pose(SIT, waist=V(-4, -12), neck=V(6, -8), rShoulder=V(120, 0, 25), rElbow=V(95), rWrist=V(0), bothKnee=V(-58))
key(8, FIST_UP)
key(12, pose(FIST_UP, waist=V(-14, 8), neck=V(-12, 6), rShoulder=V(35, 0, 10), rElbow=V(125), bothKnee=V(-72)))
key(16, pose(FIST_UP, waist=V(-10, 4), neck=V(-4), rShoulder=V(45, 0, 8), rElbow=V(110), bothKnee=V(-64)))
key(22, pose(SIT, waist=V(-12), neck=V(6), bothShoulder=V(30, 0, -7), bothElbow=V(10)))
# lean, push off the knees, stand (up on the toes for a moment), settle
LEAN = pose(SIT, root=at(SIT, dy=-0.03, dz=-0.1), waist=V(-40), neck=V(26), bothShoulder=V(15, 0, -8), bothElbow=V(20), bothWrist=V(-10),
            bothHip=V(95, 0, 4), bothKnee=V(-85), bothAnkle=V(28))
key(28, LEAN)
key(33, pose(LEAN, root=((0, SIT_ROOT[1] + 0.22, 0.15), 0), waist=V(-34), neck=V(22), bothHip=V(60, 0, 3), bothKnee=V(-60), bothAnkle=V(20),
             bothShoulder=V(-5, 0, -10), bothElbow=V(25)))
STAND = pose(root=(STAND_ROOT, 0), waist=V(-3), neck=V(2), bothHip=V(8, 0, 3), bothKnee=V(-14), bothAnkle=V(6),
             bothShoulder=V(6, 0, -6), bothElbow=V(15), bothWrist=V(0))
key(38, pose(STAND, root=at(STAND, dy=0.12, dz=0.05), waist=V(6), neck=V(-4), bothHip=V(-6, 0, 2), bothKnee=V(-2), bothAnkle=V(-14),
             bothShoulder=V(-28, 0, -10), bothElbow=V(25)))
key(45, STAND)
# adjust: headphones off (they fade, MenuPuppet.PHONES_OFF), neck cracked both ways, knuckles
key(51, pose(STAND, neck=V(4), bothShoulder=V(105, 0, 40), bothElbow=V(135), bothKnee=V(-10)))
key(56, pose(STAND, neck=V(-10), bothShoulder=V(130, 0, 45), bothElbow=V(120), bothKnee=V(-12)))
key(62, pose(STAND, neck=V(4, 0, 18), bothShoulder=V(-10, 0, 12), bothElbow=V(30)))
key(68, pose(STAND, neck=V(4, 0, -16), bothShoulder=V(4, 0, 6), bothElbow=V(20)))
key(73, pose(STAND, neck=V(0), waist=V(2), bothShoulder=V(28, 0, -4), bothElbow=V(95), bothWrist=V(-10)))
# turn round: wind up the other way, step round on the right foot, face the arena
key(78, pose(STAND, root=at(STAND, dy=-0.08, yaw=-18), waist=V(0, 14), bothKnee=V(-18), bothShoulder=V(8, 0, 8), bothElbow=V(30)))
key(84, pose(STAND, root=at(STAND, dy=-0.02, dz=0.05, yaw=95), waist=V(0, -10), rHip=V(28, 0, 4), rKnee=V(-48), rAnkle=V(10),
             lHip=V(-6, 0, -3), lKnee=V(-12), rShoulder=V(-15, 0, 10), lShoulder=V(20, 0, -10)))
key(90, pose(STAND, root=at(STAND, yaw=180), waist=V(2), bothHip=V(4, 0, 3), bothKnee=V(-8), bothShoulder=V(4, 0, 6)))
# the strut: chest out, chin up, arms swinging wide; 6 studs/s, a stride every 0.6 s
WALK_FROM, WALK_TO, WALK_SPEED, STRIDE = 92, 140, 6.0, 18


def walk_z(f):
    return STAND_ROOT[2] + WALK_SPEED * max(0, f - WALK_FROM) / FPS


for f in range(WALK_FROM, WALK_TO + 1, 3):
    p = (f - WALK_FROM) / STRIDE * 2 * math.pi
    a = min(1.0, (f - WALK_FROM + 3) / 9)  # the first step is shorter
    s = math.sin(p)
    key(f, pose(root=((0, STAND_Y - 0.06 + 0.1 * abs(math.cos(p)) * a, walk_z(f)), 180),
                waist=V(4 * a, 7 * s * a), neck=V(4, -5 * s * a),
                rHip=V(32 * s * a, 0, 3), lHip=V(-32 * s * a, 0, -3),
                rKnee=V(-(max(0, math.sin(p + 1.3)) * 55 + 6) * a), lKnee=V(-(max(0, math.sin(p + 1.3 + math.pi)) * 55 + 6) * a),
                rAnkle=V(10 * math.cos(p) * a), lAnkle=V(-10 * math.cos(p) * a),
                rShoulder=V(-30 * s * a, 0, 12), lShoulder=V(30 * s * a, 0, -12),
                rElbow=V(25 + 12 * max(0, s) * a), lElbow=V(25 + 12 * max(0, -s) * a), bothWrist=V(0)))
END = WALK_TO


# Camera keys (Roblox, the scene's own space) -----------------------------------------------------------
def look_at(eye, target):
    eye, target = Vector(eye), Vector(target)
    back = (eye - target).normalized()  # camera +Z
    right = Vector((0, 1, 0)).cross(back).normalized()
    up = back.cross(right)
    m = Matrix((right, up, back)).transposed().to_4x4()
    m.translation = eye
    return m


HEAD_UP = CENTRE["Head"].y - STAND_Y  # head centre above the root
HEAD_BACK = SIZE["Head"][2] / 2 + 0.3  # MenuPuppet.headBack: half its depth plus room for hair
CAMERA = [  # (frame, matrix, vertical fov): the whole chair in a 3/4 shot, a punch on the click, then he
    # turns his back on the camera and walks off into the arena, so the same camera follows him in
    (-LEAD, look_at((3.7, 4.3, -9.8), (0, 2.75, 0.3)), 38),
    (0, look_at((3.7, 4.3, -9.8), (0, 2.75, 0.3)), 38),
    (5, look_at((3.0, 4.1, -8.1), (0, 3.05, 0.3)), 33),
    (14, look_at((3.1, 4.15, -8.4), (0, 3.0, 0.3)), 34),
    (28, look_at((3.6, 4.3, -9.7), (0, 2.85, 0.2)), 37),
    (45, look_at((3.6, 4.6, -9.9), (0, 3.0, -0.3)), 37),
    (74, look_at((3.0, 4.8, -9.2), (0, 3.4, -0.3)), 36),
    (92, look_at((1.6, 4.9, -7.8), (0, 4.0, walk_z(92) + 4)), 40),
]
# then the menu's chase camera exactly (MenuPuppet.chaseCamera): d studs behind the back of the head,
# looking 8 ahead, d shrinking to 0 with the push-in while the field of view opens to the game's 70
HEAD_Y = STAND_Y + HEAD_UP
PUSH_FROM, CHASE_FAR = 116, 6.0
for f in range(100, END + 1, 2):
    z = walk_z(f)
    u = max(0.0, (f - PUSH_FROM) / (END - PUSH_FROM)) ** 2
    d = CHASE_FAR * (1 - u)
    side = 0.9 * (1 - u) * min(1.0, (f - 92) / 12)  # a little over the right shoulder until the push
    eye = Vector((side, HEAD_Y + d * 0.08 + 0.35 * (1 - u), z - (HEAD_BACK + d)))
    CAMERA.append((f, look_at(eye, (0, HEAD_Y, z + 8)), 42 + 3 * min(1.0, (f - 92) / 12) + 25 * u))
# the film only: a moment of first person after the clip (the game's own camera takes over here)
HOLD = 20
z = walk_z(END + HOLD)
CAMERA.append((END + HOLD, look_at((0, HEAD_Y, z - HEAD_BACK), (0, HEAD_Y, z + 8)), 70))


# Scene ------------------------------------------------------------------------------------------------
def material(name, rgb, outline=False):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs[0].default_value = (*[(c / 255) ** 2.2 for c in rgb], 1)
    bsdf.inputs["Roughness"].default_value = 0.6
    if outline:  # the inverted hull: drawn only from inside, and casting no shadow over what it wraps
        mat.use_backface_culling = True
        mat.use_backface_culling_shadow = True
    return mat


def block(name, size_r, centre_r, mat, bone=None, bevel=0.08, parent=None, ink=None):
    """A box of Roblox size at a Roblox centre, with a black inverted-hull outline."""
    sx, sy, sz = size_r
    bpy.ops.mesh.primitive_cube_add(size=1)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (sx, sz, sy)  # Roblox (x, y, z) sizes -> Blender (x, z, y)
    bpy.ops.object.transform_apply(scale=True)
    ob.location = to_b(centre_r)
    ob.data.materials.append(mat)
    ob.data.materials.append(ink or OUTLINE)
    if bevel:
        bv = ob.modifiers.new("Bevel", "BEVEL")
        bv.width, bv.segments = bevel, 2
    sol = ob.modifiers.new("Outline", "SOLIDIFY")
    sol.thickness, sol.offset, sol.use_flip_normals, sol.material_offset = 0.06, 1, True, 1
    if bone:
        # bone parenting is relative to the bone's tail in its rest pose; undo that with the parent inverse
        b = RIG.data.bones[bone]
        ob.parent, ob.parent_type, ob.parent_bone = RIG, "BONE", bone
        ob.matrix_parent_inverse = (RIG.matrix_world @ b.matrix_local @ Matrix.Translation((0, b.length, 0))).inverted()
    elif parent:  # an empty at the origin
        ob.parent = parent
    return ob


bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS
scene.frame_start, scene.frame_end = 1, LEAD + END + 1 + HOLD
OUTLINE = material("Outline", (12, 12, 16), outline=True)
CHAIR_INK = material("ChairOutline", (12, 12, 16), outline=True)
PHONE_INK = material("PhoneOutline", (12, 12, 16), outline=True)
HEAD_INK = material("HeadOutline", (12, 12, 16), outline=True)
SKIN = material("Skin", (255, 214, 170))
HEAD_SKIN = material("HeadSkin", (255, 214, 170))
FACE = material("Face", (20, 20, 24))
HOODIE = material("Hoodie", (40, 160, 170))
PANTS = material("Pants", (40, 50, 80))
SHOES = material("Shoes", (245, 245, 245))
WOOD, DARK_WOOD = material("Wood", (150, 96, 56)), material("DarkWood", (105, 64, 38))
GREY, DARKP, RED = material("PhoneBand", (70, 70, 80)), material("PhoneCup", (30, 30, 36)), material("PhoneRed", (232, 70, 56))

# armature: one bone per part from its joint, all pointing up with no roll (so their rest axes agree)
arm_data = bpy.data.armatures.new("R15")
RIG = bpy.data.objects.new("R15", arm_data)
scene.collection.objects.link(RIG)
bpy.context.view_layer.objects.active = RIG
bpy.ops.object.mode_set(mode="EDIT")
eb = arm_data.edit_bones
root = eb.new("HumanoidRootPart")
root.head, root.tail = to_b(CENTRE["HumanoidRootPart"]), to_b(CENTRE["HumanoidRootPart"]) + Vector((0, 0, 0.5))
lower = eb.new("LowerTorso")
lower.head, lower.tail, lower.parent = to_b(PIVOT["LowerTorso"]), to_b(PIVOT["LowerTorso"]) + Vector((0, 0, 0.3)), root
for part, parent, _, _ in JOINTS:
    b = eb.new(part)
    b.head, b.tail, b.parent = to_b(PIVOT[part]), to_b(PIVOT[part]) + Vector((0, 0, 0.3)), eb[parent]
    b.roll = 0
bpy.ops.object.mode_set(mode="OBJECT")
for pb in RIG.pose.bones:
    pb.rotation_mode = "QUATERNION"

LOOK = {"Head": HEAD_SKIN, "LeftHand": SKIN, "RightHand": SKIN, "UpperTorso": HOODIE, "LeftUpperArm": HOODIE, "RightUpperArm": HOODIE,
        "LeftLowerArm": HOODIE, "RightLowerArm": HOODIE, "LowerTorso": PANTS, "LeftUpperLeg": PANTS, "RightUpperLeg": PANTS,
        "LeftLowerLeg": PANTS, "RightLowerLeg": PANTS, "LeftFoot": SHOES, "RightFoot": SHOES}
for part, mat in LOOK.items():
    block("Body_" + part, SIZE[part], CENTRE[part], mat, bone=part, ink=HEAD_INK if part == "Head" else None)
# a face: two eyes and a grin
h = CENTRE["Head"]
for sx in (-0.22, 0.22):
    block("Eye", (0.14, 0.22, 0.04), h + Vector((sx, 0.12, -0.6)), FACE, bone="Head", bevel=0, ink=HEAD_INK)
block("Grin", (0.42, 0.08, 0.04), h + Vector((0, -0.22, -0.6)), FACE, bone="Head", bevel=0, ink=HEAD_INK)
# headphones (MenuPuppet's, same sizes) under an empty that fades them
hs = Vector(SIZE["Head"])
ear = hs.x / 2 + 0.1
phones = []
phones.append(block("Phone_Band", (hs.x + 0.32, 0.16, 0.26), h + Vector((0, hs.y / 2 + 0.06, 0)), GREY, bone="Head", bevel=0.03, ink=PHONE_INK))
for s in (-1, 1):
    phones.append(block("Phone_Arm", (0.14, hs.y * 0.5, 0.24), h + Vector((s * (ear + 0.06), hs.y * 0.28, 0)), GREY, bone="Head", bevel=0.03, ink=PHONE_INK))
    phones.append(block("Phone_Cup", (0.26, 0.66, 0.66), h + Vector((s * ear, 0, 0)), DARKP, bone="Head", bevel=0.1, ink=PHONE_INK))
    phones.append(block("Phone_Dot", (0.06, 0.4, 0.4), h + Vector((s * (ear + 0.14), 0, 0)), RED, bone="Head", bevel=0.05, ink=PHONE_INK))

# chair (MenuPuppet.new): seat, four legs, two back posts, two back rails
W, FRONT, BACK = 1.9, -0.2, 1.3
mid, depth = (FRONT + BACK) / 2, BACK - FRONT
chair = bpy.data.objects.new("Chair", None)
scene.collection.objects.link(chair)
block("Seat", (W, 0.28, depth), (0, SEAT_TOP - 0.14, mid), WOOD, parent=chair, bevel=0.04, ink=CHAIR_INK)
leg_x = W / 2 - 0.13
for x in (-leg_x, leg_x):
    for zz in (FRONT + 0.13, BACK - 0.13):
        block("ChairLeg", (0.22, SEAT_TOP - 0.28, 0.22), (x, (SEAT_TOP - 0.28) / 2, zz), DARK_WOOD, parent=chair, bevel=0.03, ink=CHAIR_INK)
    block("ChairPost", (0.22, 2.4, 0.22), (x, SEAT_TOP + 1.2, BACK - 0.13), DARK_WOOD, parent=chair, bevel=0.03, ink=CHAIR_INK)
block("ChairRail", (W - 0.1, 0.8, 0.18), (0, SEAT_TOP + 1.95, BACK - 0.13), WOOD, parent=chair, bevel=0.04, ink=CHAIR_INK)
block("ChairRail", (W - 0.1, 0.22, 0.18), (0, SEAT_TOP + 1.1, BACK - 0.13), WOOD, parent=chair, bevel=0.03, ink=CHAIR_INK)

# floor: the arena's dark blue, under everything; the menu's blue all round
me = bpy.data.meshes.new("Floor")
me.from_pydata([(-80, -80, 0), (80, -80, 0), (80, 80, 0), (-80, 80, 0)], [], [(0, 1, 2, 3)])
floor = bpy.data.objects.new("Floor", me)
scene.collection.objects.link(floor)
me.materials.append(material("Floor", (30, 48, 100)))
# the film only: big tiles and two rows of posts down the arena, so the walk reads as going somewhere
floor_mat = me.materials[0]
nodes = floor_mat.node_tree.nodes
checker = nodes.new("ShaderNodeTexChecker")
checker.inputs[1].default_value = (*[(c / 255) ** 2.2 for c in (34, 54, 112)], 1)
checker.inputs[2].default_value = (*[(c / 255) ** 2.2 for c in (26, 42, 88)], 1)
checker.inputs[3].default_value = 40  # 4-stud tiles over the 160-stud floor
floor_mat.node_tree.links.new(checker.outputs[0], next(n for n in nodes if n.type == "BSDF_PRINCIPLED").inputs[0])
POST, CAP = material("Post", (236, 120, 44)), material("PostCap", (250, 214, 80))
for zz in range(4, 60, 7):
    for x in (-6.5, 6.5):
        block("Post", (1.1, 5, 1.1), (x, 2.5, zz), POST, bevel=0.1)
        block("PostCap", (1.5, 0.4, 1.5), (x, 5.2, zz), CAP, bevel=0.08)
world = bpy.data.worlds.new("Menu")
world.use_nodes = True
bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs[0].default_value = (*[(c / 255) ** 2.2 for c in (40, 70, 140)], 1)
bg.inputs[1].default_value = 1.0
scene.world = world
for name, energy, direction in (("Key", 3.4, (-0.6, 0.8, -0.7)), ("Rim", 2.4, (0.5, -0.9, -0.3)), ("Fill", 0.9, (0.8, 0.6, -0.2))):
    ob = bpy.data.objects.new(name, bpy.data.lights.new(name, "SUN"))
    ob.data.energy = energy
    ob.rotation_euler = Vector(direction).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(ob)
try:
    scene.render.engine = "BLENDER_EEVEE"
except TypeError:
    pass
scene.view_settings.view_transform = "Standard"
scene.render.resolution_x, scene.render.resolution_y = 1280, 720

# Keys -------------------------------------------------------------------------------------------------
def euler(v):  # CFrame.Angles(x, y, z) in degrees, Roblox axes
    x, y, z = (math.radians(a) for a in v)
    return Matrix.Rotation(x, 3, "X") @ Matrix.Rotation(y, 3, "Y") @ Matrix.Rotation(z, 3, "Z")


def basis_quat(bone, joint_rbx):  # a joint rotation in Roblox axes -> the bone's own rotation
    rest = bone.bone.matrix_local.to_3x3()
    return (rest.transposed() @ C @ joint_rbx @ C @ rest).to_quaternion()


def bf(f):
    return f + LEAD + 1  # clip frame -> Blender frame


previous = {}
for f, p in sorted(KEYS, key=lambda k: k[0]):
    (rx, ry, rz), yaw = p["root"]
    rb = RIG.pose.bones["HumanoidRootPart"]
    rest = rb.bone.matrix_local
    rb.location = rest.to_3x3().transposed() @ (to_b((rx, ry, rz)) - rest.translation)
    targets = {"HumanoidRootPart": euler(V(0, yaw))}
    for part, _, _, k in JOINTS:
        targets[part] = euler(p.get(k, V(0)))
    for part, rot in targets.items():
        pb = RIG.pose.bones[part]
        q = basis_quat(pb, rot)
        if part in previous and previous[part].dot(q) < 0:
            q.negate()  # keep the shorter way round between keys
        previous[part] = q
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=bf(f))
    rb.keyframe_insert("location", frame=bf(f))
RIG.animation_data.action.name = "PlayIntro"
RIG.animation_data.action.use_fake_user = True

# fades, in clip frames: the chair as he gets up (he walks off through where it stood), the headphones as
# the hands lift them. The menu fades the same parts at the same moments (the bake writes them).
CHAIR_FADE = (36, 46)
PHONES_OFF = (55, 60)


def fade(mats, frames):
    for mat in mats:
        alpha = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Alpha"]
        for f, a in ((frames[0], 1.0), (frames[1], 0.0)):
            alpha.default_value = a
            alpha.keyframe_insert("default_value", frame=bf(f))
        alpha.default_value = 1.0


fade((WOOD, DARK_WOOD, CHAIR_INK), CHAIR_FADE)
fade((GREY, DARKP, RED, PHONE_INK), PHONES_OFF)
# the film only: as the camera reaches the back of the head the body goes, as a first-person camera hides it
fade((HEAD_SKIN, FACE, HEAD_INK, SKIN, HOODIE, PANTS, SHOES, OUTLINE), (END - 6, END - 2))

cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
scene.collection.objects.link(cam)
scene.camera = cam
cam.data.sensor_fit = "VERTICAL"
cam.data.sensor_height = 24
cam.data.clip_start = 0.05
cam.rotation_mode = "QUATERNION"
prev_q = None
for f, m, fov in CAMERA:
    rot = C @ m.to_3x3()
    q = rot.to_quaternion()
    if prev_q is not None and prev_q.dot(q) < 0:
        q.negate()
    prev_q = q
    cam.location = to_b(m.translation)
    cam.rotation_quaternion = q
    cam.data.lens = cam.data.sensor_height / 2 / math.tan(math.radians(fov) / 2)
    cam.keyframe_insert("location", frame=bf(f))
    cam.keyframe_insert("rotation_quaternion", frame=bf(f))
    cam.data.keyframe_insert("lens", frame=bf(f))


def fcurves_of(idb):
    ad = idb.animation_data
    if not ad or not ad.action:
        return []
    out = []
    try:
        for layer in ad.action.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    out.extend(cb.fcurves)
    except AttributeError:
        out = list(ad.action.fcurves)
    return out


# Ease: auto-clamped Bezier everywhere (no overshoot between keys); the camera's push into the head
# accelerates (ease in only), and the walk's own keys stay linear so the stride keeps its rhythm.
for idb in (RIG, cam, cam.data):
    for fc in fcurves_of(idb):
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = kp.handle_right_type = "AUTO_CLAMPED"
            if idb is RIG and kp.co.x > bf(WALK_FROM) and fc.data_path.endswith("location"):
                kp.interpolation = "LINEAR"
        fc.update()


# Outputs ----------------------------------------------------------------------------------------------
B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


def enc(x, lo, hi, chars):
    n = round((min(max(x, lo), hi) - lo) / (hi - lo) * (64 ** chars - 1))
    s = ""
    for _ in range(chars):
        s = B64[n % 64] + s
        n //= 64
    return s


def enc_quat(q):
    if q.w < 0:
        q = -q
    return "".join(enc(c, -1, 1, 2) for c in (q.x, q.y, q.z))


def bake(path):
    """Per clip frame 0..END: root position (3x3 chars, -32..32) and rotation (3x2), every joint's rotation
    (3x2 each, JOINTS order), the camera's position (3x3) and rotation (3x2) and vertical fov (2, 0..120)."""
    frames = []
    for f in range(0, END + 1):
        scene.frame_set(bf(f))
        rows = []
        mats = {pb.name: pb.matrix.to_3x3() @ pb.bone.matrix_local.to_3x3().transposed() for pb in RIG.pose.bones}
        rb = RIG.pose.bones["HumanoidRootPart"]
        p = C @ rb.head
        rows.append("".join(enc(c, -32, 32, 3) for c in p))
        rows.append(enc_quat((C @ mats["HumanoidRootPart"] @ C).to_quaternion()))
        for part, parent, _, _ in JOINTS:
            rel = mats[parent].transposed() @ mats[part]
            rows.append(enc_quat((C @ rel @ C).to_quaternion()))
        cm = cam.matrix_world
        rows.append("".join(enc(c, -32, 32, 3) for c in C @ cm.translation))
        rows.append(enc_quat((C @ cm.to_3x3().normalized()).to_quaternion()))
        fov = math.degrees(2 * math.atan(cam.data.sensor_height / 2 / cam.data.lens))
        rows.append(enc(fov, 0, 120, 2))
        frames.append("".join(rows))
    per = len(frames[0])
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("-- GENERATED by assets/menu/play_intro.py --bake: the menu's PLAY animation, keyed in Blender\n")
        fh.write("-- (assets/menu/play_intro.blend). Played by client/MenuPuppet; do not edit by hand.\n")
        fh.write("return {\n")
        fh.write(f"\tfps = {FPS},\n\tframes = {END + 1},\n\tper = {per},\n")
        fh.write(f"\tsitRoot = Vector3.new({SIT_ROOT[0]}, {SIT_ROOT[1]:.4f}, {SIT_ROOT[2]}),\n")
        fh.write(f"\tstandRoot = Vector3.new({STAND_ROOT[0]}, {STAND_ROOT[1]:.4f}, {STAND_ROOT[2]}),\n")
        fh.write(f"\tphonesOff = {{ {PHONES_OFF[0] / FPS:.4f}, {PHONES_OFF[1] / FPS:.4f} }}, -- seconds: the headphones fade\n")
        fh.write(f"\tchairFade = {{ {CHAIR_FADE[0] / FPS:.4f}, {CHAIR_FADE[1] / FPS:.4f} }}, -- seconds: the chair fades\n")
        fh.write("\tdata = \"")
        fh.write("".join(frames))
        fh.write("\",\n}\n")
    print("baked", path, END + 1, "frames,", per, "chars each")


frames_dir, bake_path, save_path = opt("--frames"), opt("--bake"), opt("--save")
if bake_path:
    bake(bake_path)
if save_path:
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(save_path))
if frames_dir:
    os.makedirs(frames_dir, exist_ok=True)
    scene.render.image_settings.file_format = "PNG"
    for f in range(scene.frame_start, scene.frame_end + 1):
        scene.frame_set(f)
        scene.render.filepath = os.path.join(frames_dir, f"{f:04d}.png")
        bpy.ops.render.render(write_still=True)
