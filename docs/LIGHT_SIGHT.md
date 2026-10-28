# Mutual light sight

If the runner can see a hunter because the hunter stands in light, the hunter can see the runner, flashlight or not.

* `LightField.exposure_at(point, lamps, line_clear)` (`src/game/light_field.gd`): 0..1 from every lamp the LampField has for
  the resident chunks (all visual lamps, not only the budgeted real lights, so the render budget never changes gameplay)
  within 25 m, falling off over the lamp range, blocked by walls (the nav floor grid line test), plus a small ambient.
* The host computes, about five times a second per hunter, the hunter's own exposure and the exposure of the runner it is
  after (`HunterBrain.self_exposure`, `target_exposure`); guests only render.
* Sight limit (`HunterBrain.sight_limit_for`): with the runner's flashlight off the range follows her exposure (pitch dark
  0.35 x sight, a lamp pool 1.6 x); the flashlight rule is unchanged; and when the hunter's own exposure is at least
  `VISIBLE_EXPOSURE` (0.32) the range is at least her full sight range (line of sight still required). Hearing is
  unchanged; gimmicks still scale the result.
* Admin (visual): MUTUAL LIGHT SIGHT on/off, LIGHT PROBE HERE (the exposure where you stand).
* Validator `light_sight`: falloff, wall occlusion, flicker-off lamps, dark / old / lit ranges, the mutual case and the
  same positions with the lamp off, and the rule switch.

Not done yet: the optional HUD visibility eye, a SHOW LIGHT heat overlay, the render-luminance calibration capture, and a
coop_test scenario (the evaluation runs on the host like all hunter perception, so guests need nothing new).
