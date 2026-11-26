# FBX source exports of the animated bosses: one file per boss with its bone rig (Motor6D pivots), its
# body pieces parented rigidly to the bones, and every clip as an FBX take.
#   blender -b assets/myth/boss_anims.blend -P assets/myth/export_fbx.py
# writes assets/myth/fbx/<Kind>.fbx. These are for other tools (and an Import 3D of a rigged model if it
# is ever wanted); the game itself plays the baked clips in shared/MythClips on the part rig.
import os

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "fbx")
os.makedirs(OUT, exist_ok=True)

for kind in ("Cyclops", "Minotaur", "Talos"):
    arm = bpy.data.objects.get(f"{kind}_Rig")
    if not arm:
        print("no rig for", kind)
        continue
    actions = [a for a in bpy.data.actions if a.name.startswith(kind + "_")]
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for child in arm.children_recursive:
        if child.type == "MESH":
            child.select_set(True)
    bpy.context.view_layer.objects.active = arm
    # one NLA track per clip so the exporter writes each as its own take
    ad = arm.animation_data_create()
    for track in list(ad.nla_tracks):
        ad.nla_tracks.remove(track)
    for act in actions:
        track = ad.nla_tracks.new()
        track.name = act.name.split("_", 1)[1]
        strip = track.strips.new(track.name, int(act.frame_range[0]), act)
        if act.slots:
            strip.action_slot = act.slots[0]
    ad.action = None
    path = os.path.join(OUT, kind + ".fbx")
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"ARMATURE", "MESH"},
                             add_leaf_bones=False, bake_anim=True, bake_anim_use_all_actions=False,
                             bake_anim_use_nla_strips=True, bake_anim_simplify_factor=0.0, bake_anim_force_startend_keying=True,
                             apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y")
    print("FBX", path, os.path.getsize(path), "bytes,", len(actions), "clips")
