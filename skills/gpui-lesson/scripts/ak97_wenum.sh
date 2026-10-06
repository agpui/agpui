#!/usr/bin/env bash
# Linux counterpart of ak97_wenum.ps1: enumerate visible top-level windows of a PID.
# Requires X11 tooling (wmctrl or xdotool); Wayland exposes no global window list by design.
# Usage: bash ak97_wenum.sh <pid>
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: ak97_wenum.sh <pid>"; exit 2; }
PID="$1"

if command -v wmctrl >/dev/null 2>&1; then
  # wmctrl -lp: winid, desktop, pid, host, title...
  wmctrl -lp | awk -v p="$PID" '
    $3 == p {
      title = ""
      for (i = 5; i <= NF; i++) title = title (i > 5 ? " " : "") $i
      print "visible: hwnd=" $1 " pid=" $2 " title=[" title "]"
    }'
  count=$(wmctrl -lp | awk -v p="$PID" '$3 == p' | wc -l)
elif command -v xdotool >/dev/null 2>&1; then
  count=0
  for wid in $(xdotool search --onlyvisible --pid "$PID" 2>/dev/null || true); do
    title=$(xdotool getwindowname "$wid" 2>/dev/null || echo '?')
    echo "visible: hwnd=$(printf '0x%08x' "$wid") pid=$PID title=[$title]"
    count=$((count + 1))
  done
else
  echo "RED: neither wmctrl nor xdotool found (X11 required; Wayland exposes no global window list)"
  exit 3
fi
echo "visible_window_count=$count"
