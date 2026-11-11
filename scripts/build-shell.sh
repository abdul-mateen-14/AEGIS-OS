#!/usr/bin/env bash
# Builds the aegis-shell .deb — MUST run inside ubuntu:resolute
# (scripts/ci/run-in-container.sh) so the binary links against the exact
# Qt 6 / LayerShellQt the ISO ships.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

export DEBIAN_FRONTEND=noninteractive
# DNS blips on the runner fleet are real (v0.6.27 attempt 1 lost all four
# archive hosts in one pass) — retry the index refresh before giving up.
for attempt in 1 2 3; do
    if apt-get update -qq; then
        break
    fi
    echo "apt-get update attempt $attempt failed, retrying in 10 s"
    sleep 10
    [ "$attempt" = 3 ] && exit 1
done
apt-get install -y --no-install-recommends \
    build-essential cmake debhelper pkg-config \
    qt6-base-dev qt6-declarative-dev \
    libssl-dev \
    liblayershellqtinterface-dev layer-shell-qt libpam0g-dev \
    file

echo "=== Building aegis-shell ==="
cd "$ROOT/shell"
dpkg-buildpackage -us -uc -b -j"$(nproc)"

mkdir -p "$ROOT/artifacts"
mv "$ROOT"/aegis-shell_*.deb "$ROOT/artifacts/"

echo "=== Built ==="
ls -la "$ROOT/artifacts"
dpkg-deb -I "$ROOT/artifacts"/aegis-shell_*.deb | head -20
