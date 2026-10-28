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
  ever executed. The skin is stored by the sha256 of its canonical re-encoding in `user://skins/<hash>.png`; the active hash is
  `Settings.skin_hash` (`[player] skin_hash` in the settings file). A damaged cache file is re-validated and refused.
- **Where it shows:** the third-person body and the first-person hand (`PlayerSkin.apply`). Gameplay hitboxes and the 1.60 m scale are
  unchanged.
- **File picking:** the platform's native file dialog when the display server has one (desktop, Android and iOS document pickers),
  else Godot's own `FileDialog` (Quest). SAVE TEMPLATE writes to the chosen path, else to the Downloads folder.

Code: `PlayerSkin` (`src/game/player_skin.gd`), `SkinPanel` (`src/ui/skin_panel.gd`). Suite: `player_skin`. Sharing with other players
(hash on the room state, backend storage) is the next step.
