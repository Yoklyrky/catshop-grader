#!/usr/bin/env bash
#
# section: concurrency — bonus. The identifier, and the one place not to cancel.
#
# Two halves. The file has to name a group that means something, and the
# repository has to show a run that was really cancelled by it — because a
# concurrency block is the kind of thing everybody writes and nobody watches
# work.

WF=../.github/workflows
ACT=../.github/actions

section_run() {
  sect "the group"
  local WFR
  WFR=$(python3 "$(dirname "${BASH_SOURCE[0]}")/../read_workflows.py" "$WF" "$ACT" 2>/dev/null)
  [ -n "$WFR" ] || { bad "conc:group" "the workflows do not parse"; return; }

  if ! grep -q '^CONC ' <<<"$WFR"; then
    bad "conc:group" "no concurrency: block anywhere — two pushes in a minute run two full pipelines"
    return
  fi
  ok "conc:group" "$(grep -c '^CONC ' <<<"$WFR") concurrency block(s)"

  local groups
  groups=$(grep '^CONC ' <<<"$WFR" | sed 's/.*group=//')
  if grep -q 'github\.\(ref\|head_ref\|ref_name\|event\.number\)' <<<"$groups"; then
    ok "conc:identifier" "the group is keyed on the ref, so one branch waits for itself and not for everybody"
  else
    bad "conc:identifier" "the group is a constant ($(head -1 <<<"$groups")) — that serialises the whole repository"
  fi

  grep -q 'github\.workflow' <<<"$groups" \
    && ok   "conc:workflow" "the workflow is part of the group, so two different pipelines do not collide" \
    || warn "conc:workflow" "add github.workflow to the group unless you meant two workflows to queue against each other"

  sect "and the place not to cancel"
  local risky=""
  local line
  while read -r line; do
    case "$line" in
      *cancel=True*) risky="$line" ;;
    esac
  done < <(grep '^CONC ' <<<"$WFR")

  if [ -z "$risky" ]; then
    ok "conc:not-main" "cancel-in-progress is never a bare true"
  elif grep -q "github.ref\|github.event_name\|!=" <<<"$(grep '^CONC ' <<<"$WFR" | sed 's/.*cancel=//')"; then
    ok "conc:not-main" "cancelling is decided by an expression, not switched on everywhere"
  else
    bad "conc:not-main" "cancel-in-progress: true with no condition — the next push kills a publish halfway through"
  fi

  sect "it is scoped to this lab"
  if grep -q '^PATHS ' <<<"$WFR"; then
    ok "paths:scoped" "$(grep '^PATHS ' <<<"$WFR" | head -1 | sed 's/^PATHS //')"
  else
    warn "paths:scoped" "no paths: filter — a README typo runs the whole pipeline"
  fi

  it_really_cancelled
  written_down
}

# A cancelled run is a fact in the API. Nothing in a YAML file proves one.
it_really_cancelled() {
  sect "a run that was really cancelled"
  . "$(dirname "${BASH_SOURCE[0]}")/../api.sh"
  if ! api_ready; then
    warn "conc:proof" "no token or repository — run this in Actions to grade it"; return
  fi

  local branch runs n
  branch="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-}}"
  runs=$(gh_api --get --data-urlencode "branch=$branch" --data-urlencode "status=cancelled" \
                --data-urlencode "per_page=20" "$API/actions/runs")
  case "$(api_code)" in
    200) : ;;
    403) warn "conc:proof" "403 — the grading job needs permissions: actions: read"; return ;;
    *)   warn "conc:proof" "the runs API answered $(api_code)"; return ;;
  esac

  n=$(jq_py "$runs" "len(d.get('workflow_runs',[]))")
  if [ "${n:-0}" -ge 1 ]; then
    ok "conc:proof" "$n cancelled run(s) on '$branch' — the group did something"
  else
    bad "conc:proof" "no cancelled run on '$branch' — push twice in quick succession and watch the first one go"
  fi
}

written_down() {
  sect "what you saw"
  need_file CONCURRENCY.md
  [ -f CONCURRENCY.md ] || return

  local ids
  ids=$(grep -oE 'actions/runs/[0-9]+' CONCURRENCY.md | sort -u | wc -l | tr -d ' ')
  [ "${ids:-0}" -ge 2 ] && ok "conc:written" "$ids run URLs — the one that was cancelled and the one that cancelled it" \
                        || bad "conc:written" "paste both runs: the one that was cancelled and the one that replaced it"

  grep -qiE 'safe|because|would|lost|partial|deploy|publish' CONCURRENCY.md \
    && ok  "conc:why" "and why cancelling that one was safe" \
    || bad "conc:why" "one line on why it was safe to cancel that run — and where it would not have been"
}
