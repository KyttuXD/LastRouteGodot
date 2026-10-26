# Reference look (branch `ref-look`)

Restyle of the infinite route to match the Last Route 3D reference images
(`LastRoute-3D-refs/3.webp` .. `20.webp`): a dark, wet, liminal facility in
chunky pixel art, lit by amber lamps with teal terminals as the only cool accent.
Everything is procedural; there is no new imported art.

## Where it lives (`src/look/`)

| File | Job |
| --- | --- |
| `ref_look.gd` | Palette, `Environment` (plum ambient, fog, filmic, glow), `install()` that adds the post layer, the region/room surface tables (`REGION_STYLE`, `ROOM_STYLE`), `grade_prop()` |
| `ref_pixel.gdshader` | Full-screen pass on a CanvasLayer *below* the HUD: block-resolution sampling (270 rows), 4x4 ordered dither into a 20-level ladder, plum/brass grade, desaturation, vignette |
| `ref_textures.gd` | Painted 32 px/m floors, walls (32x128, a whole storey), ceilings. Built into two `Texture2DArray`s |
| `ref_surface.gdshader` / `ref_surface_mesh.gd` | One merged mesh per chunk (floor+ceiling surface, wall surface) using the arrays; vertex colour carries roughness/metal/emission |
| `ref_decor.gd` | Per-chunk MultiMesh dressing: sconces, lanterns, chandeliers, caged ceiling lamps, teal terminals, frames, windows, pipes, cable swags, floor cables, planters, pedestal lanterns, additive floor pools, halos and glossy streak decals |
| `ref_streak.gdshader` | Reflection streak that always lies on the floor from a lamp's foot towards the camera (the "wet floor" read, since the Compatibility renderer has no SSR) |
| `lamp_field.gd` | Lends 12 real `OmniLight3D`s to the lamps nearest the camera (fades a light out before re-homing it) |

Hooks: `RefLook.install()` is called from `infinite_route_test.gd` and `main_3d.gd`
`_ready()`; `StreamedFacilityView3D` builds the chunk surface and decor (phases 2
and 31 of the incremental chunk build) and keeps its GridMap for collision only.
Decor is derived from chunk data and a seeded hash, so co-op peers build the same
lamps without sharing state.

## Region mapping

maze = industrial / offices / arcade, mansion = drawing room / hall / dining, hotel =
wallpapered corridors with runners, apartment = two-tone flats, beach = ivy garden
with a glass roof, gothic = vaulted brick/stone, carnival = star-carpet prize rooms,
prison = service bays with hazard striping, inferno = foundry plates with embers.

## Capture rig

```sh
godot --path . res://tools/look/capture.tscn -- OUTDIR TAG [SEED]
```

Environment: `CAP_ONLY=beach_cove,corridor_` (substring list), `CAP_LEVELS=-1,2`,
`CAP_YAWS=0,90`, `CAP_HUNTERS=aki,xivvy`, `CAP_HUD=1`, `CAP_FPS=1` (prints fps and
draw calls), `CAP_LIST=1`. Run `godot --headless --path . --import` first after
adding a `class_name` script.

## Known gaps

No fountain, hedge arches or two-flight grand staircase (the generator's
`grandFoyerStaircase` prop still renders, just in the new lighting); no hanging
cable bundles overhead beyond single swags; first-person held item is unchanged.
