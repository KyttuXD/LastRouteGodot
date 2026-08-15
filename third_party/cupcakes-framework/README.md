# Cupcakes Framework (vendored shaders + derived scripts)

Shaders vendored **verbatim, unmodified** from the Cupcakes Framework, a
Godot framework for FNAF-inspired games. Several of this project's Office
Mode scripts are also **derived** from its presentation code — see "Derived
work" below.

- **Upstream:** https://github.com/Oplexitie/Cupcakes-Framework
- **Author:** Oplexitie
- **License:** MIT — see `LICENSE` in this folder (© 2023-2026 Oplexitie)
- **Vendored at upstream commit:** `5bc1621`

## What's here, and what it's for

| File | Used for | Wired up? |
| --- | --- | --- |
| `crtwave_shader.gdshader` | Rolling CRT distortion on the camera monitor feed. | **Yes** — `scenes/office.tscn`, on the feed body. |
| `equirectangular_perspective.gdshader` | The curved-panorama office view — the FNAF-style "you're sitting in the room" look, applied over a flat office image. | Not yet. It distorts a rendered office *image*; the office is currently placeholder `ColorRect`s, so applying it would warp flat blocks to no benefit. Apply it once real office art exists — and pick up `button_scroll.gd` at the same time (see below). |

`equirectangular_perspective.gdshader` carries its own FOV formula in a
comment:

```
FOV = viewport_size * ( 1 / ( 360 / full_latitude_or_longitude ) ) / office_image_size
```

Its latitude and longitude **must match** what the office image was rendered
at in the modelling software, or the perspective won't line up. Worth knowing
when the real office art gets authored (see `art/props-3d/README.md` for this
project's own model conventions).

## Derived work

These project files are **adapted from** the framework's presentation
scripts rather than copied — each carries a header noting what it came from
and what changed:

| This project | Derived from |
| --- | --- |
| `src/ui/office/office_view.gd` | `Scripts/Nights/Office/office_scrolling.gd` — same accumulate-then-lerp mouse-edge panning and the same three tuning knobs. Changed: drives a `Control` instead of a `Sprite2D`, and reads the viewport rect rather than `content_scale_size` off a `Viewport`-typed variable (which only worked because the root viewport happens to be a `Window`). |
| `src/ui/office/camera_monitor.gd` | `Scripts/Nights/Camera/camera.gd` + `Scripts/Nights/tablet_manager.gd` — index-synced feed/button arrays, a switch that refuses to re-select the live feed, static fired on switch and on raise, and lowering the tablet re-enabling office panning. Changed: feed contents come from `OfficeSimulation` instead of a per-room occupancy array written by the framework's own AI, and static is a timed overlay rather than an `AnimationTree` one-shot (no animation assets yet). |

Not adopted yet, but worth revisiting when real office art exists:
`button_scroll.gd`, which offsets button hitboxes to compensate for the
equirectangular shader's visual distortion. That's a real gotcha — under
that shader, where a control *looks* is not where it *is* — but it only
matters once the shader is actually applied to a real office image (see
below).

## Why the AI isn't used

The framework's AI is classic FNAF: an `ai_level >= randi_range(1, 20)`
movement roll with characters hopping between discrete rooms via a
`match step:` route. LastRoute's Office Mode works differently — its ten
Void signals are progress-meter based with bespoke per-signal mechanics
(a desk-light flash edge, monitor-open acceleration, system sabotage, a
shuffled parkour challenge, camera corruption), only three of them traverse
cameras at all, and this port drives them from a **seeded** RNG so a night is
replay-stable (the framework calls `randomize()`, which would break that).
That simulation is already ported in full in
`src/game/office/office_simulation.gd`, so adopting the framework's AI would
mean replacing a faithful LastRoute port with generic FNAF behaviour.

The framework targets Godot 4.6 and uses the `@abstract` annotation (Godot
4.5+), which is *not* a barrier on this project's Godot 4.7 — the reasons
above are architectural, not version-related. (It would have been a hard
blocker back when this project targeted 4.3, which rejected `@abstract`
outright; that's no longer relevant.) The two shaders here use plain Godot 4
`canvas_item` syntax and load on both.

## Updating

These are vendored copies, not a submodule. To pull upstream changes, re-copy
the files from the repository above and update the commit hash in this file.
Keep them unmodified so provenance stays unambiguous.
