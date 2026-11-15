# Splits a Studio-saved .rbxmx holding many KeyframeSequences (in a Folder) into one minimal .rbxmx
# per sequence, for uploading as Animation assets. Only the animation data is kept (Name, Loop,
# Priority, Time, CFrame, Weight, easing): copying Studio's items whole drags along references to
# the file's SharedStrings table, and the upload then fails with "Failed to load asset content".
# Usage: py split.py animations.rbxmx upload
import os
import sys
import xml.etree.ElementTree as ET

CF = ["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"]


def prop(item, kind, name):
    el = item.find(f"Properties/{kind}[@name='{name}']")
    return el


def text(item, kind, name, default=""):
    el = prop(item, kind, name)
    return el.text if el is not None and el.text is not None else default


def emit(item, ref):
    ref[0] += 1
    me = ref[0]  # read now: the children below advance the counter
    cls = item.get("class")
    p = [f'<string name="Name">{text(item, "string", "Name")}</string>']
    if cls == "KeyframeSequence":
        p.append(f'<bool name="Loop">{text(item, "bool", "Loop", "false")}</bool>')
        p.append(f'<token name="Priority">{text(item, "token", "Priority", "0")}</token>')
    elif cls == "Keyframe":
        p.append(f'<float name="Time">{text(item, "float", "Time", "0")}</float>')
    elif cls == "Pose":
        cf = prop(item, "CoordinateFrame", "CFrame")
        p.append('<CoordinateFrame name="CFrame">' + "".join(f"<{k}>{cf.find(k).text}</{k}>" for k in CF) + "</CoordinateFrame>")
        p.append(f'<token name="EasingDirection">{text(item, "token", "EasingDirection", "0")}</token>')
        p.append(f'<token name="EasingStyle">{text(item, "token", "EasingStyle", "0")}</token>')
        p.append(f'<float name="Weight">{text(item, "float", "Weight", "1")}</float>')
    kids = "".join(emit(c, ref) for c in item.findall("Item") if c.get("class") in ("Keyframe", "Pose"))
    return f'<Item class="{cls}" referent="RBX{me}"><Properties>{"".join(p)}</Properties>{kids}</Item>'


src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
names = []
for item in ET.parse(src).getroot().iter("Item"):
    if item.get("class") != "KeyframeSequence":
        continue
    name = text(item, "string", "Name")
    xml = '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" version="4">' + emit(item, [0]) + "</roblox>"
    with open(os.path.join(out, name + ".rbxmx"), "w", encoding="utf-8") as f:
        f.write(xml)
    names.append(name)
print(len(names), "written")
