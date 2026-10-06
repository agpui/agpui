#!/usr/bin/env bash
# Linux counterpart of probe_dump.ps1: capture a core dump of a live process via gcore (gdb).
# Note: may require ptrace permissions (kernel.yama.ptrace_scope) and same-user or root.
# Usage: bash probe_dump.sh <pid> [outfile_prefix]   (default prefix: probe_dump_<pid>, writes <prefix>.<pid>)
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: probe_dump.sh <pid> [outfile_prefix]"; exit 2; }

PID="$1"
PREFIX="${2:-probe_dump_$PID}"

command -v gcore >/dev/null 2>&1 || { echo "RED: gcore not found (install gdb)"; exit 3; }

gcore -o "$PREFIX" "$PID"
echo "dump ok: $PREFIX.$PID"
