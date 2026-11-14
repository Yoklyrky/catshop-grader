#!/usr/bin/env bash
#
# runs-api.sh — the three checks that ask the API, with curl stubbed.
#
#   ./tests/runs-api.sh ran-happy | ran-none | ran-noslash | noperm \
#                       | saved | not-saved | cancelled | never-cancelled
#
# ran-happy        a run whose jobs are named "build / test"  -> PASS reuse:ran
# ran-none         no runs of the student's own pipeline       -> FAIL reuse:ran
# ran-noslash      runs exist, no reusable call among them     -> FAIL reuse:ran
# noperm           403, no actions: read                       -> WARN, never FAIL
# saved            298s cold against 91s warm                  -> PASS cache:runs
# not-saved        298s against 290s                           -> FAIL cache:runs
# cancelled        one cancelled run on the branch             -> PASS conc:proof
# never-cancelled  none                                        -> FAIL conc:proof
GR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JSON=0; KEEP=0; PORT=8080
. "$GR/common/lib.sh"
. "$GR/lab-03/verify/api.sh"

export GH_TOKEN=fake GITHUB_REPOSITORY=student/catshop-labs GITHUB_REF_NAME=lab-03 GITHUB_WORKFLOW=lab-03

CODE=200
RUNS='{"workflow_runs":[{"id":99,"name":"lab-03"},{"id":1111111111,"name":"lab-03-pipeline"}]}'
JOBS='{"jobs":[{"name":"build / test"},{"name":"promote"}]}'
JOBS_FLAT='{"jobs":[{"name":"test"},{"name":"publish"}]}'
CANCELLED='{"workflow_runs":[{"id":3333333333,"name":"lab-03-pipeline"}]}'
LONG='{"run_started_at":"2026-11-20T10:00:00Z","updated_at":"2026-11-20T10:04:58Z"}'
SHORT='{"run_started_at":"2026-11-20T11:00:00Z","updated_at":"2026-11-20T11:01:31Z"}'
NEARLY='{"run_started_at":"2026-11-20T11:00:00Z","updated_at":"2026-11-20T11:04:50Z"}'

case "$1" in
  ran-happy)       : ;;
  ran-none)        RUNS='{"workflow_runs":[{"id":99,"name":"lab-03"}]}' ;;
  ran-noslash)     JOBS="$JOBS_FLAT" ;;
  noperm)          CODE=403 ;;
  saved)           : ;;
  not-saved)       SHORT="$NEARLY" ;;
  cancelled)       : ;;
  never-cancelled) CANCELLED='{"workflow_runs":[]}' ;;
  *) echo "unknown case: $1" >&2; exit 2 ;;
esac

curl() {
  local args="$*" out=""
  case "$args" in
    *status=cancelled*)      out="$CANCELLED" ;;
    */actions/runs/*/jobs*)  out="$JOBS" ;;
    *actions/runs/2222222222) out="$SHORT" ;;
    *actions/runs/1111111111) out="$LONG" ;;
    */actions/runs*)         out="$RUNS" ;;
  esac
  printf '%s\n%s\n' "$out" "$CODE"
}

cd "$GR/tests/fixtures/solution/lab-03" || exit 2
case "$1" in
  ran-happy|ran-none|ran-noslash|noperm)
    . "$GR/lab-03/verify/sections/reuse.sh"; it_really_ran ;;
  saved|not-saved)
    . "$GR/lab-03/verify/sections/cache.sh"; measured ;;
  cancelled|never-cancelled)
    . "$GR/lab-03/verify/sections/concurrency.sh"; written_down; it_really_cancelled ;;
esac
echo "--- pass=$PASS fail=$FAIL warn=$WARN"
