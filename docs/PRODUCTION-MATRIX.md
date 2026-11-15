# AEGIS OS — Production Device Matrix (T19)

Scope: the user's production mandate — the ISO installs and boots on
**every kind of device**: bare metal (a brand-new machine, or a
refurbished one with no OS at all), dual boot next to Windows or
another Linux, and every hypervisor (VMware, VirtualBox, QEMU/KVM,
SPICE).

## What gates every release

| Gate | Where | What it proves |
|---|---|---|
| Production package set | `build-iso.sh` verify stage | microcode, SOF audio firmware, VM guest tools, NTFS/exFAT, installer, Secure Boot chain, PipeWire/NetworkManager/bluez/cups/fwupd **all present in the squashfs manifest** — a release fails before it publishes if any rot out of the archive |
| Direct-boot desktop | boot test, main leg | kernel + live system reach the desktop on virtio |
| ISO chain boot — BIOS | boot test, T19 leg | the **isolinux chain as shipped** (SeaBIOS → isolinux → kernel → live) reaches the desktop — no kernel extraction |
| ISO chain boot — UEFI | boot test, T19 leg | the **standalone GRUB ESP as shipped** (OVMF → GRUB → kernel → live) reaches the desktop |
| VMware device family | boot test, W48 leg | vmwgfx loads, plymouthd clean, serial session up |
| Bootloader modules | `build-iso.sh` | ldlinux/libcom32/libutil staged (the v0.6.14 BIOS fix is build-time enforced) |

## The matrix, honestly

| Device class | Live session | Installed system | Proven by |
|---|---|---|---|
| Bare metal, UEFI (any new PC) | ✅ T19 CI leg | ✅ shim-signed GRUB chain in the image | CI (OVMF) — real silicon by the user's re-test |
| Bare metal, legacy BIOS (refurb) | ✅ T19 CI leg | ✅ grub-pc chain staged | CI (SeaBIOS) — real silicon pending |
| Dual boot with Windows | ✅ | ✅ os-prober re-enabled via `GRUB_DISABLE_OS_PROBER=false` (Calamares `shellprocess@grub-os-prober` before grubcfg); separate NVRAM entry, no clobber | config in place — one real dual-boot install pending |
| Dual boot with Linux | ✅ | ✅ same os-prober path | config in place |
| VMware | ✅ kernel vmwgfx + open-vm-tools(-desktop) in the ISO | ✅ same | CI W48 leg + the user's Workstation captures (W41, pending) |
| VirtualBox | ✅ vboxvideo KMS + guest-utils/-x11 | ✅ same | packages in the manifest gate |
| QEMU/KVM (virtio or SPICE) | ✅ virtio/virtio-gl + spice-vdagent + qemu-guest-agent | ✅ same | the main boot-test leg |
| NVIDIA bare metal | ⚠️ nouveau (display works, acceleration on Turing+ needs the packaged driver) | ✅ first-boot `aegis-drivers` unit runs `ubuntu-drivers install` when an NVIDIA card is present, self-disables on success, logs to `/var/log/aegis-drivers.log` | unit in the image; real-card install pending |
| Intel SOF audio (2019+ laptops) | ✅ firmware-sof-signed + alsa-ucm-conf | ✅ same | manifest gate |
| CPU errata/security | ✅ intel-microcode + amd64-microcode | ✅ same | manifest gate |

## Known honest limits (recorded, not hidden)

1. **Live USB + Secure Boot ON**: the ISO's own EFI binary is a
   grub-mkstandalone build and is NOT signed — booting the live USB on
   a Secure-Boot machine requires Secure Boot disabled or a registered
   MOK. The INSTALLED system ships `shim-signed` + `grub-efi-amd64-signed`
   and boots Secure Boot ON. Secure Boot for the live media is the M2
   shim-integration item (build-iso.sh documents the probed state).
2. **`-security` pocket**: auto/config still builds without the Ubuntu
   `-security` pocket (the live-build 3.0~a57 Debian-style path bug) —
   recorded since v0.6.x; the installed system points at the normal
   Ubuntu mirrors via casper's networkcfg and pulls security updates
   normally at first `apt update`.
3. **BitLocker dual-boot**: Calamares cannot resize a BitLocker volume;
   Windows fast-startup must be off before an alongside-install. The
   installer shows the standard partition view; a BitLocker warning
   page is a follow-up, not a blocker (os-prober still finds the EFI
   entry).
4. **Real-silicon claims** close only on the user's hardware (W41
   captures and a bare-metal re-test), never on CI alone.

## T19 changes that made this real

- `debian-live/config/package-lists/aegis-production.list.chroot` — the
  enablement set with the per-class rationale in comments.
- `bootloader.conf` — the Arch-style `/boot/vmlinuz-linux` kernel paths
  (files that do not exist on an Ubuntu target) replaced by the
  Calamares 3.3 discovery schema (`kernelSearchPath` + `kernelPattern`).
- `grub-os-prober.conf` + settings.conf — dual-boot menu entries on
  every install.
- `aegis-drivers.service` — the NVIDIA first-boot enablement unit.
- ISO boot lines carry `console=ttyS0,115200n8` so any real machine's
  serial (and every CI leg) stays diagnosable.
- Boot test: BIOS + UEFI ISO-chain legs; the release gate asserts the
  production manifest.
