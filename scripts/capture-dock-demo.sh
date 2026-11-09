#!/usr/bin/env bash
# Deterministic dock-magnification capture for docs/screenshots.
#
# Why this exists: a screenshot tool cannot "hover" the dock, and grabbing a
# frame mid-motion freezes the wave wherever the springs happen to be (that is
# how 01b-dock-magnify.png ended up asymmetric). This script parks the pointer,
# glides it onto one tile, DWELLS past the spring settle time
# (mass 0.1 · stiffness 170 · damping 13 settles in ~220 ms), then captures.
#
# Usage:  ./capture-dock-demo.sh [tile-center-x] [out.png]
#         ./capture-dock-demo.sh 860 docs/screenshots/v0.4.4/01b-dock-magnify.png
#
# Deps:   ydotool (Wayland) — needs ydotoold running, e.g.
#           sudo systemctl enable --now ydotoold
#         spectacle (KDE) for the capture.
set -euo pipefail

X=${1:-860}     # center x of the tile to magnify (the X icon in the default config)
Y=755           # inside the tray
OUT=${2:-01b-dock-magnify.png}

move() {  # ydotool first (real Wayland pointer), xdotool as fallback
  if command -v ydotool >/dev/null 2>&1; then
    ydotool mousemove -a "$1" "$2"
  else
    xdotool mousemove "$1" "$2"
  fi
}

move 640 400        # 1) park away from the dock — tray at rest
sleep 0.5
move "$X" "$Y"      # 2) glide onto the tile
sleep 0.8           # 3) dwell well past the ~220 ms spring settle
spectacle -b -n -f -o "$OUT"   # 4) capture the settled wave
echo "wrote $OUT"

# Tip — for the ISLAND demo shots you don't need the pointer at all; publish a
# live activity over the session bus (the API you already ship):
#
#   busctl --user call org.aegis.Island /org/aegis/Island \
#          org.aegis.Island.PublishActivity ss"a{sv}" media \
#          0 2 "title" "Aurora Drift" "artist" "Aegis Sound"
#
# Wait ~600 ms for the morph spring (mass 1 · stiffness 420 · damping 28) to
# settle, then spectacle -b -n -f -o 06-island-nowplaying.png
