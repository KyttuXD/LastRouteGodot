#!/bin/bash
# Live co-op bot test across machines (coop_bot --coop-check): one host, N guests, each windowed on its own Mac, through the TEST
# instance's relay (the real co-op path: no LAN, so macOS Local Network privacy never matters). The tree must already be synced and
# imported in ~/Developer/lanes/<lane> on every machine. The room code is carried from the host to the guests over SSH.
#
#   tools/playtest/coop_airs.sh <lane> <out-dir> <minutes> <host> <guest> [<guest> ...]
#   a guest written machine@otherlane runs plain coop_bot from that lane (a stock build joining, no --coop-check)
#   ROOM_CODE=KTAMB gives the host a fixed code (5 of A-H J-N P-Z 2-9)
#   PROD=1 uses the live service (KT's call: private rooms only, joined by code); EXTRA="..." adds runner arguments
# Pulls every peer's report, coop_samples.jsonl and screenshots into <out-dir>/<machine>/; compare with tools/playtest/coop_compare.py.
set -u
LANE="$1"; OUT="$2"; MIN="$3"; HOSTM="$4"; shift 4; GUESTS=("$@")
BACKEND_ARG="--backend=http://lastroute.kyttuslab.org:8205"
[ "${PROD:-0}" = 1 ] && BACKEND_ARG="--i-know-this-is-production"
EXTRA="${EXTRA:-}"
SEED="${SEED:-COOPCHECK}"
# macOS app or the Linux binary; Linux opens its window on the logged-in Wayland session
G='$( [ -x ~/Applications/Godot.app/Contents/MacOS/Godot ] && echo ~/Applications/Godot.app/Contents/MacOS/Godot || echo ~/Applications/godot/Godot_v4.7.2-stable_linux.x86_64 )'
ENVL='[ "$(uname)" = Linux ] && { export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0; DD="--display-driver wayland"; } || DD="";'
DIR="Developer/lanes/$LANE"
mkdir -p "$OUT"
TIMEOUT=$(( MIN * 60 + 600 ))
run() {  # machine[@lane] role botseed
  local m="${1%@*}" lane="$LANE" role="$2" seed="$3" check="--coop-check $EXTRA"
  case "$1" in *@*) lane="${1#*@}"; check="" ;; esac
  local dir="Developer/lanes/$lane"
  ssh -o BatchMode=yes "$m" "$ENVL cd ~/$dir && rm -rf .share .playtest/coop_$role$seed && mkdir -p .share && GUARD_STALL=0 ~/.local/bin/guard.pl $TIMEOUT $G \$DD --path . --resolution 1280x720 res://scenes/playtest_runner.tscn -- --playtest-runner --game=last_route --scenario=coop_bot $check --role=$role --bot-seed=$seed --seed=$SEED --minutes=$MIN --dir=\$HOME/$dir/.share --guests=${#GUESTS[@]} $BACKEND_ARG --name=coop_$role$seed > .playtest-coop-$role$seed.log 2>&1; echo \"$m rc=\$?\"" 2>&1 | grep -v zshenv
}
[ -n "${ROOM_CODE:-}" ] && EXTRA="$EXTRA --room-code=$ROOM_CODE"
run "$HOSTM" host 0 &
PIDS=($!)
sleep 4
i=1
for g in "${GUESTS[@]}"; do run "$g" guest $i & PIDS+=($!); i=$((i + 1)); done
# carry the room code
code=""
for _ in $(seq 1 120); do
  code=$(ssh -o BatchMode=yes "$HOSTM" "cat ~/$DIR/.share/code.txt 2>/dev/null" 2>/dev/null | tr -d '[:space:]')
  [ -n "$code" ] && break
  sleep 2
done
echo "room code: ${code:-NONE}"
for g in "${GUESTS[@]}"; do gl="$LANE"; case "$g" in *@*) gl="${g#*@}" ;; esac
  ssh -o BatchMode=yes "${g%@*}" "mkdir -p ~/Developer/lanes/$gl/.share && printf %s '$code' > ~/Developer/lanes/$gl/.share/code.txt" 2>&1 | grep -v zshenv; done
for p in "${PIDS[@]}"; do wait "$p"; done
i=1
pull() { local m="${1%@*}" d="$DIR"; case "$1" in *@*) d="Developer/lanes/${1#*@}" ;; esac
  mkdir -p "$OUT/$m"; rsync -a "$m:$d/.playtest/$2/" "$OUT/$m/" 2>/dev/null; rsync -a "$m:$d/.playtest-coop-$3.log" "$OUT/$m/" 2>/dev/null; }
# CrashWatch markers (TOOLS, src/autoload/crash_watch.gd) from each machine's user://: pulled into <out>/<machine>/crash/, then
# cleared so the next run starts clean (shell only: the Airs have no python)
crash() { local m="${1%@*}" dir="$OUT/${1%@*}/crash"
  mkdir -p "$dir"
  # bash, not the login shell: zsh on the Macs aborts the whole line when a glob matches nothing
  ssh -o BatchMode=yes "$m" 'bash -s' 2>/dev/null <<'REMOTE' | tar xf - -C "$dir" 2>/dev/null
U="$HOME/Library/Application Support/Godot/app_userdata/KYTTU- The Last Route"
[ -d "$U" ] || U="$HOME/.local/share/godot/app_userdata/KYTTU- The Last Route"
cd "$U" 2>/dev/null || exit 0
shopt -s nullglob
F=(logs/crashwatch_session.json logs/crashwatch_freeze.json crash_queue/*.json)
E=(); for f in "${F[@]}"; do [ -f "$f" ] && E+=("$f"); done
[ ${#E[@]} -gt 0 ] || exit 0
tar cf - "${E[@]}" && rm -f "${E[@]}"
REMOTE
  find "$dir" -mindepth 2 -type f -exec mv {} "$dir/" \; 2>/dev/null; find "$dir" -mindepth 1 -type d -empty -delete 2>/dev/null
  rmdir "$dir" 2>/dev/null; true; }
for m in "$HOSTM" "${GUESTS[@]}"; do crash "$m"; done
pull "$HOSTM" coop_host0 host0
for g in "${GUESTS[@]}"; do pull "$g" "coop_guest$i" "guest$i"; i=$((i + 1)); done
for m in "$HOSTM" "${GUESTS[@]}"; do m="${m%@*}"; echo "== $m: $(grep -a 'PLAYTEST \(PASS\|FAIL\)' "$OUT/$m"/.playtest-coop-*.log 2>/dev/null | tail -1 | cut -c1-200)"; done
