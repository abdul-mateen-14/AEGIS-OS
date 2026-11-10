#!/usr/bin/env bash
# Builds the aegis-shell .deb — MUST run inside ubuntu:resolute
# (scripts/ci/run-in-container.sh) so the binary links against the exact
# Qt 6 / LayerShellQt the ISO ships.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
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
