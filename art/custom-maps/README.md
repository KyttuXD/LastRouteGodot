# Custom map PNG authoring

Last Route custom maps are literal pixel maps: **one image pixel is one
1-metre game cell**. Paint them in a pixel-art editor with anti-aliasing,
blending, colour profiles, and resampling disabled.

## File rules

- PNG, RGB or RGBA, fully opaque
- Width and height may each be up to **512 cells**, with at most **65,536
  total cells** (for example, 256×256 or 512×128)
- Use only the exact colours below
- Paint zero or more green spawn cells; without one, the seeded generator
  chooses a random open cell
- A red exit cell is recommended; without one, the game chooses a lift cell
- Keep the outermost pixels black so the route has a closed boundary
- Make corridors and doors at least 3 pixels wide for comfortable movement
- Keep walkable space connected so every authored or automatic spawn can
  reach the route objectives
- The downloaded PNG must be no larger than 2 MiB

The 2 MiB rule is a compressed-file transport guard for HTTP and multiplayer;
the decoded limits separately prevent a very small compressed PNG from
expanding into an unsafe GridMap allocation. Very large valid grids still
consume proportionally more RAM, collision data, loading time and network
snapshot time, so test ambitious sizes on the lowest-spec machine you intend
to support.

Do not resize a finished map with smooth/bilinear filtering. If it must be
resized, use nearest-neighbour filtering and inspect the result for changed
colours.

## Palette

| Hex | Meaning |
| --- | --- |
| `#000000` | Wall |
| `#FFFFFF` | Ordinary floor/corridor |
| `#00FF00` | Player spawn (optional; paint multiple for co-op slots) |
| `#FF0000` | Service-lift exit (optional; exactly one recommended) |
| `#4A90D9` | Office floor region |
| `#C97A3D` | Maintenance floor region |
| `#D9B94A` | Arcade floor region |
| `#D94AA0` | Circus floor region |
| `#B94A4A` | Nether floor region |
| `#E8CBA0` | Beach floor region |
| `#8E5FD9` | Mansion floor region |
| `#B07CC6` | Mansion bedroom floor region |
| `#6FBF73` | Garden floor region |

[`last-route-map-palette.gpl`](last-route-map-palette.gpl) can be imported by
GIMP, Krita, Aseprite, and other editors that support GIMP palettes. Region
colours are walkable floor; contiguous pixels of the same region colour form
one themed room. Exact cells are retained for irregular shapes, so an unpainted
hole inside a region's bounding box stays ordinary floor. Regions tint the
floor and populate the matching deterministic prop roster. For example, beach
pixels place Frozen Tideline dressing and nether pixels place Thermal Inferno
dressing. Unrecognised or transparent pixels become walls and produce a
warning.

Green spawn cells are read left-to-right, top-to-bottom. Co-op roster slots
use them in that order; if there are more players than green cells, remaining
players use nearby distinct floor cells. When there are no green cells, the
route seed chooses one random open cell deterministically, so host and guests
still agree on where the route begins.

## Test the included map

[`test-map.png`](test-map.png) is a known-good 49×49 example. The repository is
private, so a raw GitHub URL cannot be used by an unauthenticated game client.
The Node backend safely exposes checked-in PNGs from this directory instead:

```text
http://lastroute.kyttuslab.org:8105/api/custom-maps/test-map.png
```

`art/custom-maps` is the backend's default map directory. An alternate folder
can be selected with `LASTROUTE_CUSTOM_MAP_DIR`; the GitHub PAT stays on the
server and is never sent to a player.

1. Run a **debug** build and enter an offline or co-op route.
2. Press `0` (or numpad `0`) to open the admin menu.
3. Paste the raw PNG URL into **CUSTOM MAP URL** and submit it.
4. Wait for `CUSTOM MAP LOADED // 49x49`.

In co-op, a guest admin may submit the URL, but the host downloads and
installs it. The host then sends the validated PNG to all current players and
late joiners. The custom-map field is intentionally absent from release
builds because it is an admin/debug tool.

The current format places route geometry, spawns, lift, and themed floor
regions. Relays, batteries, safe zones, hiding spots, and themed props are
placed deterministically by the game. The PNG does not yet provide an exact
per-pixel prop marker, so it chooses furniture positions inside each painted
region rather than letting the map author place each chair manually.

Three larger co-op-ready samples are included (each has four green spawns):

- `sample-mansion-showcase.png`
- `sample-frozen-tideline.png`
- `sample-thermal-inferno.png`

After the backend has pulled this repository, load them through the same
endpoint, for example:

```text
http://lastroute.kyttuslab.org:8105/api/custom-maps/sample-frozen-tideline.png
```
