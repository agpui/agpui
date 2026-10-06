#!/usr/bin/env bash
# Linux counterpart of ak97_cpu_sample.ps1: idle-CPU sampling, normalized by logical core count.
# Per-sample CPU% per PID = delta(utime+stime) jiffies / (interval * CLK_TCK) * 100 / nproc,
# matching the "divide by logical processors" caliber of the PowerShell original.
# Usage: bash ak97_cpu_sample.sh [-n samples] [-i interval_sec] <name> [<name>...]   (defaults: -n 5 -i 2)
set -euo pipefail

SAMPLES=5; INTERVAL=2
while getopts "n:i:" o; do
  case "$o" in
    n) SAMPLES="$OPTARG" ;;
    i) INTERVAL="$OPTARG" ;;
    *) echo "usage: ak97_cpu_sample.sh [-n samples] [-i interval_sec] <name>..."; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || { echo "usage: ak97_cpu_sample.sh [-n samples] [-i interval_sec] <name>..."; exit 2; }

NPROC=$(nproc)
CLK=$(getconf CLK_TCK)
echo "LogicalProcessors=$NPROC"

read_cpu() { awk '{print $14 + $15}' "/proc/$1/stat" 2>/dev/null || echo 0; }

for name in "$@"; do
  pids=$(pgrep -x "$name" || true)
  if [ -z "$pids" ]; then
    echo "$name: not running"
    continue
  fi
  declare -A prev=()
  for pid in $pids; do prev[$pid]=$(read_cpu "$pid"); done
  peak=0
  for ((s = 0; s < SAMPLES; s++)); do
    sleep "$INTERVAL"
    for pid in $pids; do
      cur=$(read_cpu "$pid")
      d=$((cur - ${prev[$pid]:-0}))
      prev[$pid]=$cur
      pct=$(awk -v d="$d" -v i="$INTERVAL" -v clk="$CLK" -v n="$NPROC" \
        'BEGIN { v = (i * clk > 0) ? d / (i * clk) * 100 / n : 0; printf "%.1f", v }')
      if awk -v a="$pct" -v m="$peak" 'BEGIN { exit !(a > m) }'; then peak=$pct; fi
    done
  done
  echo "$name (pids: $(echo $pids | tr '\n' ' ')): PEAK_NORMALIZED=$peak%"
  unset prev
done
