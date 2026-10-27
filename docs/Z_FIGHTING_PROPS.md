# Z-fighting inside prop models

KT's report: the gothic canopy bed flickered on the mattress, coverlet, pillows and where the frame meets the mattress. The cause was
inside the models. A blocky prop is one mesh made of boxes, and on the 6 cm voxel grid many boxes ended on the same plane as a neighbour
facing the same way: coverlet and mattress sides, the two headboard parts, canopy bar and brass caps, slats on cabinet fronts, couch
arms and backs. The route-level `coplanar` suite could not see this because it skips parts of the same prop.

## Fix (model level)
`tools/props/build_blocky_props.py` `resolve_coplanar()` runs on every model the builder makes (doors and the relay barrel too). When two
same-facing faces of different boxes share a plane (within 3.5 mm) and overlap, the earlier box's face is set back 6 mm behind the later
box's face. The later box is the detail laid on the base: a coverlet on a mattress, a slat on a cabinet. Repeated passes handle stacks
of three layers. Boxes turned about one axis still take part on that axis (backrests, rockers, couch back cushions). Faces only ever
move inward, so no prop grew and the derived collider table (`prop_collider_sizes.gd`) is unchanged. The gothic door leaves are 6 cm
shorter so their top no longer meets the gothic chamfer blocks. Before this pass 373 of 619 models had such faces; now 0.

## Checks
- `prop_coplanar` suite: every triangle of every blocky model, same-facing coplanar overlaps of 5 cm2 or more fail (ratchet 0).
- `tools/look/bed_zfight.tscn` (windowed, on the mini): the game camera (near 0.06, far 160, gl_compatibility) at 0.5, 2, 6 and 15 m
  from two angles. Each view is rendered three times with the camera nudged 3 mm, and the bed pixels are compared (mean channel
  difference x100). Close up, part of the difference is real parallax from the nudge.

Depth precision: gl_compatibility uses a 24-bit depth buffer. With near 0.06 one depth step is about z²/1,000,000 m: 0.2 mm at 15 m,
2.5 mm at 50 m. So a 6 mm separation holds well beyond room distances.

Sheet: `docs/bed_zfight_before_after.png` (gothic double bed; top row before, bottom row after; foot 0.5/2/6 m, then side 0.5/2/6 m).

| bed | angle | distance | before | after |
|---|---|---|---|---|
| gothicDoubleBed_0 | foot | 0.5 m | 4.352 | 3.885 |
| gothicDoubleBed_0 | foot | 2.0 m | 12.568 | 1.359 |
| gothicDoubleBed_0 | foot | 6.0 m | 2.886 | 0.123 |
| gothicDoubleBed_0 | foot | 15.0 m | 0.192 | 0.009 |
| gothicDoubleBed_0 | side | 0.5 m | 10.394 | 3.704 |
| gothicDoubleBed_0 | side | 2.0 m | 1.311 | 1.254 |
| gothicDoubleBed_0 | side | 6.0 m | 0.671 | 0.123 |
| gothicDoubleBed_0 | side | 15.0 m | 0.134 | 0.013 |
| singleBed_0 | foot | 0.5 m | 1.579 | 1.579 |
| singleBed_0 | foot | 2.0 m | 0.469 | 0.469 |
| singleBed_0 | foot | 6.0 m | 0.081 | 0.058 |
| singleBed_0 | foot | 15.0 m | 0.031 | 0.004 |
| singleBed_0 | side | 0.5 m | 1.176 | 1.176 |
| singleBed_0 | side | 2.0 m | 4.996 | 0.658 |
| singleBed_0 | side | 6.0 m | 0.726 | 0.041 |
| singleBed_0 | side | 15.0 m | 0.118 | 0.013 |
| doubleBed_9 | foot | 0.5 m | 3.402 | 3.315 |
| doubleBed_9 | foot | 2.0 m | 0.966 | 1.242 |
| doubleBed_9 | foot | 6.0 m | 0.877 | 0.138 |
| doubleBed_9 | foot | 15.0 m | 0.039 | 0.008 |
| doubleBed_9 | side | 0.5 m | 1.971 | 1.962 |
| doubleBed_9 | side | 2.0 m | 1.201 | 1.185 |
| doubleBed_9 | side | 6.0 m | 0.520 | 0.102 |
| doubleBed_9 | side | 15.0 m | 0.097 | 0.031 |
| bunkBed_0 | foot | 0.5 m | 2.317 | 1.920 |
| bunkBed_0 | foot | 2.0 m | 2.386 | 1.115 |
| bunkBed_0 | foot | 6.0 m | 0.147 | 0.045 |
| bunkBed_0 | foot | 15.0 m | 0.009 | 0.006 |
| bunkBed_0 | side | 0.5 m | 4.234 | 1.473 |
| bunkBed_0 | side | 2.0 m | 1.428 | 1.097 |
| bunkBed_0 | side | 6.0 m | 0.117 | 0.073 |
| bunkBed_0 | side | 15.0 m | 0.024 | 0.022 |
