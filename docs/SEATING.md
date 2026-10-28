# Seating and the hunter-scale rescale

The world is built for a normal hunter (2.67 m, see [SCALE_FIT.md](SCALE_FIT.md)). Most furniture models were authored
person-sized, so a hunter would perch on a child's chair. This pass rescales them and splits multi-seats into separate
seats.

## Rescale (`PropModelCatalog.HUNTER_SCALE`)

- **What scales:** a per-type uniform factor, 1.5 for almost everything (the gothic canopy bed is 1.48, so it stays
  under the hunter-scale bed length). It covers every chair, stool, bench and sofa you can sit on, the beds, the
  counters, kitchens, sinks, toilets, urinals and showers, the racks, the filing cabinet, the floor lamps and the coffee
  table. Those are the props that were outside the hunter-scale ranges in `scale_fit`.
- **Where it applies:** `ModelSlot.instantiate_prop` scales the model's children, not its root, so the view's position
  and yaw stay as they were.
- **Who sees it:** the streamed view, the collider emitter (`tools/props/emit_collider_sizes.tscn`, which writes
  `PropColliderSizes`) and every audit read the same scaled model. Colliders, room placement and the hiding and rest
  cameras follow from that.
- **Emitter limits:** the height cap went to 3.4 m (the ceiling is 4 m), so a hunter-sized shower stall is solid all the
  way up. The worktop caps (vanity, serving counter, checkout, concession) are 1.5 times what they were.

## Separate seats (`PropModelCatalog.SEAT_COUNTS`)

| Prop | Seats |
| --- | --- |
| `waitingChairs` | 3 |
| `loungeCouchWide` | 3 |
| `loungeCouch` | 2 |
| `mallBench` | 2 |
| `greenhouseBench` | 2 |
| `gothicBedroomBench` | 2 |
| `publicShowerBench` | 2 |

Everything else is one seat.

- **Interactables:** each seat is its own interactable, spaced evenly across the prop's width, with its own prompt and
  camera, so you pick a seat by looking at it.
- **For hunters:** each seat is also its own entry in the hunters' navigation (`seat_spots`).

## Who sits where (`src/game/seat_occupancy.gd`)

- **Taken seats:** each frame the route collects every occupied seat: teammates from their replicated `seat_at` (and
  `seat_top`), and hunters from their seated views. A seat within 0.35 m of an occupant offers no "SIT DOWN" and refuses
  the sit, and no hunter picks it.
- **Three on one row:** the local runner, a teammate and a hunter can each take their own seat of one row at the same
  time.
- **How peers see a seated runner:** in the mannequin's `sit` clip, lifted to the hunter-scale seat
  (`seat_top - PlayerController3D.SIT_CLIP_SEAT`).

![Three on one waiting-room row](seating_three_on_a_row.png)
![The same row from the side](seating_three_on_a_row_side.png)

The captures come from `tools/look/bench_seats.tscn`.

## Sitting (runner)

- **Seat height:** the view measures each seat model's pan (`StreamedFacilityView3D.seat_top`). It takes the highest
  upward face over the middle of the seat, in front of the backrest and below the backrest and arm tops, cached per
  model.
- **Eye height:** 0.70 m above that pan (`PlayerController3D.SIT_EYE_ABOVE_SEAT`). On a hunter seat (pan about 0.68 m)
  the 1.60 m runner's eye is about 1.38 m.
- **Fallback:** authored seats without a measurement (Night Watch) keep their own exact point.

## Hunters sitting (`src/game/hunter_seats.gd`)

- **Who sits down:** a patrolling hunter (wandering or idle, no runner within 14 m) now and then walks to a free seat
  within 12 m. Two hunters never pick the same seat.
- **Seated:** she faces out of the seat in the shared `sit` pose (`assets/hunters_blocky/night_watch_poses.json`,
  authored in `tools/blocky_hunters/nw_poses.py`), and stays 12 to 28 s.
- **Senses:** she is not hunting, but she still listens and looks.
- **Getting up:** a runner noise of 2 or more within 12 m, or a runner in sight within 14 m, gets her up at once. She
  then goes to look where the runner was. A hidden runner does not get her up.
- **Chance per second of patrol:** Relaxed 1.2%, Normal 0.7%, Hard 0.2%, Nightmare never. Voids and the secret
  creatures never sit.
- **Replication:** the hunter report carries `seated` and `seat_yaw`.

## Check

The `seating` suite covers:
- **Every sit type:** it is rescaled, and its seat pan is in range for its kind: chairs 0.55–0.85 m, bar stools
  0.85–1.15 m, sofas, benches and the beach lounger 0.30–0.75 m. Each seat is at least 0.6 m wide and 0.55 m
  deep, so a seated hunter fits.
- **Multi-seats:** each has the listed number of seats.
- **Generated chunks:** the navigation lists every seat, each seat lies inside its own prop, and no seat lies inside
  another solid prop (tables and desks are allowed).
- **Reachable:** every seat has open, clear floor on at least one side (in front, or beside a chair at a table).
- **Occupancy:** three on one row works, a taken seat offers no prompt and refuses the sit, the runner's state carries
  the seat, and a hunter picks only the free seat.
- **Hunter seats:** the difficulty and Void rules, walking to a free seat, two hunters on one row taking different
  seats, sitting, a far quiet runner not getting her up, and a noise or a sighting getting her up.

`rest_and_sleep` checks the runner's seated eye against each seat's measured pan.
