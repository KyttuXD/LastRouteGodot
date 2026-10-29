#!/usr/bin/env bash
# Deploy / roll back the Last Route Godot 2 backend as the systemd service `lastroute-godot2`.
#
#   deploy/deploy.sh                    dry run (default): prints what WOULD change, changes nothing
#   deploy/deploy.sh --apply            do it (run as root on the VPS, after KT's approval)
#   deploy/deploy.sh --rollback --apply point `current` at the previous release and restart
#   deploy/deploy.sh --instance test    the separate TEST instance (default instance: production). Own unit
#                                       lastroute-godot2-test, user, env file, state dir, release dir and ports
#                                       TCP 8205 / UDP 1205; never touches the production unit, files or ports.
#   deploy/deploy.sh --instance test --wipe-data --apply   stop the TEST service, empty its state dir, start it
#   options: --src DIR (repo root to ship, default: this checkout)   --no-start (install, do not start)
#            --prefix DIR (staging mode for local tests: everything under DIR, no useradd/chown/systemctl)
#
# Idempotent: re-running ships a new release directory and re-installs identical unit/env files.
# Never touches last-route.service, nginx, the firewall or any other service (firewall: deploy/firewall.sh).
set -euo pipefail

APPLY=0; ROLLBACK=0; START=1; PREFIX=""; SRC=""; INSTANCE=production; WIPE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --rollback) ROLLBACK=1 ;;
    --no-start) START=0 ;;
    --src) SRC="$2"; shift ;;
    --prefix) PREFIX="$2"; shift ;;
    --instance) INSTANCE="$2"; shift ;;
    --wipe-data) WIPE=1 ;;
    -h|--help) sed -n 2,13p "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

case "$INSTANCE" in
  production) SUFFIX=""; SVC_USER=lastroute2; DEF_HTTP=8105; DEF_RELAY=1105 ;;
  test)       SUFFIX="-test"; SVC_USER=lastroute2test; DEF_HTTP=8205; DEF_RELAY=1205 ;;
  *) echo "unknown instance '$INSTANCE' (use production or test)" >&2; exit 2 ;;
esac
SERVICE="lastroute-godot2$SUFFIX"
NAME="lastroute-godot2$SUFFIX"
APP="$PREFIX/opt/$NAME"
ENV_DIR="$PREFIX/etc/$NAME"
ENV_FILE="$ENV_DIR/$NAME.env"
UNIT="$PREFIX/etc/systemd/system/$SERVICE.service"
STATE="$PREFIX/var/lib/$NAME"
if [ "$WIPE" = 1 ] && [ "$INSTANCE" != test ]; then echo "--wipe-data is only allowed for --instance test" >&2; exit 2; fi
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${SRC:-$(cd "$HERE/.." && pwd)}"
KEEP_RELEASES=5
STAGING=0; [ -n "$PREFIX" ] && STAGING=1
CHANGES=()

if [ "$SERVICE" = "last-route" ]; then echo "refusing: that is the website's unit" >&2; exit 3; fi
say() { printf '%s\n' "$*"; }
run() { # run a command, or only print it in dry-run
  if [ "$APPLY" = 1 ]; then "$@"; else say "  WOULD: $*"; fi
}
changed() { CHANGES+=("$*"); }
sysctl_() { if [ "$STAGING" = 1 ]; then say "  (staging) skip: systemctl $*"; else run systemctl "$@"; fi; }

say "== Last Route Godot 2 backend deploy: instance $INSTANCE, service $SERVICE ($([ "$APPLY" = 1 ] && echo APPLY || echo DRY-RUN))${PREFIX:+ [staging: $PREFIX]}"
if [ "$APPLY" = 1 ] && [ "$STAGING" = 0 ] && [ "$(id -u)" != 0 ]; then echo "--apply must run as root" >&2; exit 1; fi

