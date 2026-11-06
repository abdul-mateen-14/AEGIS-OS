#!/usr/bin/env bash
# Stages Aegis first-party app .deb files into live-build's auto-install dir.
#
# Sources, in order:
#   1. env AEGIS_APPS_DEB_URLS   (repo *variable*, newline-separated URLs — CI)
#   2. debian-live/app-deb-urls.txt (one URL per line, '#' comments — local)
#
# Files land in debian-live/config/packages.chroot/ which live-build installs
# into the image automatically. See docs/APP-SLOTS.md for the three expected
# apps: AEGIS Browser, OS Cloud, CoreX.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/debian-live/config/packages.chroot"
mkdir -p "$DEST"

count=0

fetch() {
    local url="$1"
    count=$((count + 1))
    local name
    name="$(basename "${url%%\?*}")"
    case "$name" in
        *.deb) ;;
        *) name="aegis-app-${count}.deb" ;;
    esac
    echo "Fetching: $url -> $name"
    curl -fSL --retry 3 --retry-delay 2 -o "$DEST/$name" "$url"
    if ! dpkg-deb -I "$DEST/$name" >/dev/null 2>&1; then
        echo "WARNING: $name is not a valid .deb package — removing"
        rm -f "$DEST/$name"
        return 1
    fi
}

if [ -n "${AEGIS_APPS_DEB_URLS:-}" ]; then
    while IFS= read -r url; do
        [ -n "$url" ] && fetch "$url" || true
    done <<< "$AEGIS_APPS_DEB_URLS"
fi

URLS_FILE="$ROOT/debian-live/app-deb-urls.txt"
if [ -f "$URLS_FILE" ]; then
    while IFS= read -r url || [ -n "$url" ]; do
        if [ -z "$url" ] || [[ "$url" =~ ^# ]]; then continue; fi
        fetch "$url" || true
    done < "$URLS_FILE"
fi

echo "--- staged packages.chroot ---"
ls -la "$DEST" || true
