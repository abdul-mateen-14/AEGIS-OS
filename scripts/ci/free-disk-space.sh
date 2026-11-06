#!/usr/bin/env bash
# Reclaims ~25-30 GB on a GitHub-hosted ubuntu-latest runner.
# The runner has ~72 GB total with only ~19 GB free; a live-build ISO build
# needs ~12-18 GB peak (chroot + squashfs + hybrid image), so this step is
# mandatory before lb build.
set -uo pipefail

echo "=== Disk before cleanup ==="
df -h / || true

sudo rm -rf /usr/local/lib/android          # Android SDK          (~9 GB)
sudo rm -rf /usr/share/dotnet               # .NET SDKs            (~1.7 GB)
sudo rm -rf /opt/ghc /usr/local/.ghcup      # Haskell toolchains   (~5 GB)
sudo rm -rf /opt/hostedtoolcache/CodeQL     # CodeQL bundle        (~5.4 GB)
sudo rm -rf /usr/local/share/boost          # Boost headers        (~1.7 GB)
sudo rm -rf /usr/share/miniconda            # Miniconda            (~2.9 GB)
sudo rm -rf /usr/share/swift                # Swift toolchain      (~1.6 GB)
sudo rm -rf /usr/share/mysql /usr/share/postgresql*  # local DBs   (~1 GB)
sudo docker image prune --all --force 2>/dev/null || true

echo "=== Disk after cleanup ==="
df -h /
