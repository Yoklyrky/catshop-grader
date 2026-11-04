#!/usr/bin/env bash
#
# cache-api.sh — the cache section's API path, with curl stubbed. Five payloads,
# five verdicts.
#
#   ./tests/cache-api.sh happy | empty | tiny | noperm | mismatch
#   for c in happy empty tiny noperm mismatch; do ./tests/cache-api.sh $c; done
#
# happy     two entries, the newest comes back by key and ref
# empty     no caches at all              -> FAIL cache:entry
# tiny      an 11-byte entry              -> FAIL cache:size
# noperm    403, no actions: read         -> WARN, never FAIL
# mismatch  the id does not come back     -> FAIL cache:byid
GR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JSON=0; KEEP=0; PORT=8080
. "$GR/common/lib.sh"
. "$GR/lab-02/verify/sections/cache.sh"

export GH_TOKEN=fake GITHUB_REPOSITORY=student/catshop-labs

LIST='{"total_count":2,"actions_caches":[
 {"id":17,"ref":"refs/heads/lab-02","key":"pip-Linux-aaa111","version":"v1","last_accessed_at":"2026-11-03T10:00:00Z","created_at":"2026-11-03T09:00:00Z","size_in_bytes":48210000},
 {"id":41,"ref":"refs/heads/lab-02","key":"pip-Linux-bbb222","version":"v1","last_accessed_at":"2026-11-04T10:00:00Z","created_at":"2026-11-04T09:00:00Z","size_in_bytes":51200}]}'
EMPTY='{"total_count":0,"actions_caches":[]}'
TINY='{"total_count":1,"actions_caches":[{"id":9,"ref":"refs/heads/lab-02","key":"pip-Linux-ccc","created_at":"2026-11-04T09:00:00Z","size_in_bytes":11}]}'

case "$1" in
  happy)   BODY="$LIST";  CODE=200; SECOND="$LIST" ;;
  empty)   BODY="$EMPTY"; CODE=200; SECOND="$EMPTY" ;;
  tiny)    BODY="$TINY";  CODE=200; SECOND="$TINY" ;;
  noperm)  BODY='{"message":"Resource not accessible by integration"}'; CODE=403; SECOND="$BODY" ;;
  mismatch) BODY="$LIST"; CODE=200; SECOND='{"total_count":0,"actions_caches":[]}' ;;
esac

# curl runs inside $( ), a subshell — the counter has to live in a file
STATE=$(mktemp); echo 0 > "$STATE"
curl() {
  local n; n=$(( $(cat "$STATE") + 1 )); echo "$n" > "$STATE"
  if [ "$n" = 1 ]; then printf '%s\n%s\n' "$BODY" "$CODE"
  else                  printf '%s\n%s\n' "$SECOND" "$CODE"; fi
}
cache_exists_in_the_repository
echo "--- pass=$PASS fail=$FAIL warn=$WARN"
