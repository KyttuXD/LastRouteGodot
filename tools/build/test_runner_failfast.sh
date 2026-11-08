#!/bin/bash
# Self-test for tests/validate_runner.gd: a suite that does not compile must make the run exit NON-ZERO quickly (it used
# to hang until the machine watchdog). Usage (from the project root, Godot on PATH or GODOT_BIN set):
#   tools/build/test_runner_failfast.sh
set -u
GODOT="${GODOT_BIN:-godot}"
start=$(date +%s)
"$GODOT" --headless --path . res://tests/scenes/validate.tscn -- res://tests/fixtures/broken_suite.gd > /tmp/runner_failfast.log 2>&1
code=$?
elapsed=$(( $(date +%s) - start ))
if [ "$code" -ne 0 ] && [ "$elapsed" -lt 60 ] && grep -q "did not compile" /tmp/runner_failfast.log; then
  echo "runner fail-fast OK (exit $code in ${elapsed}s)"
  exit 0
fi
echo "runner fail-fast FAILED (exit $code in ${elapsed}s)"; tail -20 /tmp/runner_failfast.log
exit 1
