#!/usr/bin/env bash
#
# section: qa — bonus. The stage that drives what you published.
#
# The suite and the stack are given, so nothing here grades scenarios. What it
# grades is the JOB: does the digest reach it, is the stack what runs, does
# anything depend on the result. Then it does the stage itself — pull the digest
# out of published.txt, bring the given stack up against it, run the suite,
# tear it down — because a job that looks right and an image that answers are
# two different claims.

WF=../.github/workflows
ACT=../.github/actions
REF_FILE=published.txt
QA_COMPOSE=qa/compose.qa.yaml

section_run() {
  sect "the suite and the stack you were given"
  if [ ! -d qa ]; then
    bad "qa:suite" "no qa/ folder — it came with the lab, and nothing here works without it"; return
  fi
  local files
  files=$(find qa -name 'test_*.py' | wc -l | tr -d ' ')
  [ "$files" -ge 1 ] && ok "qa:suite" "$files QA file(s) under qa/" \
                     || { bad "qa:suite" "no test_*.py under qa/"; return; }

  need_file "$QA_COMPOSE"
  if [ -f "$QA_COMPOSE" ]; then
    if grep -qE '^[[:space:]]*build:' "$QA_COMPOSE"; then
      bad "qa:nobuild" "the stack has a build: — then it is not testing what you published"
    else
      ok "qa:nobuild" "the app service pulls an image; nothing in the stack builds one"
    fi
  fi

  if grep -rqE '^(import|from) +app|test_client\(' qa/ 2>/dev/null; then
    bad "qa:blackbox" "something in qa/ imports the app or uses Flask's test client — that is a unit test, not AQA"
  else
    ok "qa:blackbox" "nothing in qa/ imports the app — it drives it from outside"
  fi

  sect "where the stage sits in the pipeline"
  local WFR
  WFR=$(python3 "$(dirname "${BASH_SOURCE[0]}")/../read_workflows.py" "$WF" "$ACT" 2>/dev/null)
  if [ -z "$WFR" ]; then
    bad "qa:job" "the workflows do not parse, so the stage cannot be read"
  elif ! grep -q '^QA ' <<<"$WFR"; then
    bad "qa:job" "no job runs the QA suite — this bonus is that job"
  else
    ok "qa:job" "$(grep -c '^QA ' <<<"$WFR") job(s) run the suite"

    local qa_text
    qa_text=$(qa_job_text "$WFR")
    if grep -q 'docker compose' <<<"$qa_text"; then
      ok "qa:stack" "the job brings the given stack up itself"
    else
      bad "qa:stack" "the job never runs docker compose — the suite needs the stack, not just the image"
    fi

    if grep -qE 'pytest' <<<"$qa_text"; then
      ok "qa:inline" "the pull, the stack and the suite are steps in the job, where they can be read"
    else
      warn "qa:inline" "the suite is invoked indirectly — a stage nobody can read in the workflow file is a stage nobody debugs at 02:00"
    fi

    if grep -qE 'down|always\(\)' <<<"$qa_text"; then
      ok "qa:teardown" "the stack comes down afterwards"
    else
      warn "qa:teardown" "nothing tears the stack down — on a self-hosted runner that is the next job's problem"
    fi

    grep -q '^QADIGEST yes' <<<"$WFR" \
      && ok  "qa:digest" "the job is given a digest" \
      || bad "qa:digest" "the job is not given a digest — a tag can move between the build and this run"

    grep -q '^QALATEST yes' <<<"$WFR" \
      && bad "qa:latest" "':latest' appears on the QA path — the one reference that can change under you" \
      || ok  "qa:latest" "no ':latest' on the QA path"

    grep -q '^GATE yes' <<<"$WFR" \
      && ok  "qa:gate" "shipping depends on the QA job — a red suite cannot promote" \
      || bad "qa:gate" "nothing depends on the QA job, so a red suite changes nothing about what ships"
  fi

  drive_the_published_image
}

# the qa node's own steps, plus the file it calls if it is a reusable call
qa_job_text() {
  local report="$1" site f j
  for site in $(grep '^QA ' <<<"$report" | sed 's/^QA //'); do
    f="${site%%:*}"; j="${site##*:}"
    python3 - "$WF/$f" "$j" <<'PY' 2>/dev/null
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1], errors="replace").read()) or {}
print(yaml.dump((doc.get("jobs") or {}).get(sys.argv[2], {})))
PY
    cat "$WF/$f" 2>/dev/null
  done
}

# The stage, for real: the bytes come from the registry and the stack is the one
# in the repository. Nothing is graded on how fast it is, only that it answers.
drive_the_published_image() {
  sect "the stage, run here"
  need_file "$REF_FILE"
  [ -f "$REF_FILE" ] || return
  [ -f "$QA_COMPOSE" ] || { warn "qa:runs" "no $QA_COMPOSE to bring up"; return; }

  local ref
  ref=$(tr -d ' \t\r\n' < "$REF_FILE")
  case "$ref" in
    *@sha256:*) ok  "qa:ref" "published.txt is pinned by digest" ;;
    "")         bad "qa:ref" "$REF_FILE is empty"; return ;;
    *)          bad "qa:ref" "that is not a digest reference: $ref"; return ;;
  esac

  if ! docker pull -q "$ref" >/tmp/pull.$$ 2>&1; then
    bad "qa:pull" "cannot pull it — is the package public?"; tail -5 /tmp/pull.$$ >&2; return
  fi
  ok "qa:pull" "pulled from the registry"

  python3 -m venv /tmp/qa.$$ >/dev/null 2>&1
  local PY=/tmp/qa.$$/bin/python
  [ -f requirements-dev.txt ] && $PY -m pip install -q -r requirements-dev.txt >/tmp/qpip.$$ 2>&1
  $PY -m pip install -q pytest requests >>/tmp/qpip.$$ 2>&1
  if ! $PY -c 'import pytest, requests' 2>/dev/null; then
    bad "qa:install" "the suite's dependencies do not install"; tail -10 /tmp/qpip.$$ >&2; return
  fi
  ok "qa:install" "the suite's dependencies install"

  export COMPOSE_PROJECT_NAME="qa-verify-$$" QA_IMAGE="$ref" QA_PORT="$PORT"
  if ! docker compose -f "$QA_COMPOSE" up -d --wait --wait-timeout 120 >/tmp/qup.$$ 2>&1; then
    bad "qa:up" "the stack does not come up healthy"; tail -15 /tmp/qup.$$ >&2
    docker compose -f "$QA_COMPOSE" down -v >/dev/null 2>&1
    return
  fi
  ok "qa:up" "the stack is up and healthy on $BASE"

  if QA_BASE_URL="$BASE" $PY -m pytest qa -q >/tmp/qpt.$$ 2>&1; then
    local n
    n=$(grep -oE '[0-9]+ passed' /tmp/qpt.$$ | head -1 | grep -oE '[0-9]+')
    ok "qa:runs" "${n:-?} scenario(s) green against the image your pipeline published"
  else
    bad "qa:runs" "the suite fails against the image your own pipeline published"
    tail -20 /tmp/qpt.$$ >&2
  fi

  docker compose -f "$QA_COMPOSE" down -v >/dev/null 2>&1
  rm -rf /tmp/qa.$$ /tmp/qpip.$$ /tmp/qpt.$$ /tmp/pull.$$ /tmp/qup.$$
}
