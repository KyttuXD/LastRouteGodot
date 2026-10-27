#!/usr/bin/env bash
# Weekly: refresh the Geofabrik extracts (only when newer) and build + push a new version of every curated map.
set -euo pipefail
OSM=/srv/osm
HERE="$(cd "$(dirname "$0")" && pwd)"
# only the state extracts maps.conf uses are kept and refreshed
for STATE in $(grep -vE '^#|^$' "$HERE/maps.conf" | cut -d'|' -f6 | sort -u); do
  EXTRACT="$STATE-latest.osm.pbf"
  URL="https://download.geofabrik.de/north-america/us/$EXTRACT"
  TMP="$OSM/extracts/.part-$EXTRACT"
  if curl -fsSL -z "$OSM/extracts/$EXTRACT" -o "$TMP" "$URL" && [ -s "$TMP" ]; then
    osmium fileinfo "$TMP" >/dev/null && mv "$TMP" "$OSM/extracts/$EXTRACT" && echo "updated $EXTRACT"
  fi
  rm -f "$TMP"
done
for ID in $(grep -vE '^#|^$' "$HERE/maps.conf" | cut -d'|' -f1); do "$HERE/build_map.sh" "$ID" || echo "FAILED $ID"; done
