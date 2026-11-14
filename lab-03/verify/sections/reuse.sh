#!/usr/bin/env bash
#
# section: reuse — one definition, called twice.
#
# Nothing here runs the student's pipeline; the grader cannot trigger somebody
# else's workflow. It reads every workflow in the repository, resolves the
# reusable calls between them, and asks whether the pipeline has ONE definition
# of testing and building — plus one API check, because a workflow file can
# describe a reusable call that never happened.

WF=../.github/workflows
ACT=../.github/actions

section_run() {
  sect "the workflows, read together"
  [ -d "$WF" ] || { bad "reuse:file" "no .github/workflows/ at the repository root"; return; }

  local WFR
  WFR=$(python3 "$(dirname "${BASH_SOURCE[0]}")/../read_workflows.py" "$WF" "$ACT" 2>/tmp/rw.$$)
  if [ -z "$WFR" ]; then
    bad "reuse:parses" "the workflows do not parse"; head -3 /tmp/rw.$$ >&2; return
  fi
  if grep -q '^UNPARSEABLE' <<<"$WFR"; then
    bad "reuse:parses" "$(grep '^UNPARSEABLE' <<<"$WFR" | head -1 | cut -d' ' -f2) is not valid YAML"; return
  fi
  ok "reuse:parses" "$(sed -n 's/^WORKFLOWS //p' <<<"$WFR") workflow file(s), all valid YAML"

  sect "a workflow calls a workflow"
  local calls
  calls=$(grep -c '^CALLER ' <<<"$WFR")
  if [ "$calls" -ge 1 ]; then
    ok "reuse:caller" "$(grep '^CALLER ' <<<"$WFR" | sed 's/^CALLER //' | tr '\n' ';' | sed 's/;$//')"
  else
    bad "reuse:caller" "no job uses: another workflow — nothing is reused"; return
  fi

  grep -q '^CALLED ' <<<"$WFR" \
    && ok  "reuse:called" "$(grep -c '^CALLED ' <<<"$WFR") workflow(s) declare on: workflow_call" \
    || bad "reuse:called" "the file being called does not declare on: workflow_call"

  sect "it takes arguments, and gives an answer back"
  local n typed untyped
  read -r n _ typed _ untyped < <(sed -n 's/^INPUTS //p' <<<"$WFR")
  if [ "${n:-0}" -eq 0 ]; then
    bad "reuse:typed" "the called workflow declares no inputs — it is a copy with extra steps"
  elif [ "${untyped:-0}" -gt 0 ]; then
    bad "reuse:typed" "$untyped input(s) with no type: — workflow_call inputs are typed"
  else
    ok "reuse:typed" "$typed typed input(s)"
  fi

  grep -q '^INPUTUSED yes' <<<"$WFR" \
    && ok  "reuse:inputused" "the called workflow reads inputs.*" \
    || bad "reuse:inputused" "nothing inside the called workflow reads an input"

  if grep -q '^WFOUTPUTS -' <<<"$WFR"; then
    bad "reuse:outputs" "the called workflow declares no outputs — the digest cannot come back"
  elif grep -q '^OUTPUTCONSUMED yes' <<<"$WFR"; then
    ok "reuse:outputs" "an output is declared and the caller reads needs.<job>.outputs"
  else
    bad "reuse:outputs" "outputs are declared but the caller never reads one"
  fi

  sect "the QA suite is the second one"
  local qa_in_called=no
  while read -r _ site; do
    local f="${site%%:*}"
    grep -q "^CALLED $f\$" <<<"$WFR" && qa_in_called=yes
  done < <(grep '^QA ' <<<"$WFR")

  if [ "$qa_in_called" = yes ]; then
    ok "reuse:qa-called" "the QA suite runs inside a reusable workflow"
  else
    bad "reuse:qa-called" "the QA suite is not a reusable workflow — lab 5 calls this same file against three environments"
  fi

  grep -q '^QAINPUT yes' <<<"$WFR" \
    && ok  "reuse:qa-input" "the QA call is passed the image rather than knowing it" \
    || bad "reuse:qa-input" "the QA call hardcodes what it tests — pass it in with:"

  sect "steps compose into a job"
  local comp
  comp=$(sed -n 's/^COMPOSITE //p' <<<"$WFR")
  if [ "$comp" = "-" ]; then
    bad "reuse:composite" "no composite action under .github/actions/"
  else
    ok "reuse:composite" "${comp#../}"
    grep -q '^COMPOSITEINREUSE yes' <<<"$WFR" \
      && ok  "reuse:composite-inside" "the reusable workflow is what calls it" \
      || warn "reuse:composite-inside" "the composite action is only called from the caller — inside the reusable workflow is the normal arrangement"
  fi

  sect "one definition, not four copies"
  local tf bf
  tf=$(sed -n 's/^TESTFILES //p' <<<"$WFR"); bf=$(sed -n 's/^BUILDFILES //p' <<<"$WFR")
  [ "${tf:-0}" -le 1 ] && ok "reuse:nocopy-test" "the unit suite is invoked in one file" \
                       || bad "reuse:nocopy-test" "pytest is invoked in $tf different workflow files"
  [ "${bf:-0}" -le 1 ] && ok "reuse:nocopy-build" "the image is built in one file" \
                       || bad "reuse:nocopy-build" "the image is built in $bf different workflow files"

  sect "what you call, and at which version"
  if grep -q '^UNPINNED ' <<<"$WFR"; then
    bad "reuse:pinned" "$(grep '^UNPINNED ' <<<"$WFR" | head -1 | sed 's/^UNPINNED //')"
  else
    ok "reuse:pinned" "every third-party uses: is at a tag or a sha"
  fi

  grep -q '^SECRETS yes' <<<"$WFR" \
    && ok   "reuse:secrets" "secrets are declared or inherited, not passed as inputs" \
    || warn "reuse:secrets" "nothing is passed as a secret — fine if nothing needs one, say so in the pull request"

  it_really_ran
  rm -f /tmp/rw.$$
}

