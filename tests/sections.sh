#!/usr/bin/env bash
#
# sections.sh — every lab-3 section against a correct solution and a broken one.
#
#   ./tests/sections.sh solution      expect: 0 fail everywhere
#   ./tests/sections.sh broken        expect: a FAIL with a reason in every section
#
# The fixture is copied to a temporary directory and git-initialised there,
# because the secret checks read git history and a fixture must not carry a
# repository of its own inside this one.
#
# Two checks cannot run here and warn instead: `qa:pull` needs a real published
# digest, and the three API checks need a repository. tests/runs-api.sh covers
# the API paths with curl stubbed.
set -uo pipefail
GR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FX="${1:-solution}"
[ -d "$GR/tests/fixtures/$FX" ] || { echo "no such fixture: $FX" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp -R "$GR/tests/fixtures/$FX/." "$WORK/"
git -C "$WORK" init -q .
git -C "$WORK" add -A
git -C "$WORK" -c user.email=t@t -c user.name=t commit -qm "$FX"

for s in reuse cache qa aqa concurrency; do
  printf '\n======== %s · %s\n' "$FX" "$s"
  ( cd "$WORK" && bash "$GR/lab-03/verify/verify.sh" --section "$s" --path lab-03 2>/dev/null ) \
    | grep -E '^  (FAIL|WARN)|^section '
done
