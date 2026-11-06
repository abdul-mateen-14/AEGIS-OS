#!/usr/bin/env bash
# Builds the Aegis OS live ISO — MUST run inside ubuntu:resolute
# (scripts/ci/run-in-container.sh, privileged).
#
# Stages: sync assets -> stage .debs -> lb config -> lb build -> verify.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    live-build debootstrap binutils \
    squashfs-tools xz-utils xorriso \
    grub-common grub-pc-bin grub-efi-amd64-bin \
    syslinux-common isolinux \
    mtools dosfstools e2fsprogs \
    rsync curl ca-certificates file

echo "=== 1/5 Sync theme + calamares assets into live-build includes ==="
bash scripts/sync-includes.sh

echo "=== 2/5 Stage app .debs (app-deb-urls.txt) ==="
bash scripts/ci/install-app-debs.sh || true

echo "=== 3/5 Stage aegis-shell .deb ==="
if ls "$ROOT/artifacts"/aegis-shell_*.deb 1>/dev/null 2>&1; then
    mkdir -p debian-live/config/packages.chroot
    cp "$ROOT/artifacts"/aegis-shell_*.deb debian-live/config/packages.chroot/
else
    echo "WARNING: no aegis-shell deb found in artifacts/ — ISO will boot without the shell"
fi

echo "=== 4/5 live-build: config + build ==="
rm -f build.log
bash auto/config
lb build 2>&1 | tee build.log

echo "=== 5/5 Verify ==="
ISO="$(ls -1 "$ROOT"/*.iso 2>/dev/null | head -1 || true)"
if [ -z "$ISO" ]; then
    echo "ERROR: no ISO produced. Last 200 lines of the build log:"
    tail -n 200 build.log || true
    exit 1
fi
ls -lh "$ISO"
file "$ISO"
sha256sum "$ISO" | tee "$ISO.sha256"
echo "OK: $ISO"
