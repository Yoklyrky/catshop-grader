#!/usr/bin/env bash
#
# verify.sh — grade ONE section of lab 3.
#
#   ./verify.sh --section reuse --path lab-03
#   ./verify.sh --section cache --path lab-03 --json
#
# Sections, in the order the lab teaches them:
#
#   reuse        one definition of test-and-build, called twice   section 1 · required
#   cache        both stores, proved, and the minutes saved       section 2 · required
#   qa           the suite, against the published image           section 3 · required
#   aqa          scenarios, a negative case, a regression         bonus
#   concurrency  the group, and a run that was really cancelled   bonus
#
# Three checks here ask the Actions API rather than the YAML: a reusable call
# that really ran, caches that really exist, and a run that was really
# cancelled. They need `actions: read`; without it they WARN.
#
# Flags:
#   --path DIR   the lab folder to grade, relative to the repository root
#   --port N     the host port the published image is run on (default 8080)
#   --json       machine-readable output
#   --keep       leave the container running afterwards, for inspection
#
# Exit 0 = nothing failed. A WARN is a judgement call to explain in the pull request.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECTIONS="$HERE/sections"

SECTION=""; WORKDIR=""; JSON=0; KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --section) SECTION="${2:?--section needs a value}"; shift 2 ;;
    --path)    WORKDIR="${2:?--path needs a value}";    shift 2 ;;
    --port)    PORT="${2:?--port needs a value}";       shift 2 ;;
    --json)    JSON=1; shift ;;
    --keep)    KEEP=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$SECTION" ]; then
  echo "--section is required. Available:" >&2
  for f in "$SECTIONS"/*.sh; do echo "  $(basename "$f" .sh)" >&2; done
  exit 2
fi
[ -f "$SECTIONS/$SECTION.sh" ] || { echo "unknown section '$SECTION'" >&2; exit 2; }

# The lab folder is the working directory; the workflows the sections read are
# one level up, at the repository root, which is the only place GitHub reads them.
if [ -n "$WORKDIR" ]; then
  cd "$WORKDIR" || { echo "no such path: $WORKDIR" >&2; exit 2; }
fi

export JSON KEEP
# shellcheck source=../../common/lib.sh
. "$HERE/../../common/lib.sh"
trap cleanup EXIT

# shellcheck source=/dev/null
. "$SECTIONS/$SECTION.sh"     # defines section_run
# shellcheck source=../../common/secrets.sh
. "$HERE/../../common/secrets.sh"

log "${B}catshop lab 3 · section: $SECTION${N}"
section_run
check_secrets                 # every section, always
rm -f /tmp/b.$$ /tmp/cb.$$ /tmp/cu.$$ "${TMPDIR:-/tmp}/apicode.$$"

emit_report "$SECTION"
[ "$FAIL" -eq 0 ]
