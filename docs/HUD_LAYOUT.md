# HUD layout

The in-game HUD (`game/hud/hud.gd`, `game/hud/hud.tscn`) is laid out from content, not from fixed boxes. Every game that uses
the shared HUD (Last Route, the City, Night Watch where it applies) gets the same rules at every window size.

## Rules

- **Safe margin**: every panel keeps `HUD.SAFE_MARGIN` (8 HUD units, scaled with the window) from the window edge and
  `HUD.PANEL_GAP` (4) from its neighbours. Nothing touches or crosses the edge.
- **Content-sized**: panels take their own minimum size. The stats panel (DEPTH, RELAYS/CHUNKS, DANGER) has no dead space;
  empty panels are hidden (zero size), never drawn as dark boxes.
- **Top centre status bar** (`HudStatusBar`): one bar for the BETA / TEST SERVER tag (`env`), ADMIN ACTIVE (`admin`) and the public
  route line (`public`). Sources call `set_segment(key, text, kind)`; empty segments vanish; the bar shrinks to the visible ones and
  hides when none are left. It yields width to the side columns (FPS left, minimap or zone right): the public line, then the server
  tag, then the admin tag are ellipsised, never clipped by the window edge. Menus keep the old standalone `TestServerBadge` label.
- **Right column**: minimap (or zone name) with the content-sized stats panel under it; the message toast keeps its fixed top-centre line under the bar; FPS top left.
- **Minimap only with data**: `FacilityMap.has_data()` hides the panel while there is no map. A scene without a map (the City) calls
  `hud.set_minimap_available(false)` and `hud.set_zone_text("OLD TOWN")`; the zone name takes the minimap's slot.
  The admin REGION MAP toggle is unchanged.
- **Chat** (`RoomChat`): no panel while there are no messages and the input is closed. It grows with the messages up to a quarter of
  the window height, sits above the interaction prompt (clear of the hotbar) and fades 6 s after the last message unless the input is
  open. `RoomChat.is_open()` is the open state; `panel_rect()` is zero-size while collapsed.
- **Stamina bar** sits 3 units above the hotbar. The spectator strip sits above both.
- **Text** is at least 12 screen pixels: `HUD._layout_hud()` raises the HUD font size (up to 9 units) on small windows, e.g. phone
  landscape. A 480x270 pixel window (1 pixel per unit) is exempt.

## Test

`hud_overlap` (`tests/validate_hud_overlap.gd`) opens the streamed route at 480x270, 926x728, 1024x768, 1280x720, 1440x840,
1920x1080, 3440x1440 (ultrawide) and 844x390 (phone landscape) and, in each, checks the states solo, full status bar (long
server name + ADMIN ACTIVE + public line), co-op chat with messages, chat open, toast + prompt, spectator, no map, and zone name:
every panel inside the safe margin, no two panels overlapping, no visible empty panel, status text not cut off when it fits, the stats
panel without dead space, text at least 12 px, chat at most a quarter of the window high and collapsed again afterwards.

Captures (`dev/look/hud_capture.gd`, run windowed with `--scene res://dev/look/hud_capture.tscn`):

| State | Capture |
| --- | --- |
| Last Route, 1280x720 | `hud_layout_route_1280x720.png` |
| City (no map, zone name), 1280x720 | `hud_layout_city_1280x720.png` |
| City, 1920x1080 | `hud_layout_city_1920x1080.png` |
| Last Route, phone landscape | `hud_layout_route_phone844x390.png` |
| City, phone landscape | `hud_layout_city_phone844x390.png` |
| Last Route, ultrawide | `hud_layout_route_ultrawide3440x1440.png` |

## Porcelle's radar ping

Porcelle (radar tracked) shows on the HUD minimap only as a short ping: a dot with one expanding ring for 0.7 s, roughly every
8 s (+- 2 s, fixed per cycle), hidden in between, in the active scheme's alert colour. Out of the minimap's range she clamps to the
edge as a small arrow pointing at her. Only she is shown (other hunters need admin reveal), only while active, and guests see the
same thing from the replicated hunter marks (nothing extra is sent). Reduced motion draws a steady dim dot with a slow, small fade.
The full facility map keeps her steady ghost mark. Tune cadence, duration, ring and alpha in `game/hud/radar_ping.gd`.
Test: `minimap_radar`. Frame sequence (start, rising, peak, ring, fading, between, reduced motion): `radar_ping_sequence.png`
(`dev/look/radar_capture.tscn`).

