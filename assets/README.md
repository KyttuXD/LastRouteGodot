# Assets

Copy canonical assets from `KyttuXD/LastRoute/last-route/assets/` into categorized subfolders here. Preserve source filenames initially so references remain traceable during migration.

Suggested groups: `characters/`, `environment/`, `props/`, `ui/`, `audio/`, and `fonts/`.

**Before copying anything, read the "Open decision: rendering architecture" section in `../MIGRATION.md`.** The original's environment art is built for its custom fake-3D "2.5D diorama" canvas renderer, not flat top-down tiles, and character sheets are 96×96px/frame — both mismatched with a naive top-down import. The project is currently leaning toward real 3D props (see `../art/props-3d/`) rather than reproducing the original's 2D perspective trick; confirm that direction before bulk-copying 2D art here.

