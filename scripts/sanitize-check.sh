#!/usr/bin/env bash
# sanitize-check.sh — local-only PII guard for pre-commit.
#
# Reads patterns line-by-line from .sanitize-patterns (gitignored) and
# fails if any tracked file matches. The patterns file is created from
# .sanitize-patterns.example on first run; entries are operator-private
# and never committed.
#
# Exits 0 if .sanitize-patterns is missing (no-op so a fresh clone
# without operator setup doesn't fail) — but warns to stderr so the
# operator notices.

set -euo pipefail

PATTERNS_FILE="${SANITIZE_PATTERNS_FILE:-.sanitize-patterns}"

if [ ! -f "$PATTERNS_FILE" ]; then
    printf 'sanitize-check: %s missing — skipping. Copy .sanitize-patterns.example to set up.\n' \
        "$PATTERNS_FILE" >&2
    exit 0
fi

# Build alternation from non-blank, non-comment lines.
PATTERNS=$(grep -vE '^\s*(#|$)' "$PATTERNS_FILE" | paste -sd '|' -)

if [ -z "$PATTERNS" ]; then
    printf 'sanitize-check: %s has no patterns.\n' "$PATTERNS_FILE" >&2
    exit 0
fi

# Files to scan = staged files if any, else everything tracked.
if git diff --cached --name-only --diff-filter=ACMRT | grep -q .; then
    mapfile -t FILES < <(git diff --cached --name-only --diff-filter=ACMRT)
else
    mapfile -t FILES < <(git ls-files)
fi

# Always exclude the patterns file itself and this script.
EXCLUDED=("$PATTERNS_FILE" "scripts/sanitize-check.sh")

FOUND=0
for f in "${FILES[@]}"; do
    skip=0
    for x in "${EXCLUDED[@]}"; do
        [ "$f" = "$x" ] && skip=1 && break
    done
    [ "$skip" -eq 1 ] && continue
    [ ! -f "$f" ] && continue
    if grep -EnH -- "$PATTERNS" "$f" 2>/dev/null; then
        FOUND=1
    fi
done

if [ "$FOUND" -eq 1 ]; then
    printf '\nsanitize-check: personal identifiers detected above. Aborting commit.\n' >&2
    exit 1
fi

exit 0
