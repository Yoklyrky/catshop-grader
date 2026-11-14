#!/usr/bin/env bash
#
# section: qa — an address it can reach.
#
# A unit test can pass on a laptop. An AQA suite needs something running. So
# this section does what lab 5 will do for real: it pulls the image the pipeline
# published, starts it, points the student's own suite at it, and requires the
# suite to pass against bytes it did not build.

WF=../.github/workflows
ACT=../.github/actions
REF_FILE=published.txt

section_run() {
  sect "the suite exists, and it is a suite of the right kind"
  if [ ! -d qa ]; then
    bad "qa:suite" "no qa/ folder — the AQA suite lives beside the lab, not inside tests/"; return
  fi
  local files
  files=$(find qa -name 'test_*.py' | wc -l | tr -d ' ')
  [ "$files" -ge 1 ] && ok "qa:suite" "$files QA file(s) under qa/" \
                     || { bad "qa:suite" "no test_*.py under qa/"; return; }

  if grep -rqE '^(import|from) +app|test_client\(' qa/ 2>/dev/null; then
    bad "qa:blackbox" "the suite imports the app or uses Flask's test client — that is a unit test, not AQA"
  else
    ok "qa:blackbox" "nothing in qa/ imports the app — it drives it from outside"
  fi

  grep -rqE 'requests\.|httpx\.|urllib|http\.client' qa/ 2>/dev/null \
    && ok  "qa:http" "the suite talks HTTP" \
    || bad "qa:http" "nothing in qa/ makes an HTTP call — what is it driving?"

  if grep -rqE 'environ|getenv' qa/ 2>/dev/null; then
    ok "qa:configurable" "the address comes from the environment"
  else
    bad "qa:configurable" "the base URL is hardcoded — lab 5 points this same suite at three environments"
  fi

  sect "where it sits in the pipeline"
  local WFR
  WFR=$(python3 "$(dirname "${BASH_SOURCE[0]}")/../read_workflows.py" "$WF" "$ACT" 2>/dev/null)
  if [ -z "$WFR" ]; then
    bad "qa:gate" "the workflows do not parse, so the gate cannot be read"
  else
    grep -q '^GATE yes' <<<"$WFR" \
      && ok  "qa:gate" "shipping depends on the QA job — a red suite cannot promote" \
      || bad "qa:gate" "nothing depends on the QA job, so a red suite changes nothing about what ships"

    grep -q '^QADIGEST yes' <<<"$WFR" \
      && ok  "qa:digest" "the QA job is given a digest" \
      || bad "qa:digest" "the QA job is not given a digest — a tag can move between the test and the promotion"

    grep -q '^QALATEST yes' <<<"$WFR" \
      && bad "qa:latest" "':latest' appears on the QA path — that is the one tag that can change under you" \
      || ok  "qa:latest" "no ':latest' on the QA path"

    grep -q '^QASUMMARY yes' <<<"$WFR" \
      && ok   "qa:report" "the QA job writes to \$GITHUB_STEP_SUMMARY" \
      || warn "qa:report" "the QA job reports only into the log — one summary line is what a reviewer reads"
  fi

  run_the_suite_against_the_published_image
}

run_the_suite_against_the_published_image() {
  sect "the suite, against the published image"
  need_file "$REF_FILE"
  [ -f "$REF_FILE" ] || return

  local ref
  ref=$(tr -d ' \t\r\n' < "$REF_FILE")
  case "$ref" in
    *@sha256:*) ok  "qa:ref" "pinned by digest" ;;
    "")         bad "qa:ref" "$REF_FILE is empty"; return ;;
    *)          bad "qa:ref" "that is not a digest reference: $ref"; return ;;
  esac

  docker rm -f "$IMG" >/dev/null 2>&1 || true
  if ! docker pull -q "$ref" >/tmp/pull.$$ 2>&1; then
    bad "qa:pull" "cannot pull it — is the package public?"; tail -5 /tmp/pull.$$ >&2; return
  fi
  ok "qa:pull" "pulled from the registry"

  if ! docker run -d --name "$IMG" -p "${PORT}:8080" "$ref" >/dev/null 2>&1; then
    bad "qa:start" "the published image does not start"; docker logs "$IMG" 2>&1 | tail -10 >&2; return
  fi
  wait_up 60 && ok "qa:start" "it is up on $BASE" \
              || { bad "qa:start" "no answer on $BASE/health after 60s"; docker logs "$IMG" 2>&1 | tail -10 >&2; return; }

  python3 -m venv /tmp/qa.$$ >/dev/null 2>&1
  local PY=/tmp/qa.$$/bin/python
  if [ -f requirements-dev.txt ]; then
    $PY -m pip install -q -r requirements-dev.txt >/tmp/qpip.$$ 2>&1
  fi
  $PY -m pip install -q pytest requests >>/tmp/qpip.$$ 2>&1
  if ! $PY -c 'import pytest, requests' 2>/dev/null; then
    bad "qa:install" "the suite's dependencies do not install"; tail -10 /tmp/qpip.$$ >&2; return
  fi
  ok "qa:install" "the suite's dependencies install"

  # every name the suite might read the address from, set to the same value
  if QA_BASE_URL="$BASE" BASE_URL="$BASE" APP_URL="$BASE" APP_HOST="$BASE" \
     $PY -m pytest qa -q >/tmp/qpt.$$ 2>&1; then
    local n
    n=$(grep -oE '[0-9]+ passed' /tmp/qpt.$$ | head -1 | grep -oE '[0-9]+')
    ok "qa:runs" "${n:-?} scenario(s) green against the published image"
    [ "${n:-0}" -ge 3 ] && ok "qa:count" "$n scenarios" \
                        || warn "qa:count" "only ${n:-0} — three is the floor for a suite that gates a release"
  else
    bad "qa:runs" "the suite fails against the image your own pipeline published"
    tail -20 /tmp/qpt.$$ >&2
  fi
  rm -rf /tmp/qa.$$ /tmp/qpip.$$ /tmp/qpt.$$ /tmp/pull.$$
}
