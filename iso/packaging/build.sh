#!/usr/bin/env bash
# Build the AEGIS debian packages in dependency order — the cutefish
# packaging model (work/cutefish-survey/packaging/debian/build.sh).
#   iso/packaging/build.sh                # everything
#   iso/packaging/build.sh aegis-compositor
set -euo pipefail
cd "$(dirname "$0")"

COMPONENTS="${@:-aegis-icons aegis-id aegis-compositor aegis-desktop}"

# desktop/ build order (the submodules' own packages land r3+):
#   toolkit -> framework -> fishui -> qt-plugins -> icons -> core
#   -> compositor -> apps (filemanager, terminal, settings, calculator,
#   video-player, text-editor, system-monitor) + aegis-id (Aegis-original)
# Each becomes an aegis-<name> debian dir here with the rebrand applied.

for c in $COMPONENTS; do
    echo "── building $c"
    (cd "$c" && dpkg-buildpackage -us -uc -b)
done
echo "── artifacts in iso/packaging/"
