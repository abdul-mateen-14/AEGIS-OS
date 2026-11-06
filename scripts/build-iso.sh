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
    grub-efi-amd64-signed shim-signed \
    syslinux-common isolinux syslinux-utils \
    mtools dosfstools e2fsprogs \
    rsync curl ca-certificates file

# Patch live-build 3.0~a57: the gfxboot "bootlogo" repack block in
# lb_binary_syslinux is unconditional but only ever worked with
# --mode ubuntu's gfxboot-theme-ubuntu assets. With a plain vesamenu theme
# there is no bootlogo archive, so the block aborts the whole build.
# Delete it — vesamenu reads the loose .cfg files and ignores bootlogo.
sed -i '/# Hack around the removal of support in gfxboot/,/^rm -rf "\$tmpdir"$/d' \
    /usr/lib/live/build/lb_binary_syslinux
echo "patched lb_binary_syslinux (gfxboot bootlogo block removed)"

# --- BIOS fix ---------------------------------------------------------------
# live-build 3.0~a57's isolinux template (system AND user dirs) ships only
# isolinux.bin + vesamenu.c32. syslinux 6 split the core into modules:
# isolinux.bin immediately needs ldlinux.c32, and vesamenu.c32 links
# libcom32.c32 + libutil.c32. Missing ldlinux.c32 = "Failed to load
# ldlinux.c32 / Boot failed" on every real BIOS machine. Stage the three
# modules from the container's syslinux-common into our bootloader dir —
# binary_syslinux copies config/bootloaders/isolinux verbatim.
for mod in ldlinux.c32 libcom32.c32 libutil.c32; do
    cp -f "/usr/lib/syslinux/modules/bios/${mod}" \
          "$ROOT/debian-live/config/bootloaders/isolinux/${mod}"
done
echo "staged syslinux BIOS modules (ldlinux/libcom32/libutil)"

# --- UEFI support -----------------------------------------------------------
# live-build 3.0~a57 has NO EFI ISO support (no binary_grub-efi, no ESP, no
# El Torito EFI entry) — its ISOs boot on nothing newer than 2011. We build
# the EFI chain ourselves, Debian-hybrid style:
#   includes.binary/EFI/efiboot.img  FAT ESP: shim + signed grub + fallback cfg
#   includes.binary/boot/grub/*      /boot/grub/grub.cfg + modules for the
#                                    signed grub (prefix = /boot/grub)
# and inject the El Torito EFI entry (-e) + isohybrid --uefi (MBR partition
# 0xEF) through the GENISOIMAGE_OPTIONS_EXTRA / ISOHYBRID_OPTIONS env
# passthrough consumed by lb_config (see debian-live/auto/config).
ESP_DIR="$ROOT/debian-live/config/includes.binary/EFI"
GRUB_DIR="$ROOT/debian-live/config/includes.binary/boot/grub"
mkdir -p "$ESP_DIR" "$GRUB_DIR/x86_64-efi" "$GRUB_DIR/fonts"

# Signed EFI binaries + grub module tree (grub-efi-amd64-signed/-bin,
# shim-signed; dosfstools + mtools for the ESP image).
SHIM="/usr/lib/shim/shimx64.efi.signed"
GRUBEFI="/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed"
test -e "$SHIM"    || { echo "ERROR: $SHIM missing — install shim-signed"; exit 1; }
test -e "$GRUBEFI" || { echo "ERROR: $GRUBEFI missing — install grub-efi-amd64-signed"; exit 1; }

cp -f /usr/lib/grub/x86_64-efi/*.mod "$GRUB_DIR/x86_64-efi/"
for lst in /usr/lib/grub/x86_64-efi/*.lst; do
    cp -f "$lst" "$GRUB_DIR/x86_64-efi/" 2>/dev/null || true
done
cp -f /usr/share/grub/unicode.pf2 "$GRUB_DIR/fonts/unicode.pf2"

# Fallback config inside the ESP (the signed grub normally reads
# /boot/grub/grub.cfg from the ISO; this covers prefix lookup failures).
mcopy_src="$GRUB_DIR/grub.cfg"
test -f "$mcopy_src" || { echo "ERROR: $mcopy_src missing"; exit 1; }

rm -f "$ESP_DIR/efiboot.img"
dd if=/dev/zero of="$ESP_DIR/efiboot.img" bs=1M count=8 status=none
mkfs.vfat -F 16 -n AEGIS_EFI "$ESP_DIR/efiboot.img" > /dev/null
mmd -i "$ESP_DIR/efiboot.img" ::/EFI ::/EFI/boot
mcopy -i "$ESP_DIR/efiboot.img" "$SHIM"    ::/EFI/boot/bootx64.efi
mcopy -i "$ESP_DIR/efiboot.img" "$GRUBEFI" ::/EFI/boot/grubx64.efi
mcopy -i "$ESP_DIR/efiboot.img" "$mcopy_src" ::/EFI/boot/grub.cfg
echo "built efiboot.img (shim + signed grub, 8 MB FAT16)"

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
# live-build expects to run from the config root (auto/ lives there).
cd "$ROOT/debian-live"
rm -f build.log
bash auto/config
bash auto/build

# live-build drops the image (binary.iso / binary-hybrid.iso) in the config
# root — relocate it next to the workflow's verify step.
BUILT_ISO="$(ls -1 "$ROOT/debian-live"/*.iso 2>/dev/null | head -1 || true)"
if [ -n "$BUILT_ISO" ]; then
    mv "$BUILT_ISO" "$ROOT/"
fi
cd "$ROOT"

echo "=== 5/5 Verify ==="
ISO="$(ls -1 "$ROOT"/*.iso 2>/dev/null | head -1 || true)"
if [ -z "$ISO" ]; then
    echo "ERROR: no ISO produced. Last 200 lines of the build log:"
    tail -n 200 "$ROOT/debian-live/build.log" 2>/dev/null || true
    exit 1
fi
ls -lh "$ISO"
file "$ISO"
sha256sum "$ISO" | tee "$ISO.sha256"
# The container runs as root; the workflow's verify step re-writes the
# checksum as the runner user, so the file must be writable by everyone.
chmod 666 "$ISO.sha256" 2>/dev/null || true
echo "OK: $ISO"
