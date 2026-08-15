# Cupcakes Framework (vendored shaders)

Two shaders vendored **verbatim, unmodified** from the Cupcakes Framework, a
Godot framework for FNAF-inspired games:

- **Upstream:** https://github.com/Oplexitie/Cupcakes-Framework
- **Author:** Oplexitie
- **License:** MIT — see `LICENSE` in this folder (© 2023-2026 Oplexitie)
- **Vendored at upstream commit:** `5bc1621`

## What's here, and what it's for

| File | Used for |
| --- | --- |
| `equirectangular_perspective.gdshader` | The curved-panorama office view in Office Mode — the FNAF-style "you're sitting in the room" look, applied over a flat office image. |
| `crtwave_shader.gdshader` | Rolling CRT distortion on the camera monitor feed. |

`equirectangular_perspective.gdshader` carries its own FOV formula in a
comment:

```
FOV = viewport_size * ( 1 / ( 360 / full_latitude_or_longitude ) ) / office_image_size
```

Its latitude and longitude **must match** what the office image was rendered
at in the modelling software, or the perspective won't line up. Worth knowing
when the real office art gets authored (see `art/props-3d/README.md` for this
project's own model conventions).

## Why only the shaders

The rest of the Cupcakes Framework is a starter template (~320 lines total)
whose AI model is classic FNAF: an `ai_level >= randi_range(1, 20)` movement
roll with characters hopping between discrete rooms. LastRoute's Office Mode
works differently — its ten Void signals are progress-meter based with bespoke
per-signal mechanics, only three of them traverse cameras at all, and this port
drives them from a seeded RNG so a night is replay-stable. That simulation is
already ported in full (`src/game/office/office_simulation.gd`), so adopting
the framework's AI would mean replacing a faithful LastRoute port with generic
FNAF behaviour.

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
