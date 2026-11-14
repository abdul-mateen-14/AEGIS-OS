#!/usr/bin/env bash
# Builds the aegis-shell .deb — MUST run inside ubuntu:resolute
# (scripts/ci/run-in-container.sh) so the binary links against the exact
# Qt 6 / LayerShellQt the ISO ships.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

export DEBIAN_FRONTEND=noninteractive
# DNS blips on the runner fleet are real (v0.6.27 lost all four archive
# hosts in one pass). apt-get update exits 0 on W-only fetch failures, so
# the retry verdict comes from the package index, not the exit code.
for attempt in 1 2 3; do
    apt-get update -qq || true
    if apt-cache show build-essential >/dev/null 2>&1; then
        break
    fi
    echo "archive indexes unavailable (attempt $attempt), retrying in 10 s"
    sleep 10
    if [ "$attempt" = 3 ]; then
        echo "archive unreachable after 3 attempts"
        exit 1
    fi
done
apt-get install -y --no-install-recommends \
    build-essential cmake debhelper pkg-config \
    qt6-base-dev qt6-declarative-dev \
    libssl-dev \
    liblayershellqtinterface-dev layer-shell-qt \
    libkf6windowsystem-dev \
    libpam0g-dev \
    file

echo "=== Building aegis-shell ==="
cd "$ROOT/shell"
dpkg-buildpackage -us -uc -b -j"$(nproc)"

mkdir -p "$ROOT/artifacts"
mv "$ROOT"/aegis-shell_*.deb "$ROOT/artifacts/"

echo "=== Built ==="
ls -la "$ROOT/artifacts"
dpkg-deb -I "$ROOT/artifacts"/aegis-shell_*.deb | head -20
