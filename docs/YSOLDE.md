# Ysolde avoids you

Intentional deviation from the 2D game (HUNTER_PARITY.md): Ysolde is a timid battery thief. Her battery theft is unchanged; how she moves near the runner changed, and (KT's ruling) she is no
longer capture-immune: a runner who catches up to her or blocks her way is grabbed like by any other hunter.

* When the runner is within her keep distance and in her line of sight, she retreats along the real nav graph to a cell
  that gains distance, is reachable, is not a dead end and whose route does not pass the runner (`YsoldeGimmick.flee_target`).
* Cornered: she freezes (holds position) instead of teleporting. While the runner is still close she holds and watches;
  once the runner is well away she forgets the spot and returns to wandering and her battery errands.
* `YsoldeGimmick.BEHAVIOUR` picks the style for KT: `"avoid"` (keeps about 9 m, short retreats, normal pace, default) or
  `"run"` (bolts 14 m away at 1.35x pace and gives up the area for 6 s).
* Host-authoritative like all hunter brains (solo, co-op and public routes alike).
* Validator `ysolde`: retreats gain distance and are reachable, she never ends closer to a runner in sight than she
  started, never catches from a distance and catches a runner who reaches her. `hunter_real` / `hunter_nav` pass with her fleeing.

Not done yet: a scared emote / squeak cue when she notices the runner (`noticed_at_msec` is set for it), and a coop scenario.
