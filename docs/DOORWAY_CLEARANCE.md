# Doorway clearance

Since the hunter scale-up (1.5x, [SCALE_FIT.md](SCALE_FIT.md)) a normal hunter is 2.67 m tall (up to 3.2 m with hair,
ears, horns or a halo) and 1.38 m across the shoulders, while the authored door frames opened 2.375 m high (gothic 2.31 m)
and 0.87 m wide (boarded doorways 0.84 m wide, 2.16 m high). They walked through the frames. Three things fix it, none
touches a .glb and none changes the slim hunter collision capsules.

## 1. The doors are sized for the hunters (`DoorwayFrames`, `src/game_3d/doorway_frames.gd`)

KT: the world is built at hunter scale (a normal hunter is the "human"), so doors give a normal hunter 40 cm over her
head and room at the shoulders, and she walks through without ducking.

* **Two-cell doors**: every room with a side of 4 cells or more (and every suite entrance) gets a two-cell double door
  (`StreamedRouteGenerator`, 1.98 m clear: 30+ cm each side of 1.38 m shoulders, arm swing calmed). Only rooms under 4
  cells and the rooms inside a suite keep a one-cell door (0.98 m clear), where she turns her shoulders. Sampled by
  the validator: 527 two-cell, 24 one-cell.
* **Raised**: room doors (all six types) and boarded doorways are stretched upward to a 3.15 m clear opening
  (`TARGET_OPENING`: 2.67 m + 40 cm + 5 cm for the clip's bob), frames at most 3.65 m tall (`FRAME_TOP_CAP`; gothic
  crests 4.02 m). Ceilings rose to fit: rooms start at 3.7 m (`RefLook.ROOM_RANGE`), gothic rooms and halls at 4.1 m,
  the legacy facility maze (boarded doorways) at 3.6 m. Frame and leaf scale together.
* **Widened to the wall gap**: the posts stood 6.5 cm (boarded: 8 cm) inside the wall gap. They are widened so their
  inner faces stand 1 cm proud of the gap faces (0.98 m, doubles 1.98 m; flush they z-fought); the outer parts sit
  inside the neighbouring wall cells. The grid is unchanged.
* **Open leaves square to the wall**: the authored open pose stood the leaf at 68 degrees, and its pivot sat in the middle
  of the leaf's thickness 7 cm inside the post, so the open leaf (and its handles) stood a quarter of the way across.
  Open is now 90 degrees (`RouteInteractable3D.DOOR_OPEN_EXTRA`), and the pivot slides 19 cm into the jamb as the door
  opens (`HINGE_SLIDE`). Closed doors look as before.
* **Registry**: every frame registers its clear opening (room doors, boarded doorways while shown, the prison cell
  doorways between the gate runs, which have no lintel). `DoorwayFrames.nearest(position)` gives the frame a hunter is
  passing and how far she is from its wall plane.

## 2. The hunters squeeze through (`DoorwayPose`, `src/game_3d/doorway_pose.gd`)

A light procedural layer on the blocky rig in the style of the Night Watch layers: additive on whatever the clip and the
head look left on the bones, undone at the start of the next frame (nothing accumulates). From 3.2 m before a frame's
wall plane it eases in, fully on from 2.0 m, and eases out after.

* **Duck** (oversized hunters only: tall hair, the Voids, the giants) when the opening is lower than her measured height + 10 cm (+ a spare for the clip's bob): knees bend, a
  forward lean, a head dip. As deep as needed, up to the full duck (about 0.3-0.75 m lower, measured per rig on bind).
* **Shoulder turn** when the opening is narrower than her shoulders + 2 x 8 cm (every 1-wide door): the upper body
  turns side-on; the head looks ahead, or turns with the body when that is narrower (side pigtails); the upper body
  shifts so the head is centred; arms hang straight and the stride and arm swing shrink; the feet come in a little.
  Ponytails, pigtails, wings and tails that stick out sideways are swept round to trail along her way.
* Only humanoid rigs bind it (`Pelvis` present); secret creature rigs keep their own size and are not scaled. Off
  beyond 45 m from the camera.

## Header over the door

KT: there was an open gap between the top of a door frame and the ceiling. Every room door cell now gets wall above the
frame in the streamed chunk mesh (`StreamedFacilityView3D.door_headers` / `add_door_header`): a face toward each side
from the soffit up to that side's ceiling, in that side's wall theme, and a soffit just under that model's raised frame
top (`DoorwayFrames.header_y`). Boarded doorways (the facility maze) stand under its 3.6 m ceiling. Prison cell doorways have no door or lintel
(an open wall gap), so they need no header.

## 3. The validator (`door_clearance`)

`scripts/validate_door_clearance.gd` builds every door type as the game does (six room doors, a cleared boarded doorway,
a prison cell doorway), measures the opening from the frame's own geometry, and walks each normal hunter (A-Z, 1.5x)
through it at walk and at run with the real clips and the pose, checking every mesh part each frame:

* body parts (`DoorwayPose.BONES`): never through a post or the wall gap, never into an open leaf; a normal hunter
  (body up to 2.70 m) never ducks, has 40 cm or more under every header and 25 cm or more each side in a two-cell door;
  taller ones 10 cm (or ducked and still clear);
* hair, ears, horns, tails, wings: may brush a frame or leaf by up to 10 cm, and every brush is listed;
* parts wider than a one-cell door whichever way she turns are listed every run under "wider than a door" and do not
  fail: Nyxie's and Wynelle's ponytails (in one-cell doors only). Two-cell doors fit everything.
* no gap over a door: in generated chunks (3 seeds, 3 floors, every biome they reach, halls up to 5.9 m) every room door
  cell gets a header; rays through the opening above the frame from both sides, up to each side's ceiling, and straight
  up through the soffit all hit wall. Every raised frame reaches its soffit.

Also checked: frames register only once in the tree and drop out when freed, the nearest-frame query ignores frames out
of reach or on another floor, no raised frame is taller than the cap.

```sh
godot --headless --path . res://scenes/validate.tscn -- door_clearance
```

Not covered: Void hunters (3.0-3.84 m, giant class; they still get the pose), lockers (hunters do not walk through them),
the boarded hallway (3 m wide, its frame goes with its boards).
