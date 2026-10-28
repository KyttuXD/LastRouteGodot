# Scale fit: a hunter-scale world, smaller runners

KT (2026-10-28): the world is built around the hunters; think of the hunters as the humans and the runners as smaller.
A normal hunter (1.5x, **2.67 m**, eye 2.27, shoulders 1.38 wide; `ScaleFit.HUNTER`) is the person the rooms, doors,
counters and beds are sized for. The runner is the blocky mannequin (`assets/hunters_blocky/player_mannequin`, 1.78 m as
authored) drawn at `PlayerModels.SCALE` = **0.9**: **1.60 m**, 0.6x a hunter.

Everything about the runner follows that one constant: the body (own and co-op peers, the name tag with it), the
standing capsule (1.53 m) and crouch capsule (0.97 m), the camera (aligned to the eye nodes, about 1.36-1.44 m), the
camera bob, the floor snap (0.25 m), the ladder let-go height, the interaction reach and the held items. The capsule
radius is unchanged. Derived table in `ScaleFit.PLAYER` (shoulder 1.31, elbow 0.99, hip 0.81, knee 0.43, hands
hanging 0.69, reach up 1.94). Crawl spaces and pipes read `PlayerController3D.CROUCH_COLLISION_HEIGHT`.

`ScaleFit.RULES` gives each prop category a range for height, long side and short side (collider boxes derived from the
models, `PropColliderSizes`): seats 0.70-1.45 m tall and at most 0.85 wide, tables 0.40-1.0, counters 0.85-1.20, sinks and
vanities 0.85-1.35, tall storage 1.2-2.25, couches 0.7-1.1 tall and 1.4-2.8 long, beds 1.8-2.35 long, lamps 1.3-2.0, toilets
0.7-1.05, showers 1.8-2.25, crates 0.3-1.2: person ranges, judged at hunter scale with `ScaleFit.HUNTER_FACTOR` (1.5x).
Suite: `scale_fit` fails on a prop wrong at both scales (and on a known outlier that got fixed), lists the props still
person-sized as the props lane's resize worklist, and fails on them too once `HUNTER_SCALE_STRICT` is switched on.
`ScaleFit.ARCHITECTURE` holds the checks for ceiling (4.0 m), room doors (raised toward 2.95 m for the 1.5x hunters, who duck the rest: [DOORWAY_CLEARANCE.md](DOORWAY_CLEARANCE.md); a person needs 2.0),
hall width (3 or 5 cells), capsule and camera, light switch height (1.45 m: within the runner's reach).

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
