#!/usr/bin/env bash
# Linux counterpart of ak97_capture.ps1: full-screen capture to PNG.
# Tries in order: gnome-screenshot > import (ImageMagick) > scrot (X11 tools).
# Usage: bash ak97_capture.sh [outfile.png]   (default: ak97_screen.png in cwd)
set -euo pipefail

OUT="${1:-ak97_screen.png}"

if command -v gnome-screenshot >/dev/null 2>&1; then
  gnome-screenshot -f "$OUT"
elif command -v import >/dev/null 2>&1; then
  import -window root "$OUT"
elif command -v scrot >/dev/null 2>&1; then
  scrot "$OUT"
else
  echo "RED: no screenshot tool found (install gnome-screenshot / imagemagick / scrot)"
  exit 3
fi
echo "saved=$OUT"
