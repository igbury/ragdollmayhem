# Writes upload/Temple_Visor.rbxmx: the Laser Visor's firing pose (client/WeaponAnims CLIPS.Temple_Visor),
# in the same minimal form as split.py's output, for uploading as an Animation asset.
import math

def angles(x, y=0, z=0):  # CFrame.Angles(rx, ry, rz) = Rx * Ry * Rz
    x, y, z = map(math.radians, (x, y, z))
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    mul = lambda a, b: [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return mul(mul(rx, ry), rz)

POSE = {"RightUpperArm": angles(60, 40, 20), "RightLowerArm": angles(125), "RightHand": angles(-10)}
TREE = ("HumanoidRootPart", [("LowerTorso", [("UpperTorso", [
    ("LeftUpperArm", [("LeftLowerArm", [("LeftHand", [])])]),
    ("RightUpperArm", [("RightLowerArm", [("RightHand", [])])])])])])
ref = [0]

def pose(node):
    name, kids = node
    ref[0] += 1
    m = POSE.get(name, [[1, 0, 0], [0, 1, 0], [0, 0, 1]])
    cf = "<X>0</X><Y>0</Y><Z>0</Z>" + "".join(f"<R{i}{j}>{m[i][j]:.6f}</R{i}{j}>" for i in range(3) for j in range(3))
    return (f'<Item class="Pose" referent="RBX{ref[0]}"><Properties><string name="Name">{name}</string>'
            f'<CoordinateFrame name="CFrame">{cf}</CoordinateFrame><token name="EasingDirection">0</token>'
            f'<token name="EasingStyle">3</token><float name="Weight">{1 if name in POSE else 0}</float></Properties>'
            + "".join(pose(k) for k in kids) + "</Item>")

def key(t):
    ref[0] += 1
    return (f'<Item class="Keyframe" referent="RBX{ref[0]}"><Properties><string name="Name">Keyframe</string>'
            f'<float name="Time">{t}</float></Properties>{pose(TREE)}</Item>')

ref[0] = 1
body = key(0) + key(0.5)
xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" version="4"><Item class="KeyframeSequence" referent="RBX1">'
       '<Properties><string name="Name">Temple_Visor</string><bool name="Loop">true</bool><token name="Priority">5</token>'
       f'</Properties>{body}</Item></roblox>')
open("upload/Temple_Visor.rbxmx", "w", encoding="utf-8").write(xml)
print(len(xml))
