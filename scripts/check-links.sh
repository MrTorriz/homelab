#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# check-links.sh — verify relative links in tracked Markdown files
#
#   1. Every `](path)` and `<img src="path">` outside fenced code blocks
#      must resolve to an existing file, relative to the .md file.
#      http(s):, mailto: and pure #anchors are skipped; #fragments are
#      stripped before the existence test.
#   2. Every file under docs/img/ must be referenced from some .md file.
# Exit 1 with a list of failures. Run from the repo root (CI does).
# ─────────────────────────────────────────────────────────────
set -uo pipefail

fail=0
referenced=()

while IFS= read -r md; do
  dir=$(dirname "$md")
  # strip fenced blocks, then pull link/img targets one per line
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    case "$target" in
      http://*|https://*|mailto:*|\#*) continue ;;
    esac
    target="${target%%#*}"
    [[ -z "$target" ]] && continue
    if [[ ! -e "$dir/$target" ]]; then
      echo "BROKEN  $md -> $target"
      fail=1
    else
      referenced+=("$(realpath --relative-to=. "$dir/$target")")
    fi
  done < <(awk '/^```/{f=!f; next} !f' "$md" \
           | grep -oE '\]\([^) ]+\)|<img[^>]+src="[^"]+"' \
           | sed -E 's/^\]\(([^)]+)\)$/\1/; s/^<img.*src="([^"]+)".*$/\1/')
done < <(git ls-files '*.md')

while IFS= read -r img; do
  hit=0
  for r in "${referenced[@]}"; do
    [[ "$r" == "$img" ]] && { hit=1; break; }
  done
  if (( hit == 0 )); then
    echo "ORPHAN  $img (not referenced from any .md)"
    fail=1
  fi
done < <(git ls-files 'docs/img/*')

(( fail == 0 )) && echo "check-links: OK"
exit "$fail"
