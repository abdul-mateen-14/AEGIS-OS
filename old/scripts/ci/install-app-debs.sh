#!/usr/bin/env bash
# Stages Aegis first-party app .deb files into live-build's auto-install dir.
#
# Sources, in order:
#   1. env AEGIS_APPS_DEB_URLS   (repo *variable*, newline-separated URLs — CI)
#   2. debian-live/app-deb-urls.txt (one URL per line, '#' comments — local)
#
# Files land in debian-live/config/packages.chroot/ which live-build installs
# into the image automatically. See docs/APP-SLOTS.md for the three expected
# apps: AEGIS Browser, OS (messenger), CoreX.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/debian-live/config/packages.chroot"
mkdir -p "$DEST"

count=0

# Lines accept "URL" or "URL|target-name.deb" (Google Drive URLs have no
# usable basename — strip everything after '?' first, then fall back).
fetch() {
    local url="$1"
    local forced="${1#*|}"
    [ "$forced" = "$1" ] && forced=""
    url="${1%%|*}"
    count=$((count + 1))
    local name
    if [ -n "$forced" ]; then
        name="$forced"
    else
        name="$(basename "${url%%\?*}")"
    fi
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

# "latest:owner/repo" — pick the NEWEST *.deb in a public GitHub repo's
# default branch (W83, "always use latest version"): the contents API is
# version-sorted and the winner is fetched raw. Auth rides GITHUB_TOKEN
# when the runner provides one (the unauthenticated 60/hr pool 403s under
# CI traffic); a failed resolution falls back to the pinned URL on the
# directive ("latest:owner/repo|https://…") and only then warns + skips.
fetch_latest() {
    local repo="$1"
    local fallback="${1#*|}"
    repo="${1%%|*}"
    [ "$fallback" = "$1" ] && fallback=""
    local auth=()
    [ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    local pick
    pick="$(curl -fsSL --retry 3 --retry-delay 2 "${auth[@]}" \
        "https://api.github.com/repos/${repo}/contents/" \
        | python3 -c '
import json, sys
try:
    entries = json.load(sys.stdin)
except Exception:
    sys.exit(0)
names = sorted(
    (e["name"] for e in entries
     if isinstance(e, dict) and e.get("name", "").endswith(".deb")),
    key=lambda n: [int(p) if p.isdigit() else p
                   for p in n.replace("_", ".").split(".")])
print(names[-1] if names else "")')" || true
    if [ -z "$pick" ]; then
        if [ -n "$fallback" ]; then
            echo "WARNING: latest:${repo} unresolved — using the pinned fallback"
            fetch "$fallback"
            return
        fi
        echo "WARNING: no .deb resolvable in ${repo} — slot skipped"
        return 1
    fi
    echo "latest:${repo} -> ${pick}"
    fetch "https://github.com/${repo}/raw/main/${pick}"
}

if [ -n "${AEGIS_APPS_DEB_URLS:-}" ]; then
    while IFS= read -r url; do
        [ -n "$url" ] || continue
        case "$url" in
            latest:*) fetch_latest "${url#latest:}" || true ;;
            *) fetch "$url" || true ;;
        esac
    done <<< "$AEGIS_APPS_DEB_URLS"
fi

URLS_FILE="$ROOT/debian-live/app-deb-urls.txt"
if [ -f "$URLS_FILE" ]; then
    while IFS= read -r url || [ -n "$url" ]; do
        if [ -z "$url" ] || [[ "$url" =~ ^# ]]; then continue; fi
        case "$url" in
            latest:*) fetch_latest "${url#latest:}" || true ;;
            *) fetch "$url" || true ;;
        esac
    done < "$URLS_FILE"
fi

echo "--- staged packages.chroot ---"
ls -la "$DEST" || true
