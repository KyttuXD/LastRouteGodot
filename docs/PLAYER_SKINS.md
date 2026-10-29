# Custom player skins

A skin is a standard Minecraft-layout **64×64 PNG** (the old 64×32 format is accepted: the left limbs are mirrored from the right) on the player mannequin (`assets/hunters_blocky/player_mannequin`, classic
proportions). Settings → **SKIN** picks a file, previews it on a rotating mannequin, applies it, resets to the default, or saves the
template to paint over.

- **Steve and Alex:** the mannequin matches the Minecraft player model (head 8³, body 8×12×4, legs 4×12×4, arms 4×12×4 classic / 3×12×4 slim,
  hat / jacket / sleeves / pants as slightly inflated outer shells, UVs exactly per the 64×64 layout incl. the separate left arm and leg),
  scaled to the 1.60 m runner. There are two bodies on one rig: `player_mannequin` (Steve) and `player_mannequin_slim` (Alex), built by
  `tools/blocky_hunters/build.py`. The style is detected from the skin (an Alex skin leaves the arms' 4th texture column transparent) or
  the Minecraft profile's model field, can be forced with SKIN → ARMS (AUTO / CLASSIC / SLIM), and is sent with the skin hash
  (`"skin_slim"`). `PlayerSkin.set_arms` swaps the six arm meshes in place (same bones and pivots, so every clip, the ladder, swing and
  hand poses keep working); the first-person hand and the XR hands follow the style too. Nothing is stretched or converted: a Minecraft
  skin maps 1:1. References: [player_skins_steve_alex.png](player_skins_steve_alex.png) (our own Steve-style and Alex-style test skins
  `player_skin_steve_reference.png` / `player_skin_alex_reference.png` on the two bodies; `tools/blocky_hunters/render_skins.py`).
- **Template:** [player_skin_template.png](player_skin_template.png) (the default skin, clear overlay layer) and [player_skin_template_slim.png](player_skin_template_slim.png) (the same with the Alex arm layout). The map of regions is
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

## More ways to pick a skin (Settings → SKIN)

All of them end in the same preview → APPLY → (signed in) upload flow, with the same validation.

- **FROM URL:** an `https://` link to a 64×64 PNG. https only (no credentials, no localhost / LAN / numeric hosts, standard port), a
  5 s timeout, at most 64 KB, redirects are followed by hand (max 3) and each hop must pass the same checks. The bytes are only ever
  decoded as an image.
- **FROM MC NAME:** a Minecraft username → `api.mojang.com` (uuid) → `sessionserver.mojang.com` (profile textures) →
  `textures.minecraft.net` (PNG), every hop pinned to those hosts, then converted by `PlayerSkin.from_minecraft`. The template *is* the
  Minecraft 64×64 layout, so the only conversion is the old 64×32 format (left limbs mirrored from the right; no second layer). Slim
  (Alex) skins keep their 3 px arms on the slim mannequin.
  Nothing else is converted; capes and elytra are not used.
- **COPY SKIN:** pick a co-op player in the list (those whose skin is downloaded and who allow copying) and copy it; the copy comes
  from the in-memory peer cache and becomes your own skin (stored as your file, uploaded when signed in). Each player has an
  "OTHERS MAY COPY MY SKIN" box (`Settings.skin_copyable`, published as `"skin_copy"` in the co-op state; honoured by the other client).

## Account skins (the skin lives on the account)

A signed-in player's skin is stored on the server per account, so it follows them to any computer. `user://skin.png` stays only as the
offline fallback.

- **Backend** (`backend/skins.mjs`): `PUT /api/v1/skins/<ACCOUNT>` takes the raw PNG (64x64, or the old 64x32; PNG only; at most 64 KB)
  with the owner's `x-session-token` (another account gets 403) and `x-skin-arms: auto|classic|slim`; it returns `{hash, arms,
  updatedAt}`. `GET /api/v1/skins/<ACCOUNT>` is public (co-op peers) and returns `{hash|"", arms, updatedAt, versions:[hash...]}`; the
  PNG is fetched from `GET /api/skins/files/<hash>.png`. The last 5 skins of an account are kept as versions (older files are deleted;
  clearing drops them all). Uploads share the 5-per-10-minutes limit and the moderation check with the old `/api/skins/upload` route,
  which still works for older clients. Files stay under `<data>/skins/`.
- **Sign-in** (`SkinSync.pull_account_skin`): the game asks for the account's skin. No skin on the account but one on this device:
  uploaded (migration). A skin on the account and none here, or an unchanged local one: the account's is downloaded, checked against its
  hash and validated, then kept as your skin with the account's arm style. A skin picked while offline or signed out
  (`Settings.skin_pending_upload`) is uploaded instead of replaced.
- **Changing the skin** uploads it (`SkinSync.sync_own`, PUT; falls back to the old route on a server without `/api/v1/skins`).
- **Co-op:** a peer's state still carries the skin hash. A signed-in peer whose state has none yet is looked up by account
  (`SkinSync.account_skin`, cached 30 s) and their PNG fetched by hash. Guests and offline rooms keep the local-only behaviour below.

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

Code: `PlayerSkin` (`src/game/player_skin.gd`), `SkinPanel` (`src/ui/skin_panel.gd`). Suites: `player_skin`, `skin_share`, `skin_sources`.