if [ "$APPLY" = 0 ]; then
cat <<PRE
-- Read-only pre-flight for the target host (run these over SSH first; none of them changes anything):
   hostnamectl; df -h /opt /var /etc; free -h
   ss -tulpn | grep -E ':($DEF_HTTP|$DEF_RELAY)\b' || echo "$DEF_HTTP/$DEF_RELAY free"
   command -v node; node --version            # must be a system path (/usr/bin/node), >= 18
   systemctl list-units --type=service --state=running
   systemctl status last-route.service --no-pager | head -5      # look only, never restart it
   id $SVC_USER 2>/dev/null || echo "user $SVC_USER does not exist yet"
   ls /opt/$NAME /etc/$NAME /var/lib/$NAME 2>&1 | head
   ufw status 2>/dev/null; iptables -S 2>/dev/null | head -20
PRE
fi

# ---- read-only pre-checks ----------------------------------------------------------------------
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
  [ "$NODE_MAJOR" -ge 18 ] && say "ok: node $(node --version)" || { echo "node >= 18 required (found $(node --version))" >&2; exit 1; }
else
  echo "node is not installed (need >= 18)" >&2; exit 1
fi
NODE_BIN="$(command -v node)"
case "$NODE_BIN" in
  /home/*|/root/*|/Users/*) [ "$STAGING" = 1 ] || { echo "node is at $NODE_BIN; the hardened unit (ProtectHome) cannot run it. Install a system Node (/usr/bin/node, e.g. NodeSource) first." >&2; exit 1; } ;;
esac
HTTP_PORT=$DEF_HTTP; RELAY_PORT=$DEF_RELAY
if [ -f "$ENV_FILE" ]; then
  HTTP_PORT="$(grep -E '^LASTROUTE_HTTP_PORT=' "$ENV_FILE" | tail -1 | cut -d= -f2 || true)"; HTTP_PORT="${HTTP_PORT:-$DEF_HTTP}"
  RELAY_PORT="$(grep -E '^LASTROUTE_RELAY_PORT=' "$ENV_FILE" | tail -1 | cut -d= -f2 || true)"; RELAY_PORT="${RELAY_PORT:-$DEF_RELAY}"
fi

port_users() { # who listens on proto/port (empty when free)
  command -v ss >/dev/null 2>&1 || return 0
  if [ "$1" = tcp ]; then ss -H -ltnp "sport = :$2" 2>/dev/null; else ss -H -lunp "sport = :$2" 2>/dev/null; fi
}

rollback() {
  [ -L "$APP/current" ] || { echo "no current release to roll back from" >&2; exit 1; }
  local cur prev
  cur="$(basename "$(readlink "$APP/current")")"
  prev="$(ls -1 "$APP/releases" | sort | grep -B1 -x "$cur" | head -1 || true)"
  if [ -z "$prev" ] || [ "$prev" = "$cur" ]; then echo "no earlier release than $cur" >&2; exit 1; fi
  say "rollback: $cur -> $prev"
  run ln -sfn "$APP/releases/$prev" "$APP/current"
  sysctl_ restart "$SERVICE"
  changed "current -> releases/$prev (rolled back from $cur)"
}

if [ "$ROLLBACK" = 1 ]; then
  rollback
  say; say "== ${#CHANGES[@]} change(s):"; printf '  - %s\n' "${CHANGES[@]}"
  exit 0
fi

if [ "$INSTANCE" = test ] && { [ "$HTTP_PORT" = 8105 ] || [ "$RELAY_PORT" = 1105 ]; }; then
  echo "refusing: the test instance must not use the production ports (8105/1105): fix $ENV_FILE" >&2; exit 4
fi
if [ "$WIPE" = 1 ]; then
  say "wipe: stopping $SERVICE and emptying $STATE (test instance data only)"
  sysctl_ stop "$SERVICE"
  [ -d "$STATE" ] && run find "$STATE" -mindepth 1 -delete
  sysctl_ start "$SERVICE"
  say "== test instance data wiped"; exit 0
fi
for spec in "tcp:$HTTP_PORT" "udp:$RELAY_PORT"; do
  proto="${spec%%:*}"; port="${spec##*:}"
  owner="$(port_users "$proto" "$port")"
  if [ -n "$owner" ]; then
    if echo "$owner" | grep -q "lastroute-godot2\|node" && systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
      say "ok: $proto/$port already held by $SERVICE (a restart will replace it)"
    else
      echo "PORT CONFLICT: $proto/$port is in use:" >&2; echo "$owner" >&2
      echo "choose other ports in $ENV_FILE (and the client constant) or stop the other service first. Aborting." >&2
      exit 4
    fi
  else
    say "ok: $proto/$port is free"
  fi
done

# ---- user, directories ------------------------------------------------------------------------
if [ "$STAGING" = 0 ]; then
  if id "$SVC_USER" >/dev/null 2>&1; then say "ok: user $SVC_USER exists"
  else run useradd --system --user-group --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin "$SVC_USER"; changed "created system user $SVC_USER"; fi
fi
for d in "$APP/releases" "$ENV_DIR" "$STATE"; do
  [ -d "$d" ] || { run mkdir -p "$d"; changed "created $d"; }
done
if [ "$STAGING" = 0 ]; then
  run chown root:"$SVC_USER" "$ENV_DIR"; run chmod 0750 "$ENV_DIR"
  run chown "$SVC_USER":"$SVC_USER" "$STATE"; run chmod 0750 "$STATE"
fi

# ---- release copy -----------------------------------------------------------------------------
REV="$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo nogit)"
RELEASE="$(date -u +%Y%m%d-%H%M%S)-$REV"
DEST="$APP/releases/$RELEASE"
say "release: $RELEASE (from $SRC)"
if [ "$APPLY" = 1 ]; then
  mkdir -p "$DEST"
  # the mod index's pack folders come from the game's sources, which the release does not ship (backend/pack_kinds.mjs)
  ( cd "$SRC" && node backend/pack_kinds.mjs --write ) || { echo "could not write backend/pack_kinds.json" >&2; exit 1; }
  ( cd "$SRC" && tar cf - --exclude='.env' --exclude='.data' --exclude='._*' --exclude='.DS_Store' \
      index.js package.json backend deploy docs 2>/dev/null ) | tar xf - -C "$DEST"
  [ -f "$DEST/index.js" ] && [ -f "$DEST/backend/server.mjs" ] || { echo "release copy is incomplete" >&2; rm -rf "$DEST"; exit 1; }
  # Files copied from a laptop can keep private modes (0700): the unprivileged service user could not
  # read index.js (EACCES) and the first start failed. Normalise: root-owned, owner rwX, others rX.
  chmod -R u=rwX,go=rX "$DEST"
  [ "$STAGING" = 1 ] || chown -R root:root "$DEST"
  # the service user must be able to traverse every parent directory too
  chmod u=rwx,go=rx "$APP" "$APP/releases"
else
  say "  WOULD: copy index.js package.json backend/ deploy/ docs/ -> $DEST (no .env, .data, test data)"
fi
changed "new release releases/$RELEASE"
PREV_TARGET=""; [ -L "$APP/current" ] && PREV_TARGET="$(readlink "$APP/current")"

# ---- environment file (created once; never overwritten; secrets generated here) --------------
if [ -f "$ENV_FILE" ]; then
  say "ok: $ENV_FILE exists (left untouched)"
else
  if [ "$APPLY" = 1 ]; then
    cp "$HERE/lastroute-godot2.env.example" "$ENV_FILE"
    secret="$(openssl rand -base64 33 | tr -d '\n=+/' | cut -c1-40)"
    sed -i.bak "s|^LASTROUTE_ADMIN_PASSWORD=.*|LASTROUTE_ADMIN_PASSWORD=$secret|" "$ENV_FILE"
    if [ "$INSTANCE" = test ]; then
      sed -i.bak -e "s|/var/lib/lastroute-godot2|/var/lib/$NAME|g" -e "s|^LASTROUTE_HTTP_PORT=.*|LASTROUTE_HTTP_PORT=$DEF_HTTP|" \
        -e "s|^LASTROUTE_RELAY_PORT=.*|LASTROUTE_RELAY_PORT=$DEF_RELAY|" -e "s|^LASTROUTE_INSTANCE=.*|LASTROUTE_INSTANCE=test|" "$ENV_FILE"
    fi
    rm -f "$ENV_FILE.bak"
    chmod 0640 "$ENV_FILE"; [ "$STAGING" = 1 ] || chown root:"$SVC_USER" "$ENV_FILE"
    say "created $ENV_FILE with a generated LASTROUTE_ADMIN_PASSWORD (read it with: sudo grep ADMIN $ENV_FILE)"
  else
    say "  WOULD: create $ENV_FILE from deploy/lastroute-godot2.env.example with a generated LASTROUTE_ADMIN_PASSWORD (openssl rand), mode 0640 root:$SVC_USER"
  fi
  changed "created $ENV_FILE"
fi

# ---- unit -------------------------------------------------------------------------------------
UNIT_SRC="$HERE/lastroute-godot2.service"
UNIT_TMP="$(mktemp)"; trap 'rm -f "$UNIT_TMP"' EXIT
sed -e "s|lastroute-godot2|$NAME|g" -e "s|=lastroute2\$|=$SVC_USER|" \
    -e "s|^Description=.*|Description=Last Route Godot 2 backend ($INSTANCE instance: HTTP room directory + UDP relay + PUBLIC route)|" \
    -e "s|^ExecStart=.*|ExecStart=$NODE_BIN /opt/$NAME/current/index.js|" "$UNIT_SRC" > "$UNIT_TMP"
if [ -f "$UNIT" ] && cmp -s "$UNIT_TMP" "$UNIT"; then say "ok: unit unchanged"
else [ "$STAGING" = 1 ] && [ "$APPLY" = 1 ] && mkdir -p "$(dirname "$UNIT")"; run install -m 0644 "$UNIT_TMP" "$UNIT"; changed "installed $UNIT (node at $NODE_BIN)"; fi

# ---- switch the release, (re)start, smoke ----------------------------------------------------
run ln -sfn "$DEST" "$APP/current"; changed "current -> releases/$RELEASE"
sysctl_ daemon-reload
sysctl_ enable "$SERVICE"
if [ "$START" = 1 ]; then
  sysctl_ restart "$SERVICE"
  if [ "$APPLY" = 1 ] && [ "$STAGING" = 0 ]; then
    ok=0
    for i in $(seq 1 20); do
      if curl -fsS "http://127.0.0.1:$HTTP_PORT/api/health" >/dev/null 2>&1; then ok=1; break; fi; sleep 1
    done
    if [ "$ok" = 1 ] && node "$DEST/deploy/smoke.mjs" "http://127.0.0.1:$HTTP_PORT" --instance "$INSTANCE"; then
      changed "service started; smoke test passed"
    else
      echo "SMOKE FAILED: rolling back" >&2
      journalctl -u "$SERVICE" -n 30 --no-pager >&2 || true
      if journalctl -u "$SERVICE" -n 60 --no-pager 2>/dev/null | grep -qE 'EACCES|Permission denied'; then
        echo "HINT: permission error. The service user $SVC_USER must be able to read $DEST (try: chmod -R u=rwX,go=rX $DEST; ls -ld $APP $APP/releases)." >&2
      fi
      if [ -n "$PREV_TARGET" ]; then ln -sfn "$PREV_TARGET" "$APP/current"; systemctl restart "$SERVICE" || true; echo "rolled back to $PREV_TARGET" >&2
      else systemctl stop "$SERVICE" || true; echo "no previous release; service stopped" >&2; fi
      exit 5
    fi
  else
    say "  WOULD: wait for http://127.0.0.1:$HTTP_PORT/api/health, then node deploy/smoke.mjs (auto-rollback on failure)"
  fi
else
  say "skip: --no-start"
fi

# ---- prune ------------------------------------------------------------------------------------
if [ "$APPLY" = 1 ] && [ -d "$APP/releases" ]; then
  ls -1 "$APP/releases" | sort | awk -v keep="$KEEP_RELEASES" '{a[NR]=$0} END{for(i=1;i<=NR-keep;i++) print a[i]}' | while read -r old; do
    [ "$old" = "$RELEASE" ] || { rm -rf "$APP/releases/$old"; say "pruned release $old"; }
  done
fi

say; say "== $([ "$APPLY" = 1 ] && echo "${#CHANGES[@]} change(s) made" || echo "dry run: ${#CHANGES[@]} change(s) would be made"):"
printf '  - %s\n' "${CHANGES[@]}"
say "Not touched: last-route.service, the website, the Discord bot, nginx, firewall$([ "$INSTANCE" = test ] && echo ", the production instance" || echo ", the test instance")."
[ "$APPLY" = 1 ] || say "Re-run with --apply (as root, after KT's approval) to perform them."
