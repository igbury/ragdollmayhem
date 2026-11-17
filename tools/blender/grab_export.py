# anims.json (grab_rig.py) -> src/client/GrabAnimData.luau
# In Blender's Python (live via MCP, or blender -b --python):
#   D = r"<repo>\tools\blender"
#   g = {"CFG": (D + r"\grab_keys.py", D + r"\grab_out", False), "__name__": "grab"}
#   exec(open(D + r"\grab_rig.py").read(), g)      # builds scene "GrabAnims", poses every key
#   exec(open(D + r"\grab_export.py").read(), {"D": D})
import json
import os
# this folder (exec()d inside Blender, so no __file__): pass D in, or it falls back to the copy here
D = globals().get("D") or r"C:\Users\agor2\Documents\ragdollmayhem\tools\blender"
REPO = os.path.dirname(os.path.dirname(D))
data = json.load(open(D + r"\grab_out\anims.json"))
ORDER = ["LowerTorso", "UpperTorso", "Head", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand",
         "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]
def num(x):
    s = ("%.4f" % x).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s
lines = ["-- GENERATED from Blender (tools/blender: grab_rig.py + grab_keys.py, then grab_export.py): the joint CFrames of the F grab",
         "-- animations, key by key. { x, y, z, r00, r01, ..., r22 } per part, as CFrame.new takes them.",
         "-- Edit the key poses in Blender and re-export rather than by hand.", "return {"]
for name in ("hold", "scrape", "punt"):
    a = data[name]
    lines.append(f"\t{name} = {{")
    lines.append(f"\t\tloop = {'true' if a['loop'] else 'false'},")
    if a["parts"]:
        lines.append("\t\tparts = { " + ", ".join(f'"{p}"' for p in a["parts"]) + " },")
    lines.append("\t\tframes = {")
    for fr in a["frames"]:
        lines.append(f"\t\t\t{{ t = {num(fr['t'])}, pose = {{")
        for part in ORDER:
            if a["parts"] and part not in a["parts"]:
                continue
            q = fr["pose"][part]
            lines.append(f"\t\t\t\t{part} = {{ " + ", ".join(num(v) for v in list(q["p"]) + q["r"]) + " },")
        lines.append("\t\t\t} },")
    lines.append("\t\t},")
    lines.append("\t},")
lines.append("}")
open(os.path.join(REPO, "src", "client", "GrabAnimData.luau"), "w", newline="\n").write("\n".join(lines) + "\n")
print("exported", len(lines))
