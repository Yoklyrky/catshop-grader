#!/usr/bin/env bash
#
# section: aqa — bonus. Scenarios of your own.
#
# The five scenarios in qa/test_smoke.py are given, so they are not graded here
# and they do not count towards anything. This section is about the thing QA
# actually owns: cases that came from somewhere, including the ones that only
# exist because something broke once.

WF=../.github/workflows
ACT=../.github/actions

section_run() {
  sect "how much it covers"
  [ -d qa ] || { bad "aqa:suite" "no qa/ folder"; return; }

  # the five given scenarios do not count: this bonus is the ones you added
  local own n
  own=$(find qa -name 'test_*.py' ! -name 'test_smoke.py' 2>/dev/null)
  if [ -z "$own" ]; then
    bad "aqa:scenarios" "only the given test_smoke.py is here — this bonus is scenarios of your own, in your own file"
    return
  fi
  n=$(grep -hoE '^def test_[A-Za-z0-9_]+' $own 2>/dev/null | wc -l | tr -d ' ')
  [ "${n:-0}" -ge 3 ] && ok "aqa:scenarios" "$n scenario(s) of your own, beside the five you were given" \
                      || bad "aqa:scenarios" "$n of your own — three is the bar, and the given five do not count"

  if grep -qE '== *(4[0-9][0-9]|5[0-9][0-9])|in *\( *4[0-9][0-9]|status_code *!= *200|raises' $own 2>/dev/null; then
    ok "aqa:negative" "one of yours asserts a failure, not a success"
  else
    bad "aqa:negative" "every case of yours expects things to work — a suite that cannot see a 404 or a 502 is half a suite"
  fi

  sect "where the cases came from"
  if [ -f qa/REGRESSION.md ]; then
    ok "aqa:regression-file" "qa/REGRESSION.md is there"
    local named=""
    local t
    for t in $(grep -rhoE 'def (test_[A-Za-z0-9_]+)' qa/ | sed 's/^def //'); do
      grep -q "$t" qa/REGRESSION.md && named="$t" && break
    done
    [ -n "$named" ] && ok  "aqa:regression-case" "it names the case that exists because of the incident ($named)" \
                    || bad "aqa:regression-case" "REGRESSION.md does not name any test in the suite — which case came from the incident?"
    local words
    words=$(wc -w < qa/REGRESSION.md | tr -d ' ')
    [ "${words:-0}" -ge 15 ] && ok "aqa:regression-told" "the incident is written down" \
                             || bad "aqa:regression-told" "two lines about what broke, please — a case with no story is a case nobody will keep"
  else
    bad "aqa:regression-file" "no qa/REGRESSION.md — one incident, two lines, and the case it produced"
  fi

  sect "how it runs"
  local WFR
  WFR=$(python3 "$(dirname "${BASH_SOURCE[0]}")/../read_workflows.py" "$WF" "$ACT" 2>/dev/null)
  local qa_files
  qa_files=$(grep '^QA ' <<<"$WFR" | sed 's/^QA //;s/:.*//' | sort -u)
  local text=""
  local f
  for f in $qa_files; do text+="$(cat "$WF/$f" 2>/dev/null)"; done
  [ -n "$text" ] || text=$(cat $WF/*.yml $WF/*.yaml 2>/dev/null)

  grep -q 'matrix:' <<<"$text" \
    && ok  "aqa:matrix" "the suite fans out over a matrix" \
    || bad "aqa:matrix" "one configuration only — a matrix is how the same suite covers two of them"

  grep -q 'upload-artifact' <<<"$text" \
    && ok  "aqa:artifact" "a report leaves the runner as an artifact" \
    || bad "aqa:artifact" "nothing is uploaded — when the suite fails at 02:00 the log is gone and the report is not"

  if grep -rqE 'check|required' qa/REGRESSION.md 2>/dev/null; then
    ok "aqa:checkname" "the check branch protection would require is named"
  else
    warn "aqa:checkname" "name the check a branch rule would require — that name is a job name, and it changes when the job is renamed"
  fi
}
