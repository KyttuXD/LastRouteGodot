# Hunter emotes

Hunters perform short in-world emotes as personality moments: a taunt when they spot you, a shrug when they lose you, a yawn while they patrol, a victory pose when everyone is down. **Players do not emote.** (A player emote wheel was built and dropped; nothing of it is in the game.) An emote is presentation only: it never pauses a hunter's pathing, perception or capture.

## How it works
- `HunterEmoteCatalog` (`game/config/hunter_emote_catalog.gd`): 14 emotes. The array index is the wire value, so only ever **append**. Each has a wanted clip, fallback clips, a face, a duration, an audio-noise radius and whether the clip may play while the hunter is moving.
- `HunterEmoter` (`game/hunters/ai/hunter_emoter.gd`): the host decides when. It calls `HunterBrain.start_emote(id, seconds)`.
- `HunterBrain.emote_id / emote_seq / emote_left`: plain data on the brain. They are saved in the stored hunter state (`StreamedWorldState.store_hunter` / `restore_hunter`) and so travel to guests in the ordinary hunter report. `emote_seq` changes for every new emote; a late joiner starts a running emote with the time left.
- `HunterView3D` (every peer): sees a new `emote_seq`, resolves the clip, plays it, shows the face, and for noisy emotes plays a small quiet cue (`Sound.hunter_laugh`) scaled by distance to the camera, silent beyond the radius.
- **Fallbacks:** wanted clip -> hunter's personal clip -> the catalog's existing shared clips (`emote_cheer`, `emote_bow`) -> Void stand-ins (`emote_loom`, `emote_stare`, `emote_tilt`, `emote_twitch`) -> **face only** (a `BlockyFace` expression, which the state-driven faces already handle). A missing clip is never an error. Kathy carrying her scythe is always face-only (her hands hold the shaft). The clip only replaces walk/idle while the hunter is standing (or the emote is marked `moving`); stun, flight and charge always win.

## When they happen (all rare; `HunterEmoter`)
| Trigger | Emotes | Chance | Notes |
| --- | --- | --- | --- |
| spot: a chase begins | taunt, laugh | 0.30 / 0.27 / 0.15 / 0.08 | Relaxed / Standard / Hard / Nightmare (`emote_spot_p`) |
| lose: a chase ends | shrug | 0.50 | |
| search: 1.2 s into a search | look around | 0.35 | once per search |
| chase: sprinting, runner >= 3.5 m away | point, beckon | 0.035 / s × 1.0 / 0.9 / 0.5 / 0.25, 14 s apart | `emote_chase_scale` for Relaxed / Standard / Hard / Nightmare; the only emotes during a chase, on purpose |
| idle: standing still 2 s in IDLE | stretch, yawn, hum, wave | 0.035 / s, 20 s apart | never while patrolling |
| stun begins | flinch | always | |
| a runner is caught, others alive | smug, dance, laugh | 0.85 | queued until she is no longer stunned (8 s limit) |
| everyone is down | victory | always | hunters within 30 m of the last catch |

Also: 8 s global cooldown between emotes (flinch excepted); nothing starts while another is playing, while Xivvy flies or Loxelle charges, or while a post-catch emote is queued. The idle clock starts at 6 s so a hunter never fidgets the moment she spawns. A catch itself is unchanged: no jumpscare, it goes to game over / spectating.

Noise: laugh (7 m), dance (5 m) and hum (4 m) are audible as a small cue; the rest are silent. They do not feed the hunters' own hearing.

## Personality (`HunterEmotePersonality`)
A multiplier per emote per hunter (`HunterEmotePersonality.WEIGHTS`): Ferryn's taunt, laugh, hum, smug, dance and victory are 0, and her point / beckon are 0.4× / 0.3×; Glyra hums 3× and dances 2×; Kathy's taunt, smug and dance are 0 and her wave is 1.5×; Aki stretches and waves at 1.5× and taunts at 0.2×; Ilyra's point and beckon are 0; Void hunters' laugh, hum, dance, wave, yawn and stretch are 0 (smug stays 0.5×). `CLIP_OVERRIDES` lets a hunter use a personal `emote_*` clip from `assets/hunters_blocky/emotes.json` for a given emote (Aki's `emote_shy` for her stretch is wired as the example). Add rows to tune; an unlisted hunter weighs everything 1.

## Clip spec for the blocky-hunters session
Status: every non-Void hunter now has all 14 emote clips (merged from the blocky session); Void hunters use the stand-ins below and are face-only for laugh, dance, stretch, yawn, hum and wave. Clips stay optional in code (face-only is the fallback). Build them on the shared blocky rig, named exactly as below, **one-shots** that start and end near the idle pose (the view returns to walk/idle by itself when the emote time is up), no root motion, length about the catalog seconds (a clip shorter than the emote simply holds its last pose). Existing shared clips already cover `emote_wave`, `emote_shrug`, `emote_cheer` and `emote_bow`.

| Clip | Length | Moving? | Pose / motion | Face |
| --- | --- | --- | --- | --- |
| `emote_taunt` | 1.0 s | yes (plays at a run) | upper body only: head tilts up and back, one hand beckons "come on" (legs keep the chase stride) | scream |
| `emote_laugh` | 1.6 s | no | head back, chest shakes, a hand on the belly | happy |
| `emote_point` | 1.2 s | yes | right arm straight at the runner, head follows; legs keep running | chase |
| `emote_beckon` | 1.4 s | yes | one arm forward, forearm curls toward the body twice | happy |
| `emote_look_around` | 2.2 s | no | slow body-twist left, pause, right, hand shading the eyes | derp |
| `emote_smug` | 2.2 s | no | arms crossed or hands behind the back, chin up, slow nod | happy |
| `emote_dance` | 3.0 s | no | quick side-step sway, arms alternating up, small bounce | happy |
| `emote_flinch` | 0.7 s | no | short recoil: shoulders up, head ducks (plays at the start of the stun loop) | stun |
| `emote_stretch` | 2.0 s | no | arms overhead, back arch, relax | blink |
| `emote_yawn` | 1.8 s | no | one fist to the mouth, head tips back, shoulders drop | blink |
| `emote_hum` | 2.4 s | no | gentle sway, fingers tapping at the hip | happy |
| `emote_victory` | 3.5 s | no | fist pump, arms raised, a small hop, hold | happy |

Void hunters (no mouth or hands to speak of) use their shared clips instead: loom (taunt, smug, victory), stare (point, beckon), tilt (shrug, look around), twitch (flinch). They need nothing new.

To make a hunter use a different clip for one emote, add `"hunter": {"emote id": "emote_clip"}` to `HunterEmotePersonality.CLIP_OVERRIDES` (and list the clip in `emotes.json`).

## Admin
Admin menu -> **PLAY HUNTER EMOTE // NEARBY**: every active hunter within 40 m of you plays the chosen emote now (host-authoritative, `hunters` permission, ignores the rules and cooldowns). Useful for checking which hunters have a clip and which are face-only. See [ADMIN_TOOLS.md](ADMIN_TOOLS.md).

## Checks
- `Godot --headless --path . res://tests/scenes/validate.tscn -- hunter_emotes`: catalog order, faces, clip fallbacks, personality, every trigger rule (with certain rolls), no-freeze, stored-state round trip, view behaviour (clip, face-only, stun, moving, scythe).
- `tools/build/coop_test.sh` and `tools/build/public_test.sh`: a hunter emote started on the host shows on the guest.
- `dev/look/hunter_check.tscn` (`HUNTERS=...`) shows hunters; emotes are visible in play via the admin row.
