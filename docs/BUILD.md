# Building Aegis OS

## One-command local build

Requirements: Docker (or a compatible container runtime). Everything else is
pinned inside `ubuntu:resolute`.

```bash
git clone https://github.com/abdul-mateen-14/AEGIS-OS.git
cd AEGIS-OS
bash scripts/ci/run-in-container.sh bash scripts/build-iso.sh
```

Output: `aegis-os_*.iso` + `aegis-os_*.iso.sha256` in the repo root.
Typical duration on a 4-core machine: **35–70 minutes** (most of it is
squashfs compression), peak disk use ~15 GB.

## What happens inside

`scripts/build-iso.sh` (running as root inside the container):

1. `scripts/sync-includes.sh` — copies `theme/`, `calamares/` and
   `shell/packaging/` assets into `debian-live/config/includes.chroot/`
   (sources stay in git; the includes tree carries the binaries).
2. `scripts/ci/install-app-debs.sh` — downloads the three first-party app
   `.deb`s listed in `debian-live/app-deb-urls.txt` into
   `config/packages.chroot/` (live-build installs that directory verbatim).
3. Copies `artifacts/aegis-shell_*.deb` (if present) into the same dir.
4. `bash auto/config` → `lb build` — live-build bootstraps a minbase
   resolute chroot, installs the package lists in
   `config/package-lists/*.list.chroot` + `config/packages.chroot/*.deb`,
   runs `config/hooks/live/*.hook.chroot`, and packs an `iso-hybrid` image
   (BIOS + UEFI, casper initramfs, zstd kernels via the HWE meta).
5. Verifies + hashes the ISO.

The `aegis-shell` .deb is a separate build: `scripts/build-shell.sh` runs
`dpkg-buildpackage` against resolute's Qt 6 + LayerShellQt. CI always builds
it fresh inside the ISO job (no artifact cross-trusting).

## Kernel flavour

`auto/config` pins `--linux-flavours generic-hwe-26.04` (M1 scope: "complete
linux-firmware + HWE kernel"). If that meta package is ever missing from the
archive, swap to `generic`:

```bash
sed -i 's/generic-hwe-26.04/generic/' debian-live/auto/config
```

## Testing the ISO

```bash
qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 \
    -bios /usr/share/ovmf/OVMF.fd -cdrom aegis-os_*.iso
```

BIOS boot works without `-bios`. First boot lands in the **Aegis** session:
desktop wallpaper, 28 px panel, floating dock, Dynamic Island top-center
(click to cycle), Plymouth splash at boot.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `E: Unable to locate package linux-image-generic-hwe-26.04` | swap flavour per above |
| `No space left on device` (CI) | the free-disk-space step is missing/failed — check `iso.yml` |
| live-build stage cache weirdness after config edits | `bash debian-live/auto/clean` and rebuild |
| Dock/island invisible in the live session | check `journalctl --user -u aegis-shell`; KWin blur rules live in `~/.config/kwinrulesrc` |
| Shell segfault on non-Wayland (dev run under X11) | expected — layer-shell needs a Wayland compositor; run inside the session or nested `kwin_wayland` |
