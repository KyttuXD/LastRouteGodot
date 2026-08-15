# Office Mode model pipeline

Builds the Office Mode facility — the office itself, the nine camera rooms, the
corridors between them and the desk console — as Blockbench `.bbmodel` files,
then exports them straight to `.glb` for `art/props-3d/office/`.

These scripts used to live outside the repository, which is how one of them was
lost. They are here now because the models cannot be regenerated without them,
and because `src/config/office_layout.gd` is **generated** — a generated file
whose generator is missing is worse than a hand-written one.

## Requirements

Python 3 with `pillow` and `numpy`. Nothing else; the exporter writes glTF by
hand rather than driving Blockbench's UI.

## Building

Order matters: the merged map builds the office room into itself, and the split
is what the Godot scene actually loads.

```bash
python3 tools/office/build_merged_map.py /tmp/office_map.bbmodel --gd src/config/office_layout.gd
python3 tools/office/split_office_map.py /tmp/office_map.bbmodel art/props-3d/office scenes/office_map.tscn
python3 tools/office/build_office_room.py /tmp/office_room.bbmodel
python3 tools/office/bbmodel_to_glb.py /tmp/office_room.bbmodel art/props-3d/office
```

`--gd` regenerates the floor plan the desk console draws on its screen. Pass it
whenever a room moves, or the console keeps showing a building the facility no
longer is.

## Checking the result

`render_room.py` rasterises a `.bbmodel` to a PNG without a GPU or Blockbench,
which is how geometry gets checked here:

```bash
python3 tools/office/render_room.py /tmp/office_room.bbmodel /tmp/seat.png --cam 0,1.40,2.28 --look 0.10,1.02,1.20
```

It honours group rotation, because that is the only rotation the exporter
carries into glTF — cube-level rotation is dropped, so a preview that ignored
group rotation would show something the engine never renders.

The engine-side checks are separate:

```bash
godot4 --headless --script scripts/validate_office_rooms.gd
godot4 --headless --script scripts/validate_camera_console.gd
python3 scripts/check_map_connectivity.py /tmp/office_map.bbmodel
```

## What lives where

| file | role |
| --- | --- |
| `office_layout.py` | Room positions and camera assignments. The one source of truth, and the generator for `src/config/office_layout.gd`. |
| `room_paint.py` | Procedural pixel-art materials and atlas packing. |
| `room_kit.py` | `Room` (boxes, groups, UVs), plus `shell`, `corridor`, `recessed_panel`, `louvered_grille`. |
| `build_office_room.py` | The office: desk, doors, vent, CRT, and the PREV/NEXT camera console. |
| `build_camera_rooms.py` | The nine rooms the cameras watch. |
| `build_merged_map.py` | Places every room, cuts the openings, builds the corridors and junction patches. |
| `split_office_map.py` | Splits the map into shell and props so dressing can be edited by hand. |
| `bbmodel_to_glb.py` | `.bbmodel` → `.glb`, with collision and animation. |
| `render_room.py` | Software preview renderer. |

## Two things that will bite

**`autouv` must stay 0.** With it on, Blockbench regenerates UVs on load and
silently discards every mapping the painter computed.

**A display's faces all take the display material.** Godot's
`material_override` replaces a mesh's material but keeps its UVs, so a live
viewport on a screen samples whatever patch of the shared atlas that face's UVs
point into. Giving the whole slab one material makes the mesh's UV bounds equal
the display rect, which is what lets the engine remap a viewport onto it.
