#!/usr/bin/env bash
# Syncs design assets (theme/, calamares/, shell/packaging/) into the
# live-build includes tree. Sources stay in git; includes carry the binaries.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INC="$ROOT/debian-live/config/includes.chroot"

mkdir -p \
    "$INC/usr/share/wallpapers/aegis" \
    "$INC/usr/share/plymouth/themes/aegis" \
    "$INC/usr/share/plymouth/themes/aegis-mark" \
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

# W14 — the mark + progress-line splash on the two-step C plugin (a C
# renderer that paints on this machine; the script theme rendered black in
# every boot test). Stale files are wiped first — the v0.6.13 script
# plugin's assets (aegis-mark.script, fill.png, track.png) must not
# survive into the ISO when the theme stops referencing them.
rm -f "$INC/usr/share/plymouth/themes/aegis-mark/"*
cp "$ROOT"/theme/plymouth-mark/* "$INC/usr/share/plymouth/themes/aegis-mark/"

# SDDM greeter theme — the glass login screen. The wallpaper doubles as
# the greeter background (Aurora Ink) so boot → login → desktop reads as
# one continuous surface. B3 — the greeter also carries the Aegis mark
# (the transparent plymouth watermark cutout) with the splash's progress
# device, so the logo survives past the boot splash.
cp "$ROOT"/theme/sddm/aegis/Main.qml \
   "$ROOT"/theme/sddm/aegis/theme.conf \
   "$ROOT"/theme/sddm/aegis/metadata.desktop \
   "$INC/usr/share/sddm/themes/aegis/"
cp "$ROOT"/theme/plymouth-mark/watermark.png \
   "$INC/usr/share/sddm/themes/aegis/mark.png"
cp "$ROOT"/theme/wallpapers/aurora-ink.jpg \
   "$INC/usr/share/sddm/themes/aegis/background.jpg"

# Color schemes
cp "$ROOT"/theme/colors/*.colors "$INC/usr/share/color-schemes/"

# First-party desktop entries (the rebranded calamares.desktop in here
# overwrites the package's stock file — includes land after packages)
cp "$ROOT"/theme/desktop-entries/*.desktop "$INC/usr/share/applications/"

# Shell config (wallpaper + default dock: Files, Terminal, AEGIS Browser,
# OS, CoreX, | , Settings, Trash — installed apps only, W8/W9)
cp "$ROOT"/shell/packaging/config.json "$INC/usr/share/aegis/shell/config.json"

# Account avatar (Aegis ID rail + lock screen, M2)
cp "$ROOT"/theme/avatar/avatar-alex.png "$INC/usr/share/aegis/avatar/"

# Calamares installer config + Aegis branding
cp "$ROOT"/calamares/settings.conf "$INC/etc/calamares/"
cp "$ROOT"/calamares/modules/*.conf "$INC/etc/calamares/modules/"
cp -r "$ROOT"/calamares/branding/aegis "$INC/usr/share/calamares/branding/"

echo "--- includes.chroot contents ---"
find "$INC" -type f | sed "s|$INC/||" | sort
