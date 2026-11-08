# Sourced by the network test scripts. Decides WHERE they run and refuses unsafe targets.
#   REMOTE=1 BACKEND_URL=http://127.0.0.1:8205 tools/build/coop_test.sh
# Allowed targets: loopback, or the test instance in $TEST_URL (default http://127.0.0.1:8205).
# Production (port 8105) is refused unless --i-know-this-is-production is passed to the script.
# Sets: REMOTE (0/1), BACKEND_URL, GODOT_FLAGS (extra godot args), uses ARGS_ACK (0/1).
ARGS_ACK=0
for a in "$@"; do [ "$a" = "--i-know-this-is-production" ] && ARGS_ACK=1; done
GODOT_FLAGS=""
[ "$ARGS_ACK" = 1 ] && GODOT_FLAGS="--i-know-this-is-production"
REMOTE="${REMOTE:-0}"
TEST_URL="${TEST_URL:-http://127.0.0.1:8205}"
PROD_URL="${PROD_URL:-http://127.0.0.1:8105}"
if [ "$REMOTE" = 1 ]; then
  BACKEND_URL="${BACKEND_URL:-$TEST_URL}"
  BACKEND_URL="${BACKEND_URL%/}"
  lc="$(printf '%s' "$BACKEND_URL" | tr 'A-Z' 'a-z')"
  case "$lc" in
    "$PROD_URL"|*:8105)
      if [ "$ARGS_ACK" != 1 ]; then
        echo "################################################################" >&2
        echo "REFUSED: $BACKEND_URL is PRODUCTION (port 8105)." >&2
        echo "These tests create rooms and PUBLIC-route state. Use the test instance:" >&2
        echo "  REMOTE=1 BACKEND_URL=$TEST_URL $0" >&2
        echo "Only if you really mean production: add --i-know-this-is-production" >&2
        echo "################################################################" >&2
        exit 9
      fi
      echo "WARNING: running against PRODUCTION ($BACKEND_URL) because --i-know-this-is-production was given" >&2 ;;
    "$TEST_URL"|http://127.0.0.1:*|http://localhost:*) ;;
    *) echo "REFUSED: $BACKEND_URL is not an allowed target (loopback or $TEST_URL)" >&2; exit 9 ;;
  esac
fi
