#!/usr/bin/env bash
#
# section: cache — both stores, and the minutes.
#
# Lab 2 rehearsed this as a bonus. Here it is required, and it is marked on the
# saving rather than on the YAML: the entries have to exist in the repository's
# cache, and the two run URLs in CACHE.md have to be real runs whose real
# durations show the speedup that was written down.

WF=../.github/workflows

section_run() {
  sect "both caches are configured"
  local wfs text
  wfs=$(ls $WF/*.yml $WF/*.yaml 2>/dev/null)
  [ -n "$wfs" ] || { bad "cache:file" "no workflow under .github/workflows/"; return; }
  text=$(cat $wfs)

  if grep -qE 'actions/cache@|cache: *(pip|npm|yarn|poetry|maven|gradle)' <<<"$text"; then
    ok "cache:deps" "a dependency cache is configured"
  else
    bad "cache:deps" "no actions/cache and no setup-* cache: key — the packages download on every run"
  fi

  if grep -q 'hashFiles(' <<<"$text"; then
    ok "cache:key" "the key contains hashFiles()"
  elif grep -qE 'cache: *(pip|npm|yarn|poetry|maven|gradle)' <<<"$text"; then
    ok "cache:key" "a setup-* action, which keys on the lockfile for you"
  else
    bad "cache:key" "a key with no hashFiles() never changes, so the cache is never refreshed"
  fi

  if grep -q 'restore-keys' <<<"$text"; then
    ok "cache:prefix" "restore-keys gives a prefix fallback, so a changed lockfile still starts warm"
  elif grep -qE 'cache: *(pip|npm|yarn|poetry|maven|gradle)' <<<"$text"; then
    warn "cache:prefix" "setup-* manages its own fallback; write your own key once to see the prefix work"
  else
    bad "cache:prefix" "no restore-keys — one changed dependency throws the whole cache away"
  fi

  if grep -q 'cache-from:' <<<"$text" && grep -q 'cache-to:' <<<"$text"; then
    ok "cache:layers" "the layer cache is configured as well as the dependency cache"
  else
    bad "cache:layers" "no cache-from/cache-to — the docker build rebuilds every layer every run"
  fi

  grep -q 'mode=max' <<<"$text" \
    && ok  "cache:mode" "mode=max — the intermediate stages are cached too, not only the last one" \
    || bad "cache:mode" "cache-to without mode=max caches only the final stage"

  local builds
  builds=$(grep -cE 'docker/build-push-action|docker buildx build' <<<"$text")
  if [ "${builds:-0}" -ge 2 ] && ! grep -q 'scope=' <<<"$text"; then
    warn "cache:scope" "$builds builds and no scope= — two builds sharing one scope evict each other"
  fi

  sect "the Dockerfile is ordered for it"
  if [ -f Dockerfile ]; then
    local req app
    req=$(grep -n -m1 -E '^[[:space:]]*COPY .*requirements' Dockerfile | cut -d: -f1)
    app=$(grep -n -m1 -E '^[[:space:]]*COPY \.|^[[:space:]]*COPY app' Dockerfile | cut -d: -f1)
    if [ -n "$req" ] && [ -n "$app" ] && [ "$req" -lt "$app" ]; then
      ok "cache:order" "requirements are copied and installed before the source"
    elif [ -n "$req" ] && [ -n "$app" ]; then
      bad "cache:order" "the source is copied before the requirements, so every edit invalidates the install"
    elif [ -z "$req" ] && grep -q 'pip install' Dockerfile; then
      bad "cache:order" "the requirements are never copied on their own — with COPY . . the install layer dies on every source edit"
    else
      warn "cache:order" "could not read the COPY order out of the Dockerfile"
    fi
  else
    warn "cache:order" "no Dockerfile in this folder"
  fi

  caches_exist
  measured
}

# A `cache:` block that saved nothing is still perfect YAML, so ask the API:
# list the entries, take the newest, fetch it again by its own key and ref, and
# require the same id back.
caches_exist() {
  sect "the caches exist, not just the YAML"
  . "$(dirname "${BASH_SOURCE[0]}")/../api.sh"
  if ! api_ready; then
    warn "cache:api" "no token or repository — run this in Actions to grade it"; return
  fi

  local body count id key ref size keys
  body=$(gh_api --get --data-urlencode "per_page=100" "$API/actions/caches")
  case "$(api_code)" in
    200) ok "cache:api" "the cache API answered" ;;
    403) warn "cache:api" "403 — the grading job needs permissions: actions: read"; return ;;
    *)   warn "cache:api" "the cache API answered $(api_code)"; return ;;
  esac

  count=$(jq_py "$body" "len(d.get('actions_caches',[]))")
  if [ "${count:-0}" -eq 0 ]; then
    bad "cache:entry" "this repository holds no cache entries — the save step never ran, or the job died before it"
    return
  fi
  ok "cache:entry" "$count cache entr$([ "$count" = 1 ] && echo y || echo ies)"

  id=$(jq_py  "$body" "sorted(d['actions_caches'], key=lambda c: c.get('created_at',''))[-1]['id']")
  key=$(jq_py "$body" "sorted(d['actions_caches'], key=lambda c: c.get('created_at',''))[-1].get('key','')")
  ref=$(jq_py "$body" "sorted(d['actions_caches'], key=lambda c: c.get('created_at',''))[-1].get('ref','')")
  size=$(jq_py "$body" "sorted(d['actions_caches'], key=lambda c: c.get('created_at',''))[-1].get('size_in_bytes',0)")
  [ -n "$key" ] && ok "cache:named" "newest is '$key' on $ref" \
                || { bad "cache:named" "an entry with no key"; return; }

  local again aid
  again=$(gh_api --get --data-urlencode "key=$key" --data-urlencode "ref=$ref" "$API/actions/caches")
  if [ "$(api_code)" = 200 ]; then
    aid=$(jq_py "$again" "next((str(e['id']) for e in d.get('actions_caches',[]) if str(e.get('id'))=='$id'), '')")
    [ -n "$aid" ] && ok  "cache:byid" "fetched again by its own key and ref — same entry, id $aid" \
                  || bad "cache:byid" "the entry does not come back when asked for by its own key and ref"
  else
    warn "cache:byid" "the filtered query answered $(api_code)"
  fi

  if [ "${size:-0}" -gt 1024 ]; then
    ok "cache:size" "$(( size / 1024 )) KB stored"
  else
    bad "cache:size" "the newest entry holds ${size:-0} bytes — that is an empty cache"
  fi

  # two stores, not one: buildkit writes its own entries, with keys nobody typed
  keys=$(jq_py "$body" "len(set(e.get('key','').split('-')[0] for e in d.get('actions_caches',[])))")
  if [ "${keys:-1}" -ge 2 ]; then
    ok "cache:both" "$keys different key families — the dependency cache and the layer cache are separate stores"
  else
    warn "cache:both" "every entry shares one key family; the layer cache may not have saved anything yet"
  fi
}

# The numbers. Two timings, a stated delta, and two run URLs the API can confirm.
measured() {
  sect "and it was measured"
  need_file CACHE.md
  [ -f CACHE.md ] || return

  local times
  times=$(grep -coE '[0-9]+([.,][0-9]+)? *(m|min|mins|minutes|s|sec|secs|seconds)\b' CACHE.md)
  [ "${times:-0}" -ge 2 ] && ok "cache:measured" "a cold time and a warm time are written down" \
                          || bad "cache:measured" "CACHE.md needs both runs timed — cold and warm"

  grep -qiE 'saved|faster|delta|difference|-[0-9]' CACHE.md \
    && ok  "cache:minutes" "the saving is stated, not left to be worked out" \
    || bad "cache:minutes" "say what the cache saved — the delta is the point of the section"

  local ids
  ids=$(grep -oE 'actions/runs/[0-9]+' CACHE.md | grep -oE '[0-9]+' | sort -u)
  if [ -z "$ids" ]; then
    bad "cache:evidence" "no run URLs in CACHE.md — paste the cold run and the warm run"
    return
  fi
  ok "cache:evidence" "$(wc -w <<<"$ids" | tr -d ' ') run URL(s) pasted"

  . "$(dirname "${BASH_SOURCE[0]}")/../api.sh"
  api_ready || { warn "cache:runs" "no token — the pasted runs could not be checked"; return; }

  local id secs durations=()
  for id in $ids; do
    local run
    run=$(gh_api "$API/actions/runs/$id")
    if [ "$(api_code)" != 200 ]; then
      warn "cache:runs" "run $id answered $(api_code) — is it a run of this repository?"; continue
    fi
    secs=$(python3 - "$run" <<'PY' 2>/dev/null
import json, sys, datetime
d = json.loads(sys.argv[1])
f = "%Y-%m-%dT%H:%M:%SZ"
try:
    a = datetime.datetime.strptime(d["run_started_at"], f)
    b = datetime.datetime.strptime(d["updated_at"], f)
    print(int((b - a).total_seconds()))
except Exception:
    print("")
PY
)
    [ -n "$secs" ] && durations+=("$secs")
  done

  if [ "${#durations[@]}" -lt 2 ]; then
    warn "cache:runs" "fewer than two of the pasted runs could be read back"
    return
  fi

  local cold warm
  cold=$(printf '%s\n' "${durations[@]}" | sort -n | tail -1)
  warm=$(printf '%s\n' "${durations[@]}" | sort -n | head -1)
  if [ "$cold" -gt 0 ] && [ $(( (cold - warm) * 100 / cold )) -ge 20 ]; then
    ok "cache:runs" "the runs themselves say ${cold}s cold against ${warm}s warm"
  else
    bad "cache:runs" "the pasted runs took ${cold}s and ${warm}s — that is not a cache working, whatever CACHE.md says"
  fi
}
