# Rules and limits

- **Data and assets only.** Allowed files: `pack.json`, JSON in the content folders (`props/`, `hunters/`, `regions/`, `skins/`, ...), and `.glb`, `.png`,
  `.ogg` under `assets/`. Any script, scene, resource, library or other file refuses the whole pack.
- **Models are stripped.** Models load at runtime; every script, light, camera, physics body and extension node is
  removed. glTF extensions allowed: `KHR_materials_emissive_strength`, `KHR_materials_unlit`,
  `KHR_texture_transform`, `KHR_mesh_quantization`.
- **Paths stay inside the pack**: no absolute paths, `..`, backslashes, `:`, hidden files, links, or two names that
  differ only in letter case.
- **Sizes**: 16 MB per file, 128 MB per pack, 512 files.
- **All or nothing**: one problem in any pack of a room refuses all of the room's packs, with the file named. The
  game is never left half-modded.
- **No restart**: packs load when a room starts and unload when you leave it.
- **Private rooms only.** Public routes are always the unmodded game.
- **Ids**: new content starts with `<pack id>_`; built-in content is changed only through `overrides`; one pack per
  overridden id.
- **Versions are immutable** once published.
