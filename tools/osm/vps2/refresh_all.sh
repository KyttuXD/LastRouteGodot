#!/usr/bin/env bash
# Weekly: refresh the Geofabrik extracts (only when newer) and build + push a new version of every curated map.
set -euo pipefail
OSM=/srv/osm
HERE="$(cd "$(dirname "$0")" && pwd)"
for EXTRACT in $(grep -vE '^#|^$' "$HERE/maps.conf" | cut -d'|' -f3 | sort -u); do
  case "$EXTRACT" in new-york-*) URL=https://download.geofabrik.de/north-america/us/new-york-latest.osm.pbf ;;
    florida-*) URL=https://download.geofabrik.de/north-america/us/florida-latest.osm.pbf ;;
    *) echo "no download url for $EXTRACT" >&2; continue ;; esac
  TMP="$OSM/extracts/.$EXTRACT.part"
  if curl -fsSL -z "$OSM/extracts/$EXTRACT" -o "$TMP" "$URL" && [ -s "$TMP" ]; then
    osmium fileinfo "$TMP" >/dev/null && mv "$TMP" "$OSM/extracts/$EXTRACT" && echo "updated $EXTRACT"
  fi
  rm -f "$TMP"
done
for ID in $(grep -vE '^#|^$' "$HERE/maps.conf" | cut -d'|' -f1); do "$HERE/build_map.sh" "$ID"; done
