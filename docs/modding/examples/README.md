# Example packs

Ready-made packs in `examples/mods/`. Each one passes `tools/modpack/modpack.sh validate`, and the `data_packs` and
`data_rooms` suites load, check, unload and hot-swap every one of them. All art and sound is original and generated
by `tools/modpack/example_assets.py` (no copied assets).

| pack | what it shows | kinds used |
|---|---|---|
| [neon_arcade](neon_arcade.md) | dark neon textures and an ARCADE room in the mall | floors, walls, ceilings, rooms, regions |
| [rainy_night](rainy_night.md) | rain and thunder beds, creaking doors, wet steps | ambience, sounds |
| [frostbite_aki](frostbite_aki.md) | an icy Aki variant as a new hunter | hunters, deaths, emotes |
| [library_rooms](library_rooms.md) | a reading room, an archive and a new ladder prop | rooms, props, regions |
| [gentle_grabs](gentle_grabs.md) | softer grab pools for Kathy and Glyra | grabs |
| [death_lines_plus](death_lines_plus.md) | extra death lines for all 38 hunters | deaths |

Older examples: `ember` ([walkthrough](../ember-walkthrough.md)) and `record_shop`.
`neon_arcade` and `library_rooms` both override `regions/mall`, so a room can use only one of them at a time.

The packs that must be **refused** are in [_tests](_tests.md).

## Rebuilding the assets and sheets

```
python3 tools/modpack/example_assets.py                      # textures, audio, ladder and tinted Aki
godot --headless --path . res://tools/modpack/example_layout.tscn -- <pack> <out.json> <room type>...
godot --path . --position 10000,10000 res://tools/modpack/example_render.tscn -- <work dir>   # needs a window/GPU
python3 tools/modpack/example_sheets.py <work dir>           # writes docs/modding/examples/sheets/*.png
```

The room sheets are top-down plans of rooms the real generator makes (seed `SHEET-A`); the model render is a windowed
capture. There is no in-game capture of a modded room yet.
