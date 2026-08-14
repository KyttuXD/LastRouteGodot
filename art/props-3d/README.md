# 3D prop scaffold

Placeholder grey-box meshes for a possible 3D/top-down rendering track for
LastRoute — see the "Open decision: rendering architecture" section in
`../../MIGRATION.md` for why this exists alongside the current 2D port. This
folder is decoupled from that port: nothing under `src/` references it yet.
It exists so real modeled assets have a defined scale and pivot to import
into, instead of guessing and re-exporting later.

## Scale convention

**1 grid tile = 1 meter = 1 Godot unit.** This lines up directly with
`src/game/facility_generator.gd`'s integer cell coordinates: a generator
cell `(x, y)` maps to the 3D ground position `(x, 0, y)` (Godot is Y-up, so
the facility's 2D grid becomes the XZ ground plane, not XY). The 2D port's
own `GameConfig.TILE_SIZE` (16px) is the equivalent unit on that side — the
two are parallel, unrelated pixel/meter scales for the same grid, not a
conversion factor between them.

## Pivot convention

**Every prop's origin sits at its base center — flush on the floor at
`y = 0`.** Place a prop at a cell's world position and it stands on the
ground with no manual offset. This matches Blender's usual "object origin at
the base" habit for architectural/prop assets, so exports should need no
repositioning on import — just point the import at the same origin.

Concretely, for a prop whose visual height is `h`: its mesh/collision should
be centered `h / 2` above the object's own origin, so the object origin
itself stays at floor level. All the placeholder scenes here already do
this (look at the transform on their child `MeshInstance3D`/
`CollisionShape3D` nodes for the pattern).

## Import format

Export to **glTF 2.0 (`.glb`)** — Godot 4 imports it natively with no
plugin, including materials, and it's the format Godot's own docs recommend
for 3D pipelines. Forward/up axis: Godot's default glTF import expects
+Y up, -Z forward, which is Blender's own default glTF export orientation —
no axis-fixup step should be needed if you export straight from Blender with
default settings.

## What's here

| File | Represents | Footprint | Height |
| --- | --- | --- | --- |
| `wall_block.tscn` | one 1m corridor/room wall segment | 1m × 0.2m | 2.4m |
| `floor_tile.tscn` | one 1m² floor cell | 1m × 1m | 0.1m (thin slab, top flush at y=0) |
| `door_frame.tscn` | a doorway placeholder | 0.9m × 0.15m | 2.0m |
| `generic_prop.tscn` | stand-in for any furniture/prop | 0.5m cube | 0.5m |
| `character_scale_reference.tscn` | human-scale capsule, for calibrating prop proportions against — not a real character | 0.6m diameter | 1.7m |

Each is a `StaticBody3D` (the character reference is a plain `Node3D`, no
collision) with a flat-colored placeholder material — distinct colors per
type so it's obvious at a glance which pieces are still placeholders.

`reference_layout.tscn` lays all of them out together on a small ground
plane with a light and camera already framed, so opening it in the Godot
editor immediately shows everything at correct relative scale — the fastest
way to sanity-check a new export against the existing pieces before wiring
it in anywhere.

## Replacing a placeholder

1. Export the real asset as `.glb` from Blender, origin at base center, real-world scale (1 unit = 1m).
2. Drop it in this folder (or a subfolder once there are enough to organize).
3. Either swap the placeholder's `MeshInstance3D.mesh`/material for the import directly, or replace the whole `.tscn`'s contents — keep the same root node name and collision shape sizing if other scenes reference this one by path.
4. Open `reference_layout.tscn` and check it still reads correctly at scale next to everything else.
