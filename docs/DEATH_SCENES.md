# Death lines and the death moment

Ported from the original 2D game. The
catalog is the original game's own file, `assets/data/death_lines.json` (`kyttu-death-lines/v1`), so Night Watch and Last
Route read the same lines.

## Lines

`DeathLines.pick(cause, seed, depth, name)` (`game/config/death_lines.gd`) returns `{text, source, style}`.

- A cause is `{hunter_id, via, detail}`. `via` is `contact`, `deal` (Zellia's fatal deal) or `cold` (Wynelle's freeze);
  Nyxie is `darkness` (the timer woke her) or `nyxie` (dead lamp).
- Deaths with their own cause pool draw from one union pool: the cause lines plus the hunter's own lines and `loreLine`.
  Every other death draws from the hunter's pool. Then the fallback, then the hard-coded copy.
- The pick is seeded: FNV-1a of `seed|depth|hunter|cause`, so the same death on the same route shows the same line on the
  host and on guests. Void ids map `void_red` -> `voidred`.
- A line is a string or `{text, style: "caption"}`. All 12 Voids and every cause line are captions.
- Kathy has no lines and stays silent: no moment plays, the end card stays plain. `[PLACEHOLDER]` lines render only in
  debug builds. The catalog has none left.

## The death moment

`DeathMoment` (`game/hud/death_moment.gd`): a dark subtitle box low on the screen, the catcher's name in spaced capitals,
the line typed one word every 250 ms (a caption shows whole, in italics). No jumpscare, nothing flashes.

| | |
| --- | --- |
| Input | click, tap or any key finishes the typing, then dismisses; Esc dismisses at once; the first 400 ms are ignored so the key held at death cannot skip it |
| Auto close | 7 s after the line is fully shown |
| Reduced motion (`Settings.reduced_motion`) | whole line at once, no fade |
| Short mode (`Settings.short_death_scenes`) | whole line at once, closes after 2.5 s |
| Solo | plays before the end card |
| Co-op / public route | an overlay only: the spectator hand-off happens at once and the host keeps simulating |
| Party wipe | no second cutscene; the final catcher's line is shown on the RUN OVER card |

Both capture flows play it (`infinite_route_test.gd`, `main_3d.gd`). The end card keeps its stats and reason text.
Captures: `docs/images/death_moment_typed.png` (Aki, mid-typing), `docs/images/death_moment_caption.png` (Red Void caption), made with
`dev/look/death_capture.tscn`.

The two settings are stored (`Settings.set_reduced_motion`, `set_short_death_scenes`); the settings panel has no toggle
for them yet because it is a hand-laid scene, so they are reachable from the config file only.

Validator: `death_lines` (all 38 hunters present, seeded and deterministic, every cause pool reachable, Kathy silent, the
input guard, typing and reduced motion).
