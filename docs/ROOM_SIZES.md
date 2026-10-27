# Room sizes by purpose

Rooms used to be near-uniform (9x9 minimum, 11x9 pairs, 21x9 halls). Sizes now follow what a room is for.

## The profile table

`src/config/room_size_profiles.gd` (`RoomSizeProfiles.PROFILES`) gives every room type a min / preferred / max footprint, how many
of its signature tables it should hold, and its signature props. Small rooms (bedroom, bathroom, cell, utility) keep the 9x9
playable minimum and stay small; halls and corridors are not rooms. Types the generators do not make yet (classroom, lecture
hall, open office, lobby, ballroom, warehouse, library, gym, greenhouse, workshop) are listed with `generated: false` so new
districts and the city start from the same table. `RoomSizeProfiles.within(type, size)` is what the validator uses.

| Purpose | Profile (cells) | Furniture |
| --- | --- | --- |
| restaurant / mess / dining hall | up to 21x21 | 6-12 long tables with chair rings, serving counter along the back wall |
| ballroom, lecture hall, open office, warehouse, library, gym | 21x15 up to 41x33 (planned) | table/desk/shelf grids |
| kitchen, living room, arcade | 11x11 up to 15x15 | counters and appliances / seating group |
| bedroom, guest room, bathroom, cell | 9x9 up to 13x13 | the signature piece plus dressing |

## Great halls (21x21)

A side of a dense chunk (hotel, prison, maze, mansion) can merge its two middle bank cells and the east-west hall between
them into **one 21x21 room** that opens through one door onto the vertical hall (`StreamedRouteGenerator.large_plan`):

- the plan is a pure function of the seed and the chunk, so host and guests agree;
- it needs the neighbouring chunk across that seam to be a dense district too, and it is never made on the maze's
  office-suite side;
- both chunks at the seam give up the middle seam row and trim the middle hall (`hall_trimmed`), so no dead-end hall stub is
  left; the trimmed stub becomes a 21x3 solid strip between two banks (visible as the dark bars in the map);
- shared walls, the single hall between banks, hall widths, doors straight onto halls, no humps and the streamed seams are
  unchanged elsewhere (`hallways`, `humps`, `density` still pass).

Chances per side: maze 35 %, prison 30 %, hotel 25 %, mansion 30 %. Types: maze and hotel `restaurant_dining`, prison
`prison_cafeteria`, mansion `dining_room`.

Templates scale with the room: a hall of 15x15 or more uses `restaurant_hall` (3 columns x 3 rows of party tables, a chair ring
on every table, ceiling lights, a three-part serving counter on the back wall), `prison_mess` (nine bolted tables, serving
counter, kitchen rack, tray return) or `dining_hall` (six long tables with head chairs and chandeliers). Rows are 5 cells
apart and columns 6 so every table has walking lanes of 2+ cells; the door side stays clear. The collision pass
(`PlacementClearance`, `docs/COLLISION.md`) still runs on them: keep-clear zone at the door, every table reachable.

## Validators

- `room_sizes`: every generated room inside its profile; great halls are 21x21 with a table count inside the profile and a
  chair ring (3+ chairs per table, except the bolted prison tables); every table can be walked up to at radius 0.3; both
  chunks at a great-hall seam closed row 22 and trimmed the hall; the plan is deterministic.
- `collision` / `hallways` / `humps` / `density`: unchanged rules. Notes: the density limit for the mean door-to-hall distance
  went from 2.5 to 3.0 (the maze's office suite weighs more now that fewer bank rooms open directly on a hall); the pocket
  check in `CollisionAudit` counts connected patches of 1.5 m2 or more instead of isolated points between chairs.

## Before and after

Top-down map, hotel chunks `BIG-A` 0..3 x 0..3 (left: great halls off, right: on): `docs/room_sizes_before_after_map.png`.
One screenshot per district's great hall (hotel, maze, prison, mansion): `docs/room_sizes_great_halls.png`
(`CAP_GREAT=1 CAP_WAIT=100 godot --path . res://tools/look/capture.tscn -- OUTDIR TAG SEED`).

## Not done

- Other district-specific large rooms (carnival big top beyond 21x9, gothic great hall, greenhouse, library) are in the table
  but only the four gathering rooms above are merged; the same mechanism takes more types.
- Apartments keep their suite layout; hotel bathrooms/guest rooms stay 11x9.
- A great hall is always 21x21 (two banks and the hall between); 21x15 or 33-wide halls need another merge shape.
