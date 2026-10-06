#!/usr/bin/env bash
# Linux counterpart of probe_hung.ps1: process-level responsiveness probe.
# LIMITATION: Linux (X11/Wayland) exposes no GUI-hang state equivalent to
# IsHungAppWindow, so the red/green criterion degrades to process liveness +
# uninterruptible (D-state) thread detection, which usually indicates stuck
# I/O or lock waits on the real Windows build this skill targets.
# Usage: bash probe_hung.sh <process-name>   (default: AK97)
set -euo pipefail

NAME="${1:-AK97}"

if ! pgrep -x "$NAME" >/dev/null 2>&1; then
  echo "RED: no $NAME process"
  exit 2
fi

# per-thread kernel state from /proc/<pid>/task/<tid>/stat (field 3)
thread_states() {
  local pid
  for pid in $(pgrep -x "$NAME"); do
    cat /proc/"$pid"/task/*/stat 2>/dev/null | awk '{print $3}'
  done
}

for pid in $(pgrep -x "$NAME"); do
  echo "pid=$pid"
  thread_states | sort | uniq -c | awk '{printf "  state=%s threads=%s\n", $2, $1}'
done

dcount=$(thread_states | grep -c '^D' || true)
if [ "$dcount" -gt 0 ]; then
  echo "VERDICT: RED $dcount thread(s) in uninterruptible sleep (D)"
  exit 1
fi
echo "VERDICT: GREEN no D-state threads (GUI-hang detection not available on Linux)"
exit 0
