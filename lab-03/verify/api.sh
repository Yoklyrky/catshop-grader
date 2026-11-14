#!/usr/bin/env bash
#
# api.sh — the Actions API, for the three checks that YAML cannot answer.
#
# A workflow file can describe a reusable call, a cache and a cancelled run
# without any of them ever happening. These helpers ask the repository what
# really happened. Without `actions: read` they WARN; they never invent a mark.

API_CODE_FILE="${TMPDIR:-/tmp}/apicode.$$"

api_ready() {           # sets TOKEN, REPO, API. Returns 1 when we cannot ask.
  TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  REPO="${GITHUB_REPOSITORY:-}"
  API="https://api.github.com/repos/$REPO"
  [ -n "$TOKEN" ] && [ -n "$REPO" ]
}

gh_api() {              # gh_api <curl args...> -> body on stdout, code via api_code
  local out
  out=$(curl -sS -w '\n%{http_code}' -m 25 \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$@" 2>/dev/null)
  printf '%s\n' "$(tail -1 <<<"$out")" > "$API_CODE_FILE"
  sed '$d' <<<"$out"
}

api_code() { cat "$API_CODE_FILE" 2>/dev/null; }

jq_py() {               # jq_py <json> <python expression over `d`>
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.loads(sys.argv[1])
except Exception:
    d = {}
print(eval(sys.argv[2], {"d": d, "sorted": sorted, "len": len, "next": next, "str": str}))
PY
}
