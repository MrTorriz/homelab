#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# check-facts.sh — keep the headline numbers consistent across docs
#
# Reads `<!-- facts: containers=N snapshot=YYYY-MM-DD ... -->` from
# docs/metrics.md and asserts the README badge, README snapshot date and
# docker/README.md agree. Then greps tracked text for strings that only
# existed in earlier snapshots. Exit 1 on any mismatch.
# ─────────────────────────────────────────────────────────────
set -uo pipefail

facts=$(grep -m1 -oE '<!-- facts:[^>]*-->' docs/metrics.md)
containers=$(sed -nE 's/.*containers=([0-9]+).*/\1/p' <<<"$facts")
snapshot=$(sed -nE 's/.*snapshot=([0-9-]+).*/\1/p' <<<"$facts")
fail=0

[[ -n "$containers" && -n "$snapshot" ]] || { echo "no facts comment in docs/metrics.md"; exit 1; }

grep -q "containers-${containers}-" README.md      || { echo "README badge is not containers-${containers}"; fail=1; }
grep -q "$snapshot" README.md                      || { echo "README lacks snapshot date $snapshot"; fail=1; }
grep -q "${containers} containers" docker/README.md || { echo "docker/README.md lacks '${containers} containers'"; fail=1; }

# strings from earlier snapshots that must not come back
stale=('~50' '41/41' '~40 services' '8 GB cap' 'Scaphandre measure' 'zero open inbound' 'Zero open inbound' '~20 ntfy' 'about 20 ntfy')
for s in "${stale[@]}"; do
  if hits=$(git grep -n -F -- "$s" -- '*.md' '*.yml' '*.yaml' '*.svg' ':!scripts/check-facts.sh'); then
    echo "STALE   '$s':"; echo "$hits" | sed 's/^/        /'
    fail=1
  fi
done

(( fail == 0 )) && echo "check-facts: OK (containers=$containers snapshot=$snapshot)"
exit "$fail"
