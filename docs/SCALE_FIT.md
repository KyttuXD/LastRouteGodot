# Scale fit against the player model

The player is the blocky mannequin (`assets/hunters_blocky/player_mannequin`), measured with
`tools/look/scale_measure.tscn`: height **1.78 m**, eye nodes **1.51 m** (the camera sits at 1.60, clamped 1.35-1.78),
hands hanging at 0.77 m, capsule 1.7 m. Derived table in `ScaleFit.PLAYER` (shoulder 1.45, elbow 1.10, hip 0.90,
knee 0.48, reach up 2.15). Hunters are 1.5x on purpose (2.67 m) and are not fitted.

`ScaleFit.RULES` gives each prop category a range for height, long side and short side (collider boxes derived from the
models, `PropColliderSizes`): seats 0.70-1.45 m tall and at most 0.85 wide, tables 0.40-1.0, counters 0.85-1.20, sinks and
vanities 0.85-1.35, tall storage 1.2-2.25, couches 0.7-1.1 tall and 1.4-2.8 long, beds 1.8-2.35 long, lamps 1.3-2.0, toilets
0.7-1.05, showers 1.8-2.25, crates 0.3-1.2. Suite: `scale_fit` (fails on any new outlier, and on a known outlier that got fixed).
`ScaleFit.ARCHITECTURE` holds the checks for ceiling (4.0 m), room doors (raised toward 2.95 m for the 1.5x hunters, who duck the rest: [DOORWAY_CLEARANCE.md](DOORWAY_CLEARANCE.md); a person needs 2.0),
hall width (3 or 5 cells), capsule and camera.

## Outliers (current -> target)

| Prop | Now | Target | Owner |
|---|---|---|---|
| singleBed | 2.67 m long | about 2.1-2.3 | props lane (model) |
| doubleBed | 2.67 m long | about 2.1-2.3 | props lane (model) |
| gothicDoubleBed | 2.79 m long | about 2.2-2.35 | props lane (model) |
| bathroomVanity | 1.69 m tall | 0.9-1.35 without the mirror, or a separate mirror | props lane |
| prisonServingCounter | 1.75 m tall | 1.0-1.2 counter plus a separate hood | props lane |

Everything else in the 92 collider-sized props sits in range. Not covered yet: held and pickup item sizes against hand
size, door handle and light switch heights, stairs/ladder step height, Night Watch props (cube-built, no collider table),
and the before/after lineup capture. Raised room doors (2.47-2.85 m clear) are well over the player: deliberate for the 1.5x hunters.
