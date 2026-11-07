#!/usr/bin/env bash
# Syncs design assets (theme/, calamares/, shell/packaging/) into the
# live-build includes tree. Sources stay in git; includes carry the binaries.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INC="$ROOT/debian-live/config/includes.chroot"

mkdir -p \
    "$INC/usr/share/wallpapers/aegis" \
    "$INC/usr/share/plymouth/themes/aegis" \
    "$INC/usr/share/sddm/themes/aegis" \
    "$INC/usr/share/color-schemes" \
    "$INC/usr/share/applications" \
    "$INC/usr/share/aegis/shell" \
    "$INC/usr/share/aegis/avatar" \
    "$INC/etc/calamares/modules" \
    "$INC/usr/share/calamares/branding"

# Default wallpapers (Aurora Ink · Graphite Dune · Neon Coast · Emerald Ridge)
cp "$ROOT"/theme/wallpapers/*.jpg "$INC/usr/share/wallpapers/aegis/"

# Plymouth boot splash (Aegis Mark on true black, hairline progress)
cp "$ROOT"/theme/plymouth/* "$INC/usr/share/plymouth/themes/aegis/"

# SDDM greeter theme — the glass login screen. The wallpaper doubles as
# the greeter background (Aurora Ink) so boot → login → desktop reads as
# one continuous surface.
cp "$ROOT"/theme/sddm/aegis/Main.qml \
   "$ROOT"/theme/sddm/aegis/theme.conf \
   "$ROOT"/theme/sddm/aegis/metadata.desktop \
   "$INC/usr/share/sddm/themes/aegis/"
cp "$ROOT"/theme/wallpapers/aurora-ink.jpg \
   "$INC/usr/share/sddm/themes/aegis/background.jpg"

# Color schemes
cp "$ROOT"/theme/colors/*.colors "$INC/usr/share/color-schemes/"

# First-party desktop entries (the rebranded calamares.desktop in here
# overwrites the package's stock file — includes land after packages)
cp "$ROOT"/theme/desktop-entries/*.desktop "$INC/usr/share/applications/"

# Shell config (wallpaper + default dock: Files, Terminal, AEGIS Browser,
# OS Cloud, CoreX, Settings, | , Trash)
cp "$ROOT"/shell/packaging/config.json "$INC/usr/share/aegis/shell/config.json"

# Account avatar (Aegis ID rail + lock screen, M2)
cp "$ROOT"/theme/avatar/avatar-alex.png "$INC/usr/share/aegis/avatar/"

# Calamares installer config + Aegis branding
cp "$ROOT"/calamares/settings.conf "$INC/etc/calamares/"
cp "$ROOT"/calamares/modules/*.conf "$INC/etc/calamares/modules/"
cp -r "$ROOT"/calamares/branding/aegis "$INC/usr/share/calamares/branding/"

echo "--- includes.chroot contents ---"
find "$INC" -type f | sed "s|$INC/||" | sort