## Region and district names are admin-only

`RegionNames` (`game/config/region_names.gd`): players see `LEVEL -1`, admins (`Build.tools_enabled()`: owner, scoped admin, room
admin ticket) see `LEVEL -1 // SEWER`. The City's zone panel and the map's region key stay empty for players. Decided per peer,
locally. Test: `region_names`.

## Control hints

Prompts name the key for the device the player last used (`InputGlyphs`, `game/ui_common/input_glyphs.gd`): keyboard/mouse from the live
InputMap (a rebind changes the prompt), gamepad from its joypad bindings, phone touch buttons (USE, JUMP, D-PAD...), Quest controllers
(TRIGGER uses, GRIP climbs, A lets go). Every interactable prompt reads "[E] OPEN DOOR", "[E] HIDE IN WARDROBE"; hidden: "[E] LEAVE"
("LOCKED IN // 3s" while locked); climbing: "HOLD [W]/[S] CLIMB // [SPACE] LET GO" (LET GO only near the bottom, where jump works);
furniture and sleep prompts use the same glyphs. The prompt sits just under the crosshair and fades in/out; the chat panel stays below
it. Test: `prompt_glyphs`.

## Full map follows the runner

The full-screen map opens centred on the runner and glides after them while open (`FacilityMap.follow_player`, `FOLLOW_RATE`),
zooming about them. Dragging, the stick, arrow keys, a trackpad or a one-finger touch drag pans away and stops following; the RECENTER
button (shown with the jump key for the active device) or the jump key brings it back. Pinch / trackpad magnify zooms on touch. The
zoom is remembered between opens (`FacilityMap.remembered_zoom`). Teammates, hunters and waypoints draw as before; the title shows the
current floor. Test: `map_follow`.

## Spoken chat, channels and quick chat

`RoomChat` (`game/menus/room_chat.gd`). Typed lines (80 characters, chat key / CHAT touch button / headset keyboard) are SPOKEN with
the OS text-to-speech voice of their sender (`DisplayServer.tts_speak`; a stable voice, pitch and rate per peer,
`RoomChat.voice_for`). Loudness: NEARBY falls off over 25 m on the same level, halved through walls (a ray from the camera),
silent beyond and from other levels; TEAM is at least a quiet radio (35 %) for everyone. Each line shows as a speech bubble over
the speaker and a subtitle at the bottom (Settings, on by default); there is no chat log, only "SAID RECENTLY" in the pause menu
with MUTE per speaker. Speaking makes a hunter noise sized by length (a SHOUT or "!" is louder). No voices installed: subtitle +
a soft blip. Settings > AUDIO: SPOKEN CHAT volume, VOICES (off = subtitles only), SUBTITLES.
Moderation (host-side, `RemotePlayers.accept_line`): 3 lines per 10 s then a 5 s cooldown, quick-chat pings included (and one
ping per 2 s); exact or near-duplicate repeats within 20 s dropped; long repeated characters collapsed ("aaaaa" -> "aaa"); local
mute (pause menu); owner/admin ROOM MUTE / UNMUTE EVERYONE / KICK in the admin tools; peers cannot send system lines.
Quick chat (`quick_chat`: ` key, D-pad up, Quest left X + stick, QUICK touch button): a radial of OVER HERE!, HUNTER!, RELAY HERE,
NEED LIGHT, HIDE!, FOLLOW ME, THANKS, YES, NO, spoken like a line, plus a 6 s ping in the sender's colour on both maps (HUNTER!
on the aimed hunter). Test: `chat`.

## No server addresses for players

`ServerPrivacy` (`game/config/server_privacy.gd`): no host name, IP, port or URL in player-facing text. The BETA badge is gone; the
TEST SERVER badge shows (without an address) only for a debug build pointed at the test server. `RoomState.status_message`,
public-route status, account-panel messages and menu update text are scrubbed; a connection failure that named an address reads
"CAN'T REACH THE SERVER". Admins see `SERVER <host> // CHANNEL <channel>` in the route's admin readout only. Test: `server_privacy`.
