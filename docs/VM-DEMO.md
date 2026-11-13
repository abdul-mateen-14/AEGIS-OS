# VM-DEMO — running Aegis OS in a virtual machine

The v0.6.36 round (QEMU/VirtualBox era) and the v0.6.55 VMware round
taught the same lesson twice: a demo VM needs its boot order and virtual
drives set up ONCE, or the installer round ends in a firmware screen.
This document is the demo setup the OS itself now assumes — and every
piece of it is asserted or handled in code (see the W41/W46 rulings in
docs/TASKS.md).

## VMware Workstation (the user's demo path)

1. **New VM**: "Custom (Advanced)" — compatibility the current
   Workstation release, "I will install the operating system later".
2. **Guest OS**: Linux / Ubuntu 64-bit. Workstation presents the VMware
   SVGA II device; Aegis carries `vmwgfx` in the initramfs since
   v0.6.56 (the 0200-plymouth hook force-loads it), so the boot splash
   paints instead of flooding the console with `[ OK ]` lines.
3. **Disk**: **>= 24 GB** virtual disk. The installed system (KDE stack +
   the first-party suite + the Tier B debs) needs room; 20 GB disks
   finish the install and then choke on updates.
4. **CD**: attach `AegisOS-<version>-amd64.iso` to CD/DVD (use ISO image).
   **Boot order: CD first** — until a disk install exists, that is the
   only bootable device.
5. **Network**: **NAT**. NAT is wired ethernet from the guest's point of
   view — the Network pane shows the wired row (Connected + IP + the
   Disconnect/Reconnect buttons) and the panel shows the RJ45 glyph.
   There is no Wi-Fi toggle in a VM because there is no radio; that is
   honest, not a defect (W43).
6. **Install**: boot the ISO -> the live session -> the Store notice card
   or the app grid -> run the Aegis installer. On success the installer
   drops a completion banner: **remove the ISO, then reboot.**

## The restart trap (W46.2) — what "no bootable device" was

| Sequence | Result |
| --- | --- |
| Reboot with ISO attached, CD-first order | Boots the LIVE session again — "my install disappeared" |
| Reboot with ISO ejected, CD-first order | Firmware falls through to the disk — GRUB |
| Reboot with ISO still in the *host* drive list but disconnected from the guest | Disk boot (the guest eject did it) |

Since v0.6.56 the installer's **Restart now** button runs
`aegis-install-finish`: it ejects the live medium from the guest side
(eject /dev/sr0, udisksctl power-off as fallback) before `systemctl -i
reboot`. On VMware a guest eject disconnects the ISO-backed virtual CD —
so the default button is safe by itself. If you reboot manually instead,
disconnect the CD first (VM > Removable Devices > CD/DVD > Disconnect).

## QEMU (the CI harness path)

`scripts/boot-capture.py` runs the ISO two ways since v0.6.56 — one
boot-gate variant per hypervisor family:

- `python3 scripts/boot-capture.py iso/AegisOS.iso screenshots` — the
  full choreography on virtio (`virtio-vga-gl`, KVM when available).
  This is the release-blocking gate.
- `python3 scripts/boot-capture.py iso/AegisOS.iso shots-vmware
  --vmware-boot-check` — the VMware family variant on QEMU's
  `vmware-svga` device (the guest loads `vmwgfx` exactly like
  Workstation): asserts the mark splash paints, `vmwgfx` is loaded, and
  the journal carries no plymouthd DRM-master failure line.

## Graphics, honestly

- The CI runner is virtio; Workstation is vmwgfx; both ship their DRM
  module in the initramfs since v0.6.56 (0200 hook force-load list:
  `virtio_gpu bochs_drm bochs vmwgfx qxl cirrus`, modinfo-guarded per
  kernel). A boot fix is not "done" when it only paints on virtio.
- Electron/Chromium apps (AEGIS Browser, OS, CoreX) run through
  `aegis-electron-launch`, which adds `--disable-gpu --no-sandbox` in
  VMs (nosuid guest root, no user namespaces) and
  `--no-first-run --no-default-browser-check` everywhere.
