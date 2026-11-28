#!/usr/bin/env bash
# Build the AEGIS debian packages in dependency order — the cutefish
# packaging model (work/cutefish-survey/packaging/debian/build.sh).
#   iso/packaging/build.sh                # everything
#   iso/packaging/build.sh aegis-compositor
set -euo pipefail
cd "$(dirname "$0")"

COMPONENTS="${@:-aegis-compositor aegis-desktop}"

for c in $COMPONENTS; do
    echo "── building $c"
    (cd "$c" && dpkg-buildpackage -us -uc -b)
done
echo "── artifacts in iso/packaging/"
