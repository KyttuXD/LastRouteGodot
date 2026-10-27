#!/usr/bin/env bash
# Promote a pushed City map version on VPS 3 from the incoming drop into an instance's live map dir
# (docs/CITY_OSM_MAPS.md). Checks the Ed25519 manifest signature and every file's sha256 first.
#   sudo deploy/city_maps_promote.sh --instance test <id> <version>      dry run (default)
#   sudo deploy/city_maps_promote.sh --instance test <id> <version> --apply
#   sudo deploy/city_maps_promote.sh --instance test --unlist <id> --apply   drop a map from index.json (files kept)
set -euo pipefail
INSTANCE=production; APPLY=0; UNLIST=""; ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) INSTANCE="$2"; shift ;;
    --apply) APPLY=1 ;;
    --unlist) UNLIST="$2"; shift ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done
case "$INSTANCE" in production) NAME=lastroute-godot2; SVC_USER=lastroute2 ;; test) NAME=lastroute-godot2-test; SVC_USER=lastroute2test ;;
  *) echo "unknown instance $INSTANCE" >&2; exit 2 ;; esac
INCOMING=/srv/city-maps-incoming
MAPS="/var/lib/$NAME/city-maps"
LIVE="$MAPS/live"
index_edit() { # $1 = id, $2 = version or "" to remove
  node -e '
    const fs = require("fs"); const [path, id, version] = process.argv.slice(1);
    const index = fs.existsSync(path) ? JSON.parse(fs.readFileSync(path, "utf8")) : { maps: [] };
    index.maps = (index.maps || []).filter((m) => m.id !== id);
    if (version) index.maps.push({ id, version: Number(version) });
    index.maps.sort((a, b) => a.id.localeCompare(b.id));
    fs.writeFileSync(path + ".part", JSON.stringify(index, null, 1) + "\n"); fs.renameSync(path + ".part", path);
    console.log(JSON.stringify(index));' "$LIVE/index.json" "$1" "${2:-}"
}
if [ -n "$UNLIST" ]; then
  if [ "$APPLY" = 1 ]; then index_edit "$UNLIST"; else echo "WOULD: remove $UNLIST from $LIVE/index.json"; fi
  exit 0
fi
ID="${ARGS[0]:?map id}"; VER="${ARGS[1]:?version}"
[[ "$ID" =~ ^[a-z0-9][a-z0-9-]{0,63}$ && "$VER" =~ ^[0-9]{1,6}$ ]] || { echo "bad id/version" >&2; exit 2; }
SRC="$INCOMING/$ID/$VER"
[ -f "$SRC/manifest.json" ] && [ -f "$SRC/manifest.sig" ] || { echo "no pushed map at $SRC" >&2; exit 3; }
openssl pkeyutl -verify -rawin -pubin -inkey "$MAPS/maps_pub.pem" -in "$SRC/manifest.json" -sigfile "$SRC/manifest.sig" >/dev/null \
  || { echo "signature check FAILED for $SRC" >&2; exit 4; }
node -e '
  const fs = require("fs"), crypto = require("crypto"); const [dir, id, ver] = process.argv.slice(1);
  const m = JSON.parse(fs.readFileSync(dir + "/manifest.json", "utf8"));
  if (m.format !== "LRCM1" || m.id !== id || m.version !== Number(ver)) throw new Error("manifest id/version mismatch");
  for (const [f, sha] of Object.entries(m.files)) {
    if (crypto.createHash("sha256").update(fs.readFileSync(dir + "/" + f)).digest("hex") !== sha) throw new Error(f + " sha256 mismatch");
  }
  console.log("ok: " + m.name + " v" + m.version + ", " + Object.keys(m.files).length + " files, " + JSON.stringify(m.stats));' "$SRC" "$ID" "$VER"
DEST="$LIVE/$ID/$VER"
if [ "$APPLY" = 0 ]; then echo "WOULD: copy $SRC -> $DEST (root:$SVC_USER, read-only) and list $ID v$VER in $LIVE/index.json"; exit 0; fi
[ -e "$DEST" ] && { echo "$DEST already live (versions are immutable)"; } || {
  mkdir -p "$LIVE/$ID"; cp -r "$SRC" "$DEST.part"; mv "$DEST.part" "$DEST"
}
chown -R root:"$SVC_USER" "$LIVE"; chmod -R u=rwX,g=rX,o= "$LIVE"
index_edit "$ID" "$VER"
chown root:"$SVC_USER" "$LIVE/index.json"; chmod 0640 "$LIVE/index.json"
echo "promoted $ID v$VER for $INSTANCE (the backend re-reads index.json within 10 s)"
