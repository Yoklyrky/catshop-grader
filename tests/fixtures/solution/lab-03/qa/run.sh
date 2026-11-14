#!/usr/bin/env bash
#
# run.sh — pull the published image, stand the stack up, drive it, tear it down.
#
# This is the file your QA workflow calls. It is given to you: the QA half of a
# pipeline is always the same four moves, and the lab is about where they sit in
# the pipeline rather than about rewriting them.
#
#   QA_IMAGE=ghcr.io/you/catshop@sha256:... bash lab-03/qa/run.sh
#
# | variable      | default           | what it is                                   |
# |---------------|-------------------|----------------------------------------------|
# | QA_IMAGE      | — (required)      | the image to test. A DIGEST, not a tag       |
# | QA_PORT       | 8080              | the host port the stack is published on      |
# | QA_BASE_URL   | http://localhost:$QA_PORT | what the suite is pointed at         |
# | QA_PROFILE    | (none)            | `partner` also starts the stubbed partner    |
# | QA_REPORT     | qa-report.xml     | junit file, for uploading as an artifact     |
# | QA_PYTHON     | python3           | the interpreter that has pytest and requests |
# | QA_KEEP       | (unset)           | set to 1 to leave the stack up afterwards    |
#
# Exit status is the suite's. Nothing here decides whether QA passed except the
# tests themselves.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB="$(cd "$HERE/.." && pwd)"
COMPOSE="$HERE/compose.qa.yaml"

: "${QA_IMAGE:?QA_IMAGE is required — the digest your pipeline published}"
QA_PORT="${QA_PORT:-8080}"
QA_BASE_URL="${QA_BASE_URL:-http://localhost:$QA_PORT}"
QA_REPORT="${QA_REPORT:-$LAB/qa-report.xml}"
QA_PYTHON="${QA_PYTHON:-python3}"
export QA_IMAGE QA_PORT QA_BASE_URL
[ -n "${QA_PROFILE:-}" ] && export QA_PROFILE   # the suite may want to know which stack it is in
export COMPOSE_PROJECT_NAME="catshop-qa-$$"

case "$QA_IMAGE" in
  *@sha256:*) : ;;
  *) echo "::warning::QA_IMAGE is '$QA_IMAGE' — that is a tag. A tag can move between the build and this run." ;;
esac

say() { printf '\n== %s\n' "$*"; }

compose() {
  if [ -n "${QA_PROFILE:-}" ]; then
    docker compose -f "$COMPOSE" --profile "$QA_PROFILE" "$@"
  else
    docker compose -f "$COMPOSE" "$@"
  fi
}

down() {
  [ "${QA_KEEP:-0}" = 1 ] && { say "left up — docker compose -p $COMPOSE_PROJECT_NAME down -v"; return; }
  compose down -v >/dev/null 2>&1 || true
}
trap down EXIT

# 1 · the bytes under test come from the registry, not from this machine
say "pull $QA_IMAGE"
docker pull -q "$QA_IMAGE" || { echo "cannot pull it — is the package public?" >&2; exit 1; }

# 2 · up
say "up${QA_PROFILE:+ (profile: $QA_PROFILE)}"
compose up -d || exit 1

# 3 · wait for an address that answers, because "started" is not "ready"
say "wait for $QA_BASE_URL/health"
ready=0
for _ in $(seq 1 60); do
  if curl -sf -m 2 "$QA_BASE_URL/health" >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
if [ "$ready" != 1 ]; then
  echo "no answer on $QA_BASE_URL/health after 60s" >&2
  compose logs --tail 30 >&2
  exit 1
fi

# 4 · drive it from outside, and leave a report behind
say "pytest $HERE"
"$QA_PYTHON" -m pytest "$HERE" -q --junitxml="$QA_REPORT"
rc=$?

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { printf '## qa · %s\n\n' "$([ $rc -eq 0 ] && echo passed || echo FAILED)"
    printf '- image: `%s`\n' "$QA_IMAGE"
    printf '- address: %s\n' "$QA_BASE_URL"
    printf '- profile: %s\n' "${QA_PROFILE:-none, so the partner is absent and /price answers 502}"
    printf '- report: `%s`\n' "${QA_REPORT#"$LAB/"}"
  } >> "$GITHUB_STEP_SUMMARY"
fi

exit $rc
