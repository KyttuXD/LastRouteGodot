# Blocky (Minecraft-style) props

`measure.gd` records the footprint of every catalogued prop model;
`build_blocky_props.py` (Blender, headless) rebuilds the most visible ones as box
models from one 64x64 pixel atlas at the same size and pivot; the generated
`src/config/blocky_prop_models.gd` maps catalogue types to the new GLBs and
`PropModelCatalog.USE_BLOCKY_PROPS` switches them on (the original models remain the
fallback and are untouched).

```sh
godot --headless --path . res://tools/props/measure.tscn -- OUTDIR
/Applications/Blender.app/Contents/MacOS/Blender --background \
  --python tools/props/build_blocky_props.py -- OUTDIR/prop_bounds.json art/props-3d/props/blocky
godot --headless --path . --import
```
Then regenerate `blocky_prop_models.gd` from `art/props-3d/props/blocky/manifest.json`.
