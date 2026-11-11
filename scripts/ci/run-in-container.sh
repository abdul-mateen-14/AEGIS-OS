#!/usr/bin/env bash
# Runs a script inside a pristine Ubuntu 26.04 LTS (resolute) container.
#
# Why a container: the ISO targets resolute, but the runner's host OS (and its
# debootstrap / archive keyring) may lag behind. Building inside ubuntu:resolute
# pins debootstrap, keyrings, live-build and the whole toolchain to the exact
# release the ISO is built from — independent of runner drift.
#
# Usage: scripts/ci/run-in-container.sh <command...>
set -euo pipefail

IMG="ubuntu:resolute"
if ! docker pull "$IMG" >/dev/null 2>&1; then
    echo "ubuntu:resolute tag unavailable, falling back to ubuntu:26.04"
    IMG="ubuntu:26.04"
fi

# --privileged: live-build bind-mounts /dev, /proc and /sys into the chroot,
# which needs mount capabilities the default docker capset does not include.
# --network host: the 2026-11-11 v0.6.27 runs lost archive.ubuntu.com DNS
# inside the default bridge (docker's embedded resolver forwards to the
# host resolver; when the host's resolver stops answering the bridge, apt
# gets "Could not resolve" and the build dies before any package can be
# located). The host network namespace hands the container the runner's
# working resolver directly. The VM is disposable — the isolation trade is
# nil, and live-build's archive fetches take the same path.
exec docker run --rm --privileged --network host \
    -v "${GITHUB_WORKSPACE:-$(pwd)}:/work" \
    -w /work \
    "$IMG" "$@"
