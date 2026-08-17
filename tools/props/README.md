# Prop build tools

These scripts are the retained local source pipeline for the Minecraft/Hytale-
styled Last Route props. Paths are resolved from this folder, so the repository
can be moved without editing the scripts.

## Build models

Run Blender in background mode and pass one or more model names after `--`:

```bash
flatpak run --filesystem="$PWD" org.blender.Blender --background \
  --python "$PWD/tools/props/rebuild_hytale_props.py" -- bedroom_nightstand bedroom_wardrobe
```

Use `mansion`, `maze`, `beach`, or `nether` to rebuild a complete pack. Each
build writes all three retained asset layers:

- editable `.blend` source under the pack's `source/` directory;
- the pixel atlas under `source/textures/`;
- the runtime `.glb` and a rendered preview.

The mansion builder also retains the coordinated bedroom theme definitions:

- normal: burgundy, navy, violet, olive, ivory, and charcoal;
- Gothic: crimson, violet, midnight blue, forest green, and ivory.

It also owns three complete hunter-scale kitchen families—normal, luxury, and
Gothic—covering counters, sinks, stoves, refrigerators, wall cabinets, and
islands, plus the normal-house and mansion furniture expansion.

Normal bedroom model names use the historical unsuffixed path for burgundy
and a theme suffix for the other finishes. Gothic bedroom pieces always use a
theme suffix. Keeping those rules in the builder is important because the
Godot catalog relies on the same ordering to choose one coordinated colorway
for every prop in a room.

## Hunter-scale contract

Props use metres and are authored against the imported hunter roster: the
shared body is about 1.70 m tall, while hair, halos, wings and other silhouette
pieces bring some hunters up to 2.20 m. Human-use furniture therefore keeps
seats near 0.5-0.6 m, work surfaces near 0.75-1.05 m, and full-height storage
near 1.8-2.5 m. The Frozen Tideline umbrella is about one and a half shared
hunter bodies tall (2.60 m), and its palm tree is over two bodies tall
(about 3.69 m). The umbrella canopy is 2.30 m across so two hunters can stand
side by side beneath it.

Bed sleeping surfaces are at least 2.42 m long; their complete frames and
collision footprints retain extra head/foot clearance so no hunter silhouette
hangs over either end.

`validate_prop_sources.py` enforces the critical human-scale ranges along with
floor pivots, source/export parity, embedded pixel atlases, and mesh budgets.

The `.blend`, atlas, runtime `.glb`, and Godot `.import` metadata are retained
source/runtime assets. Preview renders, Meshy task output, and Blender's
automatic `.blend1` previous-save copies are reproducible local review files
and are ignored by Git. This keeps a complete rebuild path without adding
dozens of megabytes of gallery/cache output to every clone.

No retained asset currently approaches GitHub's per-file limit. If a future
single source or runtime model reaches 50 MiB, configure Git LFS on development
machines and the Pterodactyl checkout before committing it; do not add the
large binary directly to ordinary Git history.

## Validate models

```bash
flatpak run --filesystem="$PWD" org.blender.Blender --background \
  --python "$PWD/tools/props/validate_prop_sources.py"
```

The validator checks floor pivots, hunter-relative scale, stray render
objects, embedded textures, nearest-neighbour filtering, GLB headers, and
source/export mesh parity.

## Rebuild preview galleries

The gallery scripts use Pillow:

```bash
python3 tools/props/make_mansion_prop_sheets.py
python3 tools/props/make_maze_prop_sheets.py
python3 tools/props/make_beach_nether_prop_sheets.py
```

They only compose existing preview PNGs; they do not modify model sources.

`make_original_mansion_reference.py` and
`make_original_beach_nether_reference.py` retain the comparison-sheet process
used against the sibling `LastRoute-OG` checkout. They write reference sheets
under `art/props-3d/reference/` and never alter the original project.
