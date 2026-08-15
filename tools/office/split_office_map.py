#!/usr/bin/env python3
"""
Splits the merged office map into a SHELL and a PROPS model, plus a Godot
scene that instances both.

One monolithic .glb is fine to render and impossible to edit: adding a crate
or nudging a shelf means regenerating the whole map. Splitting the built
fabric from the things standing on it means props can be adjusted, added or
replaced in the Godot editor without touching the walls -- and the shell can
be rebuilt without losing hand-placed dressing.

The split is by group name. Anything structural -- floors, ceilings, walls,
corridors, junction patches, doorframes and the doors themselves -- is shell.
Everything else is a prop, including the camera mounts and nav markers, which
belong with the dressing rather than the building.

    python3 split_office_map.py <map.bbmodel> <outdir> <scene_out.tscn>
"""
import sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bbmodel_to_glb import convert

# Structural fabric. Matched against the group name with its room prefix
# stripped, so "Storage_WallNorth0" tests as "WallNorth0".
SHELL = ("Floor", "Ceiling", "Wall", "BackWall", "FrontWall", "LeftWall",
         "RightWall", "Link", "Passage", "WestPassage", "EastPassage",
         "Junct", "DoorFrame", "Jamb", "Lintel", "OfficeDuct")
# Doors are shell too -- they are part of the opening -- but they are DRIVEN,
# so they must stay individually named and cannot be dressing.
SHELL_EXACT = ("LeftDoor", "RightDoor", "BayDoor", "Door", "DoorFar", "DoorNear")


def is_shell(name):
    bare = name.split("_", 1)[1] if "_" in name else name
    return bare.startswith(SHELL) or bare in SHELL_EXACT


def main():
    src, outdir, scene_out = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(outdir, exist_ok=True)

    shell = convert(src, os.path.join(outdir, "office_map_shell.glb"),
                    keep=is_shell)
    props = convert(src, os.path.join(outdir, "office_map_props.glb"),
                    keep=lambda n: not is_shell(n))
    print(f"  shell  {shell['meshes']:3d} meshes {shell['tris']:5d} tris "
          f"{shell['bytes']//1024:4d} KB")
    print(f"  props  {props['meshes']:3d} meshes {props['tris']:5d} tris "
          f"{props['bytes']//1024:4d} KB")

    res = "res://" + os.path.relpath(outdir, os.path.dirname(os.path.dirname(scene_out)))
    res = res.replace(os.sep, "/")
    os.makedirs(os.path.dirname(scene_out) or ".", exist_ok=True)
    with open(scene_out, "w") as fh:
        fh.write(f'''[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="{res}/office_map_shell.glb" id="1_shell"]
[ext_resource type="PackedScene" path="{res}/office_map_props.glb" id="2_props"]

; The office facility, split so it can be edited.
;
; Shell is the built fabric -- floors, ceilings, walls, corridors, junction
; patches, doorframes and the driven doors. Props is everything standing in
; it, including the CameraMount/CameraTarget pairs the feeds aim from and the
; Nav_cam markers hunters walk between.
;
; To adjust dressing by hand: right-click Props > "Make Local", then move,
; delete or add whatever you like. The shell can still be regenerated from
; Blockbench without disturbing it. Both halves share one texture atlas, so
; they line up exactly.
[node name="OfficeMap" type="Node3D"]

[node name="Shell" parent="." instance=ExtResource("1_shell")]

[node name="Props" parent="." instance=ExtResource("2_props")]
''')
    print(f"  scene  {scene_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
