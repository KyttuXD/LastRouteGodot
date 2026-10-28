# Custom player skins

A skin is a standard Minecraft-layout **64×64 PNG** on the player mannequin (`assets/hunters_blocky/player_mannequin`, classic
proportions). Settings → **SKIN** picks a file, previews it on a rotating mannequin, applies it, resets to the default, or saves the
template to paint over.

- **Template:** [player_skin_template.png](player_skin_template.png) (the default skin, clear overlay layer). The map of regions is
  [player_skin_guide.png](player_skin_guide.png) (base regions outlined in amber, overlay regions in blue).
- **Base layer:** head, body, arms, legs. Alpha is ignored there: the base is forced opaque, so nobody can go invisible.
- **Overlay layer:** hat (32,0 32×16), jacket (16,32 24×16), right sleeve (40,32 16×16), right pants (0,32 16×16), left sleeve
  (48,48 16×16), left pants (0,48 16×16). Alpha is kept, so hats, jackets, sleeves and pants can have holes.
- **Limits:** PNG only, exactly 64×64, at most 64 KB. The bytes are decoded with `Image.load_png_from_buffer` and nothing in them is
  ever executed. Your own skin is the only one kept on disk: `user://skin.png`, with its sha256 (of the canonical re-encoding) in
  `Settings.skin_hash` (`[player] skin_hash` in the settings file). A damaged or swapped file is re-validated and refused.
- **Where it shows:** the third-person body and the first-person hand (`PlayerSkin.apply`). Gameplay hitboxes and the 1.60 m scale are
  unchanged.
- **File picking:** the platform's native file dialog when the display server has one (desktop, Android and iOS document pickers),
  else Godot's own `FileDialog` (Quest). SAVE TEMPLATE writes to the chosen path, else to the Downloads folder.

## Sharing in co-op

- **Backend** (`backend/skins.mjs`, tests `backend/skins.test.mjs`): one skin per signed-in account, stored by the sha256 of the uploaded
  bytes under `<data>/skins/files/`. `POST /api/skins/upload` (raw PNG body, `x-session-token` header; at most 64 KB; the server checks
  signature, every chunk CRC, 64×64, colour type, and that the pixel stream inflates to exactly the promised size), `POST
  /api/skins/mine`, `POST /api/skins/clear`, `GET /api/skins/files/<hash>.png` (immutable, public), and `POST /api/skins/remove`
  for owners (KYTTU / AYTTU), which also blocks the hash from coming back. Uploads are limited to 5 per account per 10 minutes.
  `LASTROUTE_SKINS_DIR` overrides the folder. Deploys go through the manual `deploy.sh`.
- **Client** (`SkinSync`, `Backend.skin_sync`): signed-in players upload their skin; the room/peer state carries only the hash
  (`"skin"`). Each peer downloads a hash once, checks that the bytes hash to it and validate as a skin, and keeps it **in memory only**
  (`PlayerSkin` peer cache, at most 16): nothing downloaded is ever written to disk. A peer's skin is freed when they leave, and the
  whole cache is emptied when you leave the room, when the run's scene ends, and on quit.
- **Local-only:** guests and offline players wear their skin on their own screen; it is never uploaded and no hash is published.

Code: `PlayerSkin` (`src/game/player_skin.gd`), `SkinPanel` (`src/ui/skin_panel.gd`). Suites: `player_skin`, `skin_share`.
