#!/usr/bin/env bash
# Builds the KDE-Rounded-Corners KWin effect .deb (kwin4_effect_shapecorners)
# — rounds ALL FOUR window corners + hairline outline (proposal: 18 px target,
# 12-14 px interim; see docs review round 2, item 1).
#
# MUST run inside ubuntu:resolute (scripts/ci/run-in-container.sh), same as
# build-shell.sh. Deps mirror upstream's kubuntu2604.yml CI job, pinned tag.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TAG="v0.11.0"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    cmake g++ gettext extra-cmake-modules \
    qt6-base-private-dev qt6-base-dev-tools \
    libkf6configwidgets-dev libkf6kcmutils-dev \
    kwin-dev kwin-x11-dev libdrm-dev \
    dpkg-dev file git ca-certificates

SRC=/tmp/KDE-Rounded-Corners
rm -rf "$SRC"
git clone --depth 1 --branch "$TAG" \
    https://github.com/matinlotfali/KDE-Rounded-Corners "$SRC"
cd "$SRC"

cmake . -DCMAKE_BUILD_TYPE=Release
cmake --build . -j"$(nproc)"
cpack -V -G DEB

mkdir -p "$ROOT/artifacts"
mv "$SRC"/*.deb "$ROOT/artifacts/"
echo "=== Built ==="
ls -la "$ROOT/artifacts"
for d in "$ROOT"/artifacts/*.deb; do
    dpkg-deb -I "$d" | head -12
done
