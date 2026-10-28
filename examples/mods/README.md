# Example content packs

`ember/` is a complete pack for testing and for the docs (`docs/DATA_DRIVEN_CONTENT.md`, "Mod packs").

- `pack.json`: the manifest (`lr.pack/1`). It overrides one built-in prop, so it lists `props/officePrinter`.
- `props/office.json`: every office printer uses `assets/office_printer_ember.glb`, the shipped printer model with its
  material tinted ember orange.
- `hunters/ember.json`: `ember_aki`, a new hunter. New ids start with the pack id. She wears Aki's shipped body and
  portrait, joins the seeded draw in the intermediate tier, and runs the default chase behaviour on her own tuning.

To try it, copy `ember/` to `user://mods/ember/` (on macOS
`~/Library/Application Support/Godot/app_userdata/<project>/mods/ember/`), enable it under Settings -> MODS, and start
a private room. Packs hold data and png/ogg/glb assets only; this folder has a `.gdignore` so Godot never imports it
as game content.
