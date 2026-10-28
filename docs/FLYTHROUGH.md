# Flythrough videos

Short H.264 clips that fly a camera through a named area of Last Route, so you can look at a build without playing it. They come from the
`flythrough` scenario of the [playtest system](PLAYTEST.md): the runner starts a real debug route (nothing is saved), teleports a noclip,
input-frozen player to the area and glides the player's own first-person camera along a smoothed walkable path, then cuts to a slow
overview orbit. Godot's Movie Maker (`--write-movie`, fixed 30 fps, 1280x720) records it; `ffmpeg` trims it to the clip, fades it and encodes it.

## One command

```sh
tools/playtest/flythrough.py                       # the default set of the current HEAD -> captures/videos/<commit>/<area>.mp4
tools/playtest/flythrough.py --commit <rev>        # any commit: its tree is exported with git archive, your checkout is untouched
tools/playtest/flythrough.py --working-tree --areas hospital,sewer_tunnels
tools/playtest/flythrough.py --list                # every area
```

The game runs on **KT-Mini4-2** (windowed, through `Claude-Setup/mini-run.sh`); the Mac only exports the tree, pulls the capture back and
encodes it. Output goes to `captures/videos/<commit>/` (gitignored) with an `index.md` and `index.json`. A clip is 30-40 s and about 3-6 MB.

Useful options: `--seed` (the world seed; the same seed gives the same layout for one build), `--seconds` (clip length), `--hunters show`
(leave the hunters in the shot; default hides them), `--crf` / `--width` (size vs quality), `--keep-avi`, `--timeout`.

## Areas

Districts (level 0): `hospital lab greenhouse mall prison mansion hotel` (plus `maze apartment beach gothic carnival` with `--areas all`).
Each walks about 50 m down the middle of the halls of the nearest chunk of that district, then cuts to an overview orbit over the chunk.
Sewer (level -1): `sewer_tunnels` (the long tunnel with its bridges, then a look back), `sewer_junction` (junction plaza orbit),
`sewer_valve_room`, `sewer_pump_room`, `sewer_overflow` (walk in from the junction, then orbit the room), `sewer_ladder` (walk to a shaft, climb
the ladder to the maze, look round). `inferno` (-3) exists as a preset and is skipped with a note until the build has that district; the -2
collector gets a preset when it lands (add it to `AREAS` in `src/playtest/playtest_flythrough.gd` and to the lists in `flythrough.py`).

## How a clip is made (v2)

* **Planned from the layout.** A district clip opens with a slow high orbit over the chunk (the establishing shot), cuts to a tour that goes down the
  halls, through the real doorways of two or three rooms and out again. Cell paths are smoothed like a player's walk: line-of-sight pruning (a
  0.4 m body must clear the walls), a Catmull-Rom curve, a push-off keeping 0.6 m from walls where the hall allows, walking speed with gentle
  acceleration and slower rounded turns, optional head bob (`--no-bob`).
* **Looks at things.** Room centres, relays, signature props (district) and valve wheels, lamps, pipes, ladders (sewer) are points of interest. The
  camera glances at one when it is within ~9 m, inside a 75 degree cone and in line of sight, with a rate-limited turn (no snapping); it never glances
  toward a wall closer than 3 m.
* **Follows the real floor.** Each walking frame ray-casts the physics collision floor (ramps, bridge slopes, stairs); the flying shots are absolute.
* **Checks itself.** The planner counts seconds facing a wall under 2 m and motion stats (largest yaw step, zig-zag); the runner records the real
  view depth through the collision every frame; `flythrough.py` samples a frame per second and flags blank or flat-wall frames. A clip with more
  than 2 boring seconds, or the view under 2 m for over 1 s, is re-planned with the next `--variants` try (default 3); the best try is kept and
  marked WARN if it still has boring stretches. Each clip gets a `<area>_sheet.jpg` contact sheet.
* **Clean scene (optional).** `--clean` hides pickups, tools, coins and the waypoint trail by visibility only (`--keep relay,battery` whitelists kinds).

## Notes

* The maze is dark on purpose; the flythrough adds a soft lamp on the camera (`--lamp=false` in the runner's own arguments turns it off).
* The camera is the player's own, moved by the script (noclip, so it passes through props), so what you see is what the game renders.
* `scripts/validate_playtest.gd` (suite `playtest`) plans every default area without a scene and checks the track length and that the camera
  never jumps, so a world change that breaks a path shows up as a failing check, not as a bad video.
* Adding an area: a preset in `AREAS`, a branch in `plan()` if it is not a plain district, the name in `flythrough.py`.
