# Blocky (Minecraft-style) props

`measure.gd` records the footprint of every catalogued prop model;
`build_blocky_props.py` (Blender, headless) rebuilds the most visible ones as box
models from one 64x64 pixel atlas at the same size and pivot; the generated
`game/config/blocky_prop_models.gd` maps catalogue types to the new GLBs and
`PropModelCatalog.USE_BLOCKY_PROPS` switches them on (the original models remain the
fallback and are untouched).

`PropModelCatalog.PREFER_ORIGINAL_PROPS` then draws the original model again for the types that fit their (blocky-derived) collider and stay under the
triangle cap (docs/ORIGINAL_PROPS.md); colliders and footprints still come from the blocky models, so `emit_collider_sizes` and `measure` are unchanged.
`original_fit_report.tscn` prints the per-type numbers behind the deny list.

```sh
godot --headless --path . res://tools/props/measure.tscn -- OUTDIR
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --python tools/props/build_blocky_props.py -- OUTDIR/prop_bounds.json assets/props/blocky
godot --headless --path . --import
```
Then regenerate `blocky_prop_models.gd` from `assets/props/blocky/manifest.json`.

## Rework 2 (DONE13) workflow

```sh
S=/path/to/scratch
godot --headless --path . res://tools/props/measure.tscn -- $S                      # footprints of the original models
blender --background --python tools/props/build_blocky_props.py -- $S/prop_bounds.json assets/props/blocky
python3 tools/props/clean_orphans.py                                               # drop GLBs the build no longer lists
python3 tools/props/emit_models.py                                                 # regenerate game/config/blocky_prop_models.gd
godot --headless --path . --import
blender --background --python tools/props/render_sheet.py -- OUT.png assets/props/blocky name_0,name_1 three 6   # contact sheet
```
Designs in metres live in `blocky_props_rework2.py` and `blocky_props_rework3.py` (`TARGET_SIZE`, rotated parts via `Part.add(..., rot=, pivot=)`).

Colliders: after any model change regenerate `game/config/prop_collider_sizes.gd` (`godot --headless --path . res://tools/props/emit_collider_sizes.tscn`). Imports and
validators for testing run locally with Godot headless, then the generated `.import` files and the collider table are
pulled back and committed.
