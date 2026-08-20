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

Use `mansion`, `maze`, `beach`, `nether`, or `prison` to rebuild a complete pack. Each
build writes all three retained asset layers:

- editable `.blend` source under the pack's `source/` directory;
- the pixel atlas under `source/textures/`;
- the runtime `.glb` and a rendered preview.

The mansion builder also retains the coordinated bedroom theme definitions:

- normal: burgundy, navy, violet, olive, ivory, and charcoal;
- Gothic: crimson, violet, midnight blue, forest green, and ivory.

It also owns three complete hunter-scale kitchen families—normal, luxury, and
Gothic—covering counters, sinks, stoves, refrigerators, wall cabinets, and
islands, plus the normal-house and mansion furniture expansion. Bathroom
sources include public men's/women's utilities, public showers, and a warmer
residential tub/shower collection. The grand stair hall retains visible
pixel-art treads and rails while Godot supplies a smooth no-jump ramp beneath
them for player and hunter traversal.

Normal bedroom model names use the historical unsuffixed path for burgundy
and a theme suffix for the other finishes. Gothic bedroom pieces always use a
theme suffix. Keeping those rules in the builder is important because the
Godot catalog relies on the same ordering to choose one coordinated colorway
for every prop in a room.

The maze builder also owns four complete retro-computer silhouettes: a compact
all-in-one, tower workstation with speakers, horizontal desktop workstation,
and wedge-terminal computer. Each is authored in ivory, charcoal, teal, and
burgundy. Their screens use original Last Route signal glyphs rather than
third-party operating-system artwork. Rebuild one family or the complete set
with, for example:

```bash
flatpak run --filesystem="$PWD" org.blender.Blender --background \
  --python "$PWD/tools/props/rebuild_hytale_props.py" -- \
  retro_computer_compact_ivory retro_computer_tower_charcoal \
  retro_computer_desktop_teal retro_computer_terminal_burgundy
```

The wooden chair, cushioned chair, table, and dresser/sideboard families are
available in oak, walnut, mahogany, and ash. `PropModelCatalog` keeps every
family in matching order and hashes the containing room id, so furniture in a
room receives one stable wood finish and its computers receive one stable
shell color in both finite and streamed routes. Adding a future variant means
adding it to every coordinated silhouette at the same array index and updating
the matching `VARIANT_THEMES` labels.

Office desks, task chairs, CRT security consoles, partitions, printers, water
coolers, photocopiers, shredders, file-box stacks, and corner workstations use
the same rule. Each has neutral, charcoal, and teal authored exports, and every
piece in one generated office resolves to the same finish from the room id.

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

The interactable pack also owns the gameplay-facing locked relay crate and
barrel, one-metre doorway and full 3×3 hallway barricades, flashlight, taser,
lockpick set, crowbar, rescue axe, service ladder and wall-light switch. These
are real pixel-painted GLBs used across map pickups, first-person equipment
and architecture; code supplies collision, interaction state and animation
transforms. Rebuilding the five inventory items also renders transparent
96×96 HUD icons into `assets/ui/inventory/` from those exact sources.

The prison pack supplies a three-metre cell gate, bunk, freestanding dungeon
cage, and restraint chair for lower-level streamed prison regions. These are
offline-authored, pixel-painted Blender/GLB assets built by this repository's
normal source pipeline; no remote 3D-generation service is used. Prison rooms
are marked streamed-only so their furniture cannot leak into Standard routes.

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
