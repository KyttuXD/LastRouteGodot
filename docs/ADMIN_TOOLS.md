# Admin tools (in-game overlay)

Press **0** on the streamed route (or the older main_3d mode) to open the admin overlay. It is built by `AdminMenu.attach`
and exists **only** when `Build.tools_enabled()` is true: a debug build with tools, or a live primary-server owner / scoped
admin login (`KYTTU` / `AYTTU`, see `backend/README.md` "Accounts and release admin"). A normal player, or an admin of the
wrong scope, never gets the node, the key handler or any action; every row carries a permission scope (`player`, `world`,
`hunters`, `visual`, `inventory`, or `owner_only`) and an unscoped row fails closed for delegated admins. In an online room
or the PUBLIC route, a guest's request goes to the host as a ticket-verified `admin_world` event; nothing here works without
that auth. Modelled on the 2D game's ADMIN debug section (`LastRoute/games/last-route/docs/ADMIN-DEBUG.md`).

## What is in it

* Creative inventory (all items), player tools (full lamp, restore, clear stun/cooldowns), teleport to start / checkpoint,
  no-target ("hunters ignore me"), god mode (also infinite stamina), noclip.
* **Run speed** 1x / 1.5x / 2x / 3x.
* **Teleport** one chunk N/S/E/W (lands on the chunk's centre, where the main halls cross), nearest safe room, nearest relay.
* **Game speed** pause / 0.25x / 1x / 2x / 4x / step one frame. Solo runs only: refused in the PUBLIC route and in rooms with
  other players (it would desync them).
* Hunters: stun / wake / calm / **freeze all / release all**, summon or remove any A-Z or Void hunter, and a status readout of
  the six nearest hunters with state, distance, FROZEN / ASLEEP.
* **Hunter emotes**: play any hunter emote on every active hunter within 40 m ([HUNTER_EMOTES.md](HUNTER_EMOTES.md)).
* World: grant / all relays, damage / repair checkpoint, all region lights, story scenes, map and hunter reveal.
* Copy seed, copy room code (no run flag).
* Owner only: admin roster add / remove.

## ADMIN ACTIVE badge and DEBUG RUN

While the overlay exists a badge shows "ADMIN ACTIVE // SOLO | ROOM | PUBLIC ROUTE" at the top centre (a segment of the HUD status bar, see
[HUD_LAYOUT.md](HUD_LAYOUT.md)), also while the panel is
closed. Using any tool marks the run a **DEBUG RUN** (`GameState.debug_run`, shown on the badge and in the readout): it records
nothing (`Backend.account_save_progress` and `account_discover_hunter` return early) until a new run starts. Roster edits and
read-only rows opt out with `"no_debug": true`.

## Not ported

Server-side public-route admin endpoints (reset resume, wipe state) would need new authenticated backend endpoints and are not
part of this overlay; the PUBLIC route status shows in the readout only. There is no time-of-day or hour system in Godot 2.

Checked by `scripts/validate_admin.gd` (`godot --headless res://scenes/validate.tscn -- admin`).

## FULLBRIGHT / WIREFRAME debug view

Every admin menu (Last Route, the City, Night Watch) has a DEBUG VIEW section: TOGGLE FULLBRIGHT and TOGGLE WIREFRAME; F7
(action `debug_fullbright`) toggles fullbright while an admin menu exists. Admin only (`Build.tools_enabled()`), never on a public
route, shown in the ADMIN ACTIVE badge, local to this client. Fullbright puts a flat white-ambient Environment (no fog, glow, SSAO,
SDFGI) on the current camera, so the world's Environment and every light keep their real values and gameplay light rules are
unchanged; off restores the camera's own environment exactly, and leaving the run turns it off. Tests: `debug_view`; rendered
brightness check `tools/look/fullbright_check.tscn` (Mac mini).
