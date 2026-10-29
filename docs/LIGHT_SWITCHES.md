# Room light switches (streamed world)

The finite route had toggleable room lights (`facility_view_3d._spawn_room_lights`). The streamed world now has them
too, reusing the same `RouteInteractable3D.Kind.LIGHT_SWITCH` interactable and its `wall_light_switch.glb`.

## What a room gets

- **Lamps grouped by room.** When a chunk finishes building, every lamp in it is grouped by the room it sits in. That
  covers the ref-look decor lamps (chandeliers, strip lamps, sconces) and the fixture props' lights (ceiling fans,
  ceiling lights, chandelier props), which since the ceiling pass are one family per room.
- **One switch per lit room with a door.** It sits inside, on the wall beside the main doorway, 0.75 m past the
  opening's edge, so it is clear of the frame and of the leaf's swing (KT: "doors collide with light switches"). It goes
  on whichever side of the door the wall carries on, and is skipped when neither side has room. It faces into the room, at
  1.45 m (`StreamedFacilityView3D.SWITCH_HEIGHT`). The world is hunter-scale, and the switch stays well within a
  1.60 m runner's reach (2.15 m). SCALE_FIT has no switch-height ruling yet; this is the value to audit. A lit room
  without a door gets no switch.
- **Some rooms start dark:** about one in four, seeded by room id (`StreamedWorldState.default_room_light`).

## Switching

A switch zeroes its room's lamps' energy in place, and the click plays. The LampField pool lights and
`LightField.exposure_at` read the same lamp arrays, so the rendered light and the mutual light sight (`LIT_SIGHT_SCALE`)
go dark together: a dark room hides you more. In the check, the exposure at a room's lamp went from 0.78 to 0.04.

One gap: the emissive bulb meshes and halo decals stay drawn when a room is switched off. Only the light they cast goes.

## State

- **`StreamedWorldState.room_lights`:** only rooms someone switched are stored. It is in the snapshot, so it covers
  saves, late joiners and a chunk unload and reload, where the state is reapplied as the chunk builds.
- **Parked storeys:** they keep their lamp arrays, so a room switched while parked is right when it revives.
- **Co-op:** host-authoritative, like room doors. A guest's switch sends `stream_room_light` (whitelisted in
  `RemotePlayers`); the host applies it and relays it to every peer.

## Hunters

This runs on the host, at a switch within 1.6 m:
- **Nyxie:** turns lights off.
- **Everyone else:** turns them on while searching or investigating.

A switch rests 15 s after a hunter uses it. Peers hear the click.

## Movie system

The movie system can drive the same switch, `facility.room_light_switch(room_id)`, or set a room's state directly with
`facility.apply_room_light(room_id, on)`.

## Check

The `light_switches` suite covers:
- door clearance: across four seeds (about 2,700 switches), no switch is within a door's frame plus 0.5 m, inside its
  swing on either side of the wall. Wall-mounted props in a door zone are counted too (currently 0);
- lit rooms have switches at a reachable height;
- rooms that start dark have dark lamps;
- flipping a switch changes the lamps, the light field, the switch's own state and the click;
- a save and load (world state snapshot) and a full unload and rebuild of the chunks both keep the room dark;
- a guest's request on the host, and the host's relayed event on a guest, both apply.

Hunter flips are not covered by the suite.

## Fixture placement (KT: "center or even with the room")

Every room's ceiling fixtures follow one rule: an even grid centred on the room's interior bounds (the room rect, not
the cell grid origin).
- **Fixture count:** each axis gets `round(length / spacing)` fixtures, at least one. Spacing is 7 m for chandeliers and
  pendants, 5 m for strip lamps.
- **Position:** each fixture sits at the middle of its equal share of the axis. So one fixture is at the exact centre,
  half a cell off the grid in even-sized rooms, and several form rows along the long axis with equal margins to
  opposite walls. Lit or dark is decided once per room.
- **Source:** `RefDecor.fixture_grid` and `even_positions`.
- **Recipe ceiling fixtures** (fans, ceiling lights, chandelier props) are re-laid by
  `StreamedRouteGenerator.even_ceiling_fixtures`. One goes to the centre; several form a row along the long axis, or two
  rows in a room 12 or more cells deep with 4 or more fixtures. They keep their cell and room and move through
  `placement_offset`. A leftover that would break the grid is dropped.
- **Suites:** a suite's parent room no longer gets its own fixtures over its child rooms.
- **Tall-room roof ribs** run on the lines halfway between pendant rows (at the thirds with one row), so a chain never
  passes through a beam.
- **Sconces:** room sconces are evenly spaced along each wall, at the same positions on opposite walls, so they come in
  symmetric pairs. A doorway that falls on a sconce position leaves that sconce out.
- **Corridors:** corridor lamps stay on the hall centreline at even intervals.

The `ceiling_fixtures` suite checks every room with ceiling fixtures across three seeds (5,735 rooms). Each fixture must
mirror onto another about the room centre within 5 cm, and the spacing along each axis must be even.

Not done: the sewer levels (−1 to −3) and the upper levels use their own lanes' placement. Those lanes have been sent
this rule.
