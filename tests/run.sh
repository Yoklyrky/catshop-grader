#!/usr/bin/env bash
#
# run.sh — every test the graders have. One file.
#
#   ./tests/run.sh              everything
#   ./tests/run.sh graph        the workflow analyser's verdicts on the fixtures
#   ./tests/run.sh sections     every lab-3 section, on the good fixture and the bad one
#   ./tests/run.sh api          the checks that call GitHub, with curl stubbed
#
# Nothing here needs a network, a token or a registry. Two things therefore
# cannot be reached: `qa:pull` wants a real published digest, and the API
# checks want a repository — which is what the stubs are for.
set -uo pipefail
GR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0
ok()   { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILS=$((FAILS+1)); }

# ── the analyser ─────────────────────────────────────────────────────────────
graph() {
  echo "== graph"
  local fx
  for fx in good solution copypaste broken; do
    ( cd "$GR/tests/fixtures/$fx" && python3 "$GR/lab-03/read_workflows.py" .github/workflows .github/actions ) > "/tmp/rg.$fx"
  done
  want()   { grep -qxF "$2" "/tmp/rg.$1" && ok "$1: $2" || fail "$1: expected '$2'"; }
  unwant() { grep -qxF "$2" "/tmp/rg.$1" && fail "$1: must not say '$2'" || ok "$1: no '$2'"; }

  for fx in good solution; do
    want $fx "LOCALCALLS 2"; want $fx "INPUTUSED yes"; want $fx "OUTPUTCONSUMED yes"
    want $fx "COMPOSITEINREUSE yes"; want $fx "TESTFILES 1"; want $fx "BUILDFILES 1"
    want $fx "GATE yes"; want $fx "TESTGATE yes"
    want $fx "QAINPUT yes"; want $fx "QADIGEST yes"; want $fx "QALATEST no"
    unwant $fx "UNPINNED"
  done
  want copypaste "LOCALCALLS 0"; want copypaste "TESTFILES 2"; want copypaste "BUILDFILES 2"
  want copypaste "GATE no"; want copypaste "OUTPUTCONSUMED no"
  want copypaste "UNPINNED lab-03.yml actions/checkout@main (main is a branch)"
  want broken "GATE no"; want broken "QAINPUT no"
  want broken "CONC lab-03-pipeline.yml workflow cancel=True group=ci"
}

# ── whole sections, against a correct solution and a wrong one ───────────────
sections() {
  local fx s work out
  for fx in solution broken; do
    echo "== sections · $fx"
    work="$(mktemp -d)"
    cp -R "$GR/tests/fixtures/$fx/." "$work/"
    git -C "$work" init -q .; git -C "$work" add -A
    git -C "$work" -c user.email=t@t -c user.name=t commit -qm "$fx"
    for s in reuse cache qa aqa concurrency; do
      out=$( cd "$work" && bash "$GR/lab-03/verify.sh" --section "$s" --path lab-03 2>/dev/null \
             | grep -E '^section ' )
      case "$fx:$s" in
        solution:qa) grep -q ' 1 fail' <<<"$out" \
          && ok "$s — clean but for qa:pull, which needs a real digest" \
          || fail "$s — $out" ;;
        solution:*) grep -q ' 0 fail' <<<"$out" && ok "$s — $out" || fail "$s — $out" ;;
        broken:*)   grep -q ' 0 fail' <<<"$out" && fail "$s — passed a broken solution" || ok "$s — red, as it should be: $out" ;;
      esac
    done
    rm -rf "$work"
  done
}

# ── the four API checks, and lab 2's, with curl stubbed ──────────────────────
api() {
  echo "== api"
  local c
  for c in happy empty tiny noperm mismatch; do
    printf '  lab2/cache %-9s ' "$c"
    bash "$GR/tests/cache-api.sh" "$c" 2>/dev/null | tail -1
  done
  for c in ran-happy ran-none ran-noslash noperm saved not-saved cancelled never-cancelled; do
    printf '  lab3/api   %-16s ' "$c"
    bash "$GR/tests/runs-api.sh" "$c" 2>/dev/null | tail -1
  done
  echo "  (read the counts: a case named for a failure must show fail=1)"
}

case "${1:-all}" in
  graph)    graph ;;
  sections) sections ;;
  api)      api ;;
  all)      graph; sections; api ;;
  *) echo "usage: run.sh [graph|sections|api]" >&2; exit 2 ;;
esac

echo
[ "$FAILS" -eq 0 ] && echo "all assertions held" || echo "$FAILS assertion(s) failed"
exit $([ "$FAILS" -eq 0 ] && echo 0 || echo 1)
