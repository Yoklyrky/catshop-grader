#!/usr/bin/env bash
#
# section: cache — bonus. Keyed on something that changes, measured, and proved
# to exist via the Actions cache API.

section_run() {
  sect "a cache is configured"
  local wfs text
  wfs=$(ls ../.github/workflows/*.yml ../.github/workflows/*.yaml 2>/dev/null)
  [ -n "$wfs" ] || { bad "cache:file" "no workflow to read"; return; }
  text=$(cat $wfs)

  if grep -q 'actions/cache@\|cache: *pip\|cache: *npm\|cache-from:' <<<"$text"; then
    ok "cache:present" "a cache is configured"
  else
    bad "cache:present" "no actions/cache, no setup-* cache: key, no buildx cache-from"
    return
  fi

  sect "it is keyed on something that changes"
  if grep -q 'hashFiles(' <<<"$text"; then
    ok "cache:key" "the key contains hashFiles()"
  elif grep -qE 'cache: *(pip|npm|yarn|maven|gradle)' <<<"$text"; then
    ok "cache:key" "a setup-* action, which keys on the lockfile for you"
  else
    bad "cache:key" "a key with no hashFiles() never changes, so the cache is never refreshed"
  fi

  if grep -q 'cache-to:.*mode=max' <<<"$text"; then
    ok "cache:mode" "mode=max — intermediate stages are cached too"
  elif grep -q 'cache-from:' <<<"$text"; then
    warn "cache:mode" "layer cache without mode=max caches only the final stage"
  fi

  cache_exists_in_the_repository

  sect "and it was measured"
  need_file CACHE.md
  [ -f CACHE.md ] || return
  local times
  times=$(grep -coE '[0-9]+ *(m|min|s|sec)' CACHE.md)
  if [ "$times" -ge 2 ]; then
    ok "cache:measured" "two timings written down"
  else
    bad "cache:measured" "CACHE.md needs a cold run and a warm run, with both times"
  fi
}

# A `cache:` block that saved nothing is still perfect YAML, so ask the API:
# list the entries, take the newest, fetch it again by its own key and ref, and
# require the same id back. Needs `actions: read`; without it, WARN not FAIL.
cache_exists_in_the_repository() {
  sect "the cache exists, not just the YAML"

  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  local repo="${GITHUB_REPOSITORY:-}"
  if [ -z "$token" ] || [ -z "$repo" ]; then
    warn "cache:api" "no token or repository in the environment — run this in Actions to grade it"
    return
  fi

  local api="https://api.github.com/repos/$repo/actions/caches"
  local body code
  body=$(curl -sS -w '\n%{http_code}' -m 20 \
          -H "Authorization: Bearer $token" \
          -H "Accept: application/vnd.github+json" \
          -H "X-GitHub-Api-Version: 2022-11-28" \
          "$api?per_page=100" 2>/dev/null)
  code=$(tail -1 <<<"$body"); body=$(sed '$d' <<<"$body")

  case "$code" in
    200) ok "cache:api" "the cache API answered" ;;
    403) warn "cache:api" "403 — the grading job needs permissions: actions: read"; return ;;
    *)   warn "cache:api" "the cache API answered $code"; return ;;
  esac

  local line id key ref size count
  line=$(python3 - "$body" <<'PY' 2>/dev/null
import json, sys
try:
    entries = json.loads(sys.argv[1]).get("actions_caches", [])
except Exception:
    entries = []
if entries:
    e = sorted(entries, key=lambda c: c.get("created_at", ""))[-1]
    print("\t".join(str(e.get(k, "")) for k in ("id", "key", "ref", "size_in_bytes")))
print(f"COUNT\t{len(entries)}")
PY
)
  count=$(sed -n 's/^COUNT\t//p' <<<"$line")
  IFS=$'\t' read -r id key ref size <<<"$(grep -v '^COUNT' <<<"$line" | head -1)"

  if [ "${count:-0}" -eq 0 ]; then
    bad "cache:entry" "the repository has no cache entries — the save step never ran, or the job failed before it"
    return
  fi
  ok "cache:entry" "${count} cache entr$([ "$count" = 1 ] && echo y || echo ies) in this repository"

  [ -n "$key" ] && ok "cache:named" "newest is '$key' on $ref" \
                || { bad "cache:named" "an entry with no key"; return; }

  local again aid acode
  again=$(curl -sS -w '\n%{http_code}' -m 20 \
           -H "Authorization: Bearer $token" \
           -H "Accept: application/vnd.github+json" \
           -H "X-GitHub-Api-Version: 2022-11-28" \
           --get --data-urlencode "key=$key" --data-urlencode "ref=$ref" \
           "$api" 2>/dev/null)
  acode=$(tail -1 <<<"$again"); again=$(sed '$d' <<<"$again")
  if [ "$acode" = 200 ]; then
    aid=$(python3 - "$again" "$id" <<'PY' 2>/dev/null
import json, sys
try:
    entries = json.loads(sys.argv[1]).get("actions_caches", [])
except Exception:
    entries = []
print(next((str(e["id"]) for e in entries if str(e.get("id")) == sys.argv[2]), ""))
PY
)
    [ -n "$aid" ] && ok "cache:byid" "fetched again by key and ref — same entry, id $aid" \
                  || bad "cache:byid" "the entry does not come back when asked for by its own key and ref"
  else
    warn "cache:byid" "the filtered query answered $acode"
  fi

  if [ "${size:-0}" -gt 1024 ]; then
    ok "cache:size" "$(( size / 1024 )) KB stored"
  else
    bad "cache:size" "the entry holds ${size:-0} bytes — that is an empty cache"
  fi
}
