# Custom map PNG authoring

Last Route custom maps are literal pixel maps: **one image pixel is one
1-metre game cell**. Paint them in a pixel-art editor with anti-aliasing,
blending, colour profiles, and resampling disabled.

## File rules

- PNG, RGB or RGBA, fully opaque
- Width and height may each be **35 through 121 pixels**
- Use only the exact colours below
- Paint exactly one green start cell
- A red exit cell is recommended; without one, the game chooses a lift cell
- Keep the outermost pixels black so the route has a closed boundary
- Make corridors and doors at least 3 pixels wide for comfortable movement
- Every walkable area should be connected to the green start cell
- The downloaded PNG must be no larger than 2 MiB

Do not resize a finished map with smooth/bilinear filtering. If it must be
resized, use nearest-neighbour filtering and inspect the result for changed
colours.

## Palette

| Hex | Meaning |
| --- | --- |
| `#000000` | Wall |
| `#FFFFFF` | Ordinary floor/corridor |
| `#00FF00` | Player start (required; exactly one recommended) |
| `#FF0000` | Service-lift exit (optional; exactly one recommended) |
| `#4A90D9` | Office floor region |
| `#C97A3D` | Maintenance floor region |
| `#D9B94A` | Arcade floor region |
| `#D94AA0` | Circus floor region |
| `#B94A4A` | Nether floor region |
| `#E8CBA0` | Beach floor region |
| `#8E5FD9` | Mansion floor region |
| `#6FBF73` | Garden floor region |

[`last-route-map-palette.gpl`](last-route-map-palette.gpl) can be imported by
GIMP, Krita, Aseprite, and other editors that support GIMP palettes. Region
colours are walkable floor; contiguous pixels of the same region colour form
one themed room. They currently tint the normal floor material. Unrecognised
or transparent pixels become walls and produce a warning.

## Test the included map

[`test-map.png`](test-map.png) is a known-good 49×49 example. Once it is on
GitHub, its directly downloadable URL is:

```text
https://raw.githubusercontent.com/KyttuXD/LastRouteGodot/main/art/custom-maps/test-map.png
```

1. Run a **debug** build and enter an offline or co-op route.
2. Press `0` (or numpad `0`) to open the admin menu.
3. Paste the raw PNG URL into **CUSTOM MAP URL** and submit it.
4. Wait for `CUSTOM MAP LOADED // 49x49`.

In co-op, a guest admin may submit the URL, but the host downloads and
installs it. The host then sends the validated PNG to all current players and
late joiners. The custom-map field is intentionally absent from release
builds because it is an admin/debug tool.

The current format places the route geometry, start, lift, and themed floor
regions. Relays, batteries, safe zones, hiding spots, and other route items are
placed by the game. Authored props and dialogue-trigger pixels are not
supported yet.