# A reusable call has a signature from outside: the caller's run shows its jobs
# as "<calling job> / <called job>". No YAML can fake that, and no local run can
# produce it. Needs actions: read; without it, WARN.
it_really_ran() {
  sect "and it really ran"
  . "$(dirname "${BASH_SOURCE[0]}")/../api.sh"
  if ! api_ready; then
    warn "reuse:ran" "no token or repository — run this in Actions to grade it"; return
  fi

  local branch runs ids body found=""
  branch="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-}}"
  runs=$(gh_api --get --data-urlencode "branch=$branch" --data-urlencode "per_page=20" \
                "$API/actions/runs")
  case "$(api_code)" in
    200) : ;;
    403) warn "reuse:ran" "403 — the grading job needs permissions: actions: read"; return ;;
    *)   warn "reuse:ran" "the runs API answered $(api_code)"; return ;;
  esac

  # the grader's own run is a run too, so look at several and skip this workflow
  ids=$(jq_py "$runs" "' '.join(str(r['id']) for r in d.get('workflow_runs',[]) if r.get('name') != '${GITHUB_WORKFLOW:-}')" )
  ids=$(tr ' ' '\n' <<<"$ids" | head -8 | tr '\n' ' ')
  if [ -z "${ids// /}" ]; then
    bad "reuse:ran" "no run of your own pipeline on '$branch' — push it before it can be graded"; return
  fi

  local id
  for id in $ids; do
    body=$(gh_api "$API/actions/runs/$id/jobs?per_page=100")
    [ "$(api_code)" = 200 ] || continue
    found=$(jq_py "$body" "next((j['name'] for j in d.get('jobs',[]) if ' / ' in j.get('name','')), '')")
    [ -n "$found" ] && break
  done

  if [ -n "$found" ]; then
    ok "reuse:ran" "a run shows the job '$found' — that slash is a reusable call"
  else
    bad "reuse:ran" "no run on '$branch' shows a '<job> / <job>' name, so no reusable workflow has actually run"
  fi
}
