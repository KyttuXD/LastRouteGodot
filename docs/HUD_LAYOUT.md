# HUD layout

The in-game HUD (`src/ui/hud.gd`, `scenes/hud.tscn`) is laid out from content, not from fixed boxes. Every game that uses
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
- **Stack under the bar**: stats panel, then the message toast, all top centre. Minimap (or zone name) top right, FPS top left.
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

`hud_overlap` (`scripts/validate_hud_overlap.gd`) opens the streamed route at 480x270, 926x728, 1024x768, 1280x720, 1440x840,
1920x1080, 3440x1440 (ultrawide) and 844x390 (phone landscape) and, in each, checks the states solo, full status bar (long
server name + ADMIN ACTIVE + public line), co-op chat with messages, chat open, toast + prompt, spectator, no map, and zone name:
every panel inside the safe margin, no two panels overlapping, no visible empty panel, status text not cut off when it fits, the stats
panel without dead space, text at least 12 px, chat at most a quarter of the window high and collapsed again afterwards.

Captures (`tools/look/hud_capture.gd`, run windowed on the Mac mini with `mini-run.sh ... --scene res://tools/look/hud_capture.tscn`):

| State | Capture |
| --- | --- |
| Last Route, 1280x720 | `hud_layout_route_1280x720.png` |
| City (no map, zone name), 1280x720 | `hud_layout_city_1280x720.png` |
| City, 1920x1080 | `hud_layout_city_1920x1080.png` |
| Last Route, phone landscape | `hud_layout_route_phone844x390.png` |
| City, phone landscape | `hud_layout_city_phone844x390.png` |
| Last Route, ultrawide | `hud_layout_route_ultrawide3440x1440.png` |
