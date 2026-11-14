#!/usr/bin/env bash
#
# reuse-graph.sh — the part of lab 3 that cannot be graded one file at a time.
#
#   ./tests/reuse-graph.sh
#
# Four fixtures under tests/fixtures/, and the verdicts the analyser must reach
# on each. `solution` is the shape the lab asks for; `copypaste` and `broken`
# are the shapes it exists to catch.
GR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RW="$GR/lab-03/verify/read_workflows.py"
fails=0

expect() {   # expect <fixture> <line that must be in the report>
  local fx="$1"; shift
  if grep -qxF "$1" "/tmp/rg.$fx"; then
    printf '  ok    %-12s %s\n' "$fx" "$1"
  else
    printf '  FAIL  %-12s expected: %s\n' "$fx" "$1"; fails=$((fails+1))
  fi
}

reject() {   # reject <fixture> <line that must NOT be in the report>
  local fx="$1"; shift
  if grep -qxF "$1" "/tmp/rg.$fx"; then
    printf '  FAIL  %-12s must not say: %s\n' "$fx" "$1"; fails=$((fails+1))
  else
    printf '  ok    %-12s no "%s"\n' "$fx" "$1"
  fi
}

for fx in good solution copypaste broken; do
  ( cd "$GR/tests/fixtures/$fx" && python3 "$RW" .github/workflows .github/actions ) > "/tmp/rg.$fx"
done

echo "the shape the lab asks for"
for fx in good solution; do
  expect $fx "LOCALCALLS 2"
  expect $fx "INPUTUSED yes"
  expect $fx "OUTPUTCONSUMED yes"
  expect $fx "COMPOSITEINREUSE yes"
  expect $fx "TESTFILES 1"
  expect $fx "BUILDFILES 1"
  expect $fx "GATE yes"            # promotion depends on qa
  expect $fx "TESTGATE yes"        # a red unit suite cannot publish
  expect $fx "QAINPUT yes"
  expect $fx "QADIGEST yes"
  expect $fx "QALATEST no"
  reject $fx "UNPINNED"
done

echo "the same pipeline, copied instead of called"
expect copypaste "LOCALCALLS 0"
expect copypaste "TESTFILES 2"
expect copypaste "BUILDFILES 2"
expect copypaste "GATE no"
expect copypaste "OUTPUTCONSUMED no"
expect copypaste "UNPINNED lab-03.yml actions/checkout@main (main is a branch)"

echo "and with a lab folder to grade"
expect broken "GATE no"
expect broken "QAINPUT no"
expect broken "CONC lab-03-pipeline.yml workflow cancel=True group=ci"

echo
[ "$fails" -eq 0 ] && echo "all verdicts as expected" || echo "$fails verdict(s) wrong"
exit $([ "$fails" -eq 0 ] && echo 0 || echo 1)
