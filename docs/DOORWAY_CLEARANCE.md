# Doorway clearance

Since the hunter scale-up (1.5x, [SCALE_FIT.md](SCALE_FIT.md)) a normal hunter is 2.67 m tall (up to 3.2 m with hair,
ears, horns or a halo) and 1.38 m across the shoulders, while the authored door frames opened 2.375 m high (gothic 2.31 m)
and 0.87 m wide (boarded doorways 0.84 m wide, 2.16 m high). They walked through the frames. Three things fix it, none
touches a .glb and none changes the slim hunter collision capsules.

## 1. The frames are bigger (`DoorwayFrames`, `src/game_3d/doorway_frames.gd`)

* **Raised**: room doors (all six types) and boarded doorways are stretched upward toward a 2.95 m opening, never taller
  than 3.15 m overall (`FRAME_TOP_CAP`, under the lowest room ceiling of 3.2 m). Result: normal 2.85 m, luxury 2.72 m,
  gothic 2.47 m (single) / 2.60 m (double), boarded 2.95 m clear. Frame and leaf scale together.
* **Widened to the wall gap**: the posts stood 6.5 cm (boarded: 8 cm) inside the 1 m wall gap. They are widened so their
  inner faces meet the gap (1.00 m, doubles 2.00 m); the outer parts sit inside the neighbouring wall cells. The grid
  is unchanged.
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

* **Duck** when the opening is lower than her measured height + 10 cm (+ a spare for the clip's bob): knees bend, a
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
from `HEADER_Y` up to that side's ceiling, in that side's wall theme, and a soffit on the frame. Boarded doorways (the
facility maze, 3 m ceiling) are raised until the frame meets the ceiling. Prison cell doorways have no door or lintel
(an open wall gap), so they need no header.

## 3. The validator (`door_clearance`)

`scripts/validate_door_clearance.gd` builds every door type as the game does (six room doors, a cleared boarded doorway,
a prison cell doorway), measures the opening from the frame's own geometry, and walks each normal hunter (A-Z, 1.5x)
through it at walk and at run with the real clips and the pose, checking every mesh part each frame:

* body parts (`DoorwayPose.BONES`): never through a post or the wall gap, 10 cm or more under the header (or ducked and
  still clear), never into an open leaf;
* hair, ears, horns, tails, wings: may brush a frame or leaf by up to 10 cm, and every brush is listed;
* parts wider than a 1 m door whichever way she turns are listed every run under "wider than a door" and do not fail:
  Nyxie's and Solyth's floating glyphs (about 1.1 m across). They still pass through the frame side; they need the
  models narrowed or the doors widened (the biomes lane widens doorless 1-wide openings to 3; doors with leaves stay 1
  wide).
* no gap over a door: in generated chunks (3 seeds, 3 floors, every biome they reach, halls up to 5.9 m) every room door
  cell gets a header; rays through the opening above the frame from both sides, up to each side's ceiling, and straight
  up through the soffit all hit wall. Every raised frame reaches the soffit (`DoorwayFrames.HEADER_Y`, 3.1 m).

Also checked: frames register only once in the tree and drop out when freed, the nearest-frame query ignores frames out
of reach or on another floor, no raised frame is taller than the cap.

```sh
godot --headless --path . res://scenes/validate.tscn -- door_clearance
```

Not covered: Void hunters (3.0-3.84 m, giant class; they still get the pose), lockers (hunters do not walk through them),
the boarded hallway (3 m wide, its frame goes with its boards).
