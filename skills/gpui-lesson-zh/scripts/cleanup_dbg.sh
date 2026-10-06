#!/usr/bin/env bash
# Remove all [DBG-set] diagnostic lines from the given files (Phase 6 cleanup).
# After cleanup, verify with a grep count back to zero.
# Usage: bash cleanup_dbg.sh <file> [file...]
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: cleanup_dbg.sh <file> [file...]"; exit 2; }

MARKER='[DBG-set]'
total=0
for f in "$@"; do
  before=$(wc -l < "$f")
  # fixed-string match so [] is literal, same criterion as cleanup_dbg.ps1
  grep -vF "$MARKER" "$f" > "$f.tmp" || true
  mv "$f.tmp" "$f"
  after=$(wc -l < "$f")
  removed=$((before - after))
  echo "$f removed: $removed"
  total=$((total + removed))
done
echo "total removed: $total"
