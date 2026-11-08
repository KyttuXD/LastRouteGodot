# Hunter rig add-ons

New parts and bones for the blocky hunters (a tail, ears, a hat, a held lantern) come from DATA, mounted when a hunter model is instanced. No hunter
`.glb` or `.bbmodel` is ever edited, and deleting a line in the data removes the add-on again.

- Data: `assets/hunters_blocky/addons/addons.json` (+ small part scenes next to it, e.g. `lantern.tscn`).
- Code: `HunterAddons` (`game/hunters/view/hunter_addons.gd`), `HunterAddonTicker` (`game/hunters/view/hunter_addon_ticker.gd`), hooks in `ModelSlot.instantiate_hunter`
  and `NightWatchPoses`.
- Check: suite `hunter_addons` (`tests/validate_hunter_addons.gd`).

The hunters' rig is a tree of Node3D bones (`Pelvis`, `Belly`, `Chest`, `Head`, `L-Arm` ..., plus the `L-/R-HandProp` empties), not a Skeleton3D. So an add-on
"attachment" is a child node of the bone (it follows every clip), and a "runtime bone" is a new Node3D under an existing or earlier-declared bone, created at
load before the parts are mounted. Everything is rigid and cube-style, no skinning.

## Where it happens

`ModelSlot.instantiate_hunter(identity)` mounts the add-ons for `identity["id"]` right after the model is instanced, so every consumer gets them: the 3D route and
City hunters (`HunterView3D`), Night Watch (all modes), the menus and previews, the jump-scare. Data only, so every co-op peer builds the same thing (the
JSON ships with the build). The plan per hunter id, the meshes and the materials are built once and cached; each model instance only creates its nodes.

## Data format

All vectors are `[x, y, z]`, rotations are euler degrees, the rig faces -Z (the hunter's back is +Z, +X is her right).

```json
{
  "shared":  [],                                   // kits worn by EVERY hunter
  "hunters": { "dovelle": ["test_tail"], "aki": ["test_lantern"] },   // hunter id -> kits
  "kits": {
    "test_tail": {
      "bones":   [ { "name": "TestTail1", "parent": "Pelvis", "position": [0,-0.02,0.14], "rotation": [28,0,0], "scale": [1,1,1] },
                   { "name": "TestTail2", "parent": "TestTail1", "position": [0,0,0.13], "rotation": [10,0,0] } ],
      "parts":   [ { "id": "test_tail_1", "bone": "TestTail1", "shape": { "box": [0.067,0.067,0.15], "color": "#b98ad0" },
                     "position": [0,0,0.065], "rotation": [0,0,0], "scale": [1,1,1], "tint": "#ffffff", "hunters": "any" } ],
      "motions": [ { "id": "sway_1", "bone": "TestTail1", "rot": [3,13,0], "rate": 0.55, "phase": 0.14, "speed_gain": 0.22,
                     "mode_scale": { "idle": 0.5, "walk": 1.2, "chase": 1.6, "sprint": 2.0, "emote": 0.8, "pose": 0.6 } } ],
      "poses":   { "test_tail_flick": { "length": 1.3, "loop": false, "blend": 0.15, "tracks": { "TestTail1": { "rot": [[0,0,0,0],[0.25,8,32,0],[1.3,0,0,0]] } } } }
    }
  }
}
```

- **bones**: new runtime bones. `parent` is an existing bone name or a bone declared earlier. A name that already exists on the model, or a missing parent, is an error (reported
  in `rig.errors`, nothing crashes). Prefer a prefix that cannot clash (`Tail1` may already exist on a hunter with a tail accessory).
- **parts**: a rigid visual. `shape.box` makes a cube (shared mesh + matte material), or `scene` instances a small scene/.glb. `bone` is any existing or declared bone
  (`R-HandProp` / `L-HandProp` are the palm empties for held props). `tint` multiplies the colour. `hunters` (`"any"` or a list) filters a kit's part further.
- **motions**: an additive secondary motion on a bone (existing or runtime): `rot` is the amplitude in degrees per axis, `rate` the Hz, `phase` the offset (0..1), `speed_gain`
  speeds it up with the hunter's ground speed, `mode_scale` how strong it is per mode (`idle`, `walk`, `chase`, `sprint`, `flight`, `stun`, `emote`, `pose`; a mode not listed is 0).
  The motion is applied on top of whatever the clip or pose left on the bone, so it layers over walk, idle, emotes and Night Watch poses.
- **poses**: per-bone rotation keys (the same format as `night_watch_poses.json`: `[time, x, y, z]` degrees, deltas from the bone's rest) for the kit's runtime bones. They become clips
  `nw/<pose_id>` on the hunters that wear the kit only, so `NightWatchPoses.play(view, "test_tail_flick")` works exactly like a core pose (and does nothing for others).
  `NightWatchPoses` poses may also key runtime bones directly: a track whose bone is not in the core list is looked up on the mounted model.

## API

```gdscript
HunterAddons.mount(model, hunter_id)            # done by ModelSlot.instantiate_hunter; returns the Rig (errors, bones, parts) or null
HunterAddons.rig_of(model)                      # the Rig of a mounted model
rig.tick(delta, mode, speed)                    # secondary motion; the model's own HunterAddonTicker does it every frame unless rig.external_tick is set
HunterAddons.is_addon(node)                     # true for add-on nodes (the bounds helpers use this)
HunterAddons.plan(hunter_id)                    # {kits, bones, parts, motions, poses} for a hunter
HunterAddons.enabled = false                    # build models exactly as the .glb ships (tests)
HunterAddons.reset(replacement_data)            # swap the data in tests
```

## Rules it keeps

- Visual only: no collider or collision object is ever created. The hunter's capsule, the hitboxes and the face / hiding logic do not see add-ons, and
  `ModelSlot.combined_local_bounds` (the hiding-props camera fit) and the interaction-bounds helper skip nodes tagged `hunter_addon`.
- Fades (ghosted hunters, the crouch silhouette) reach the add-ons because they are normal meshes under the model.
- The creature rig (spiders) is not a blocky rig; add-ons are ignored there.
- A removed entry leaves the model node-for-node identical to the shipped `.glb` (checked by the suite).

## Nothing ships yet: the test fixture

The shipped `addons.json` assigns no add-on to any hunter (no live hunter wears a tail or a lantern; the suite checks this). The proof of concept is a test-only fixture,
`tests/fixtures/addons/hunter_addons_fixture.json` (+ `lantern.tscn`), which `hunter_addons` swaps in with `HunterAddons.reset(fixture)`: `test_tail` is a four-segment tail
(runtime bones off `Pelvis`, cube parts, a sway that grows with speed and a `test_tail_flick` bone pose) on Dovelle, and `test_lantern` a cube lantern on Aki's right hand that swings as she
walks. To use the system for real, add a kit to the shipped `addons.json` and list its hunters (the fixture is a worked example of every field). `docs/images/addons_back.png` and
`docs/images/addons_side.png` were captured with the fixture assigned.
