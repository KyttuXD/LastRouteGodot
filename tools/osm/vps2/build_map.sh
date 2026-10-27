#!/usr/bin/env bash
# Build, sign and push one curated City map on VPS 2 (runs as osmbuild; docs/CITY_OSM_MAPS.md section 2.1).
#   build_map.sh <id> [version]     version defaults to the next free number under /srv/osm/out/<id>/
#   NO_PUSH=1 build_map.sh <id>     build and sign only
# Output /srv/osm/out/<id>/<version>/ is immutable once built; the push lands in VPS 3's incoming drop and is
# only served after city_maps_promote.sh checks it there.
set -euo pipefail
OSM=/srv/osm
HERE="$(cd "$(dirname "$0")" && pwd)"
ID="${1:?map id}"
LINE="$(grep -E "^$ID\|" "$HERE/maps.conf" || true)"
[ -n "$LINE" ] || { echo "unknown map id $ID (see maps.conf)" >&2; exit 2; }
IFS='|' read -r _ NAME CITY STATE REGION EXTRACT AREA TAGS BLURB <<<"$LINE"
SRC="$OSM/extracts/$EXTRACT-latest.osm.pbf"
[ -s "$SRC" ] || { echo "missing extract $SRC" >&2; exit 4; }
if [ -n "${2:-}" ]; then VER="$2"; else
  VER=$(( $(ls "$OSM/out/$ID" 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -1 || echo 0) + 1 ))
fi
OUT="$OSM/out/$ID/$VER"
[ ! -e "$OUT" ] || { echo "$OUT already exists (versions are immutable)" >&2; exit 3; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
EXTRA=(); MAXKM=2.0
case "$AREA" in
  bbox:*) IFS=',' read -r S W N E <<<"${AREA#bbox:}" ;;
  osm:*)
    # the outline: one relation or closed way, exported as a GeoJSON polygon; its bounding box is the map frame
    osmium getid -O -r "$SRC" "${AREA#osm:}" -o "$WORK/outline.osm.pbf"
    osmium export -O -f geojson --geometry-types=polygon "$WORK/outline.osm.pbf" -o "$WORK/outline.geojson"
    read -r S W N E < <(python3 -I -c 'import json,sys
g=json.load(open(sys.argv[1])); pts=[]
def walk(c):
    if isinstance(c[0], (int, float)): pts.append(c)
    else: [walk(x) for x in c]
for f in g["features"]: walk(f["geometry"]["coordinates"])
print(min(p[1] for p in pts), min(p[0] for p in pts), max(p[1] for p in pts), max(p[0] for p in pts))' "$WORK/outline.geojson")
    EXTRA=(--boundary "$WORK/outline.geojson"); MAXKM=6.0 ;;  # the frame of a diagonal outline is larger than its area
  *) echo "bad area $AREA" >&2; exit 2 ;;
esac
META="$(python3 -I -c 'import json,sys; print(json.dumps(dict(zip(["city","state","region","tags","blurb"], [sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].split(","), sys.argv[5]]))))' "$CITY" "$STATE" "$REGION" "$TAGS" "$BLURB")"
# 300 m margin so ways crossing the map edge are complete
M=0.003
osmium extract -b "$(echo "$W - $M" | bc),$(echo "$S - $M" | bc),$(echo "$E + $M" | bc),$(echo "$N + $M" | bc)" \
  --strategy=complete_ways -o "$WORK/clip.osm.pbf" "$SRC"
osmium export --geometry-types=point,linestring,polygon -f geojsonseq -a type,id -o "$WORK/clip.geojsonseq" "$WORK/clip.osm.pbf"
python3 -I "$HERE/osm_city_convert.py" "$WORK/clip.geojsonseq" "$WORK/out" --name "$NAME" --id "$ID" \
  --bbox "$S,$W,$N,$E" --version "$VER" --max-km2 "$MAXKM" --meta "$META" "${EXTRA[@]}"
openssl pkeyutl -sign -rawin -inkey "$OSM/keys/maps.key" -in "$WORK/out/manifest.json" -out "$WORK/out/manifest.sig"
# the Godot client checks an RSA-SHA256 signature (Godot's Crypto has no Ed25519); the server checks the Ed25519 one
openssl dgst -sha256 -sign "$OSM/keys/maps_rsa.key" -out "$WORK/out/manifest.rsa.sig" "$WORK/out/manifest.json"
openssl pkeyutl -verify -rawin -pubin -inkey "$OSM/keys/maps_pub.pem" -in "$WORK/out/manifest.json" -sigfile "$WORK/out/manifest.sig" >/dev/null
mkdir -p "$(dirname "$OUT")"; mv "$WORK/out" "$OUT"; chmod -R a+rX "$OUT"
echo "built $OUT"
if [ -z "${NO_PUSH:-}" ]; then
  rsync -a -e "ssh -i $OSM/keys/push_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes" "$OSM/out/$ID/$VER" "osmpush@194.156.90.219:$ID/"
  echo "pushed $ID/$VER to VPS 3 incoming"
fi
