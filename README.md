# Aegis OS

Liquid-glass, Ubuntu-based desktop environment — **KWin 6 Wayland + Qt Quick 6 shell**, built entirely on **GitHub Actions free runners**.

> Hardened by default. Quiet chrome, colorful content. Calm. Fast.

This repository implements the [Aegis OS UI Design Proposal v1.3](docs/DESIGN-TOKENS.md) as a real, buildable OS: a live ISO with the Aegis Shell (28 px glass panel, floating dock with macOS-grade magnification, Dynamic Island), branded Plymouth boot splash, glass tokens as code, and a Calamares installer.

**Base (proposal Table 19):** Ubuntu 26.04 LTS "resolute" · KWin 6 Wayland · Qt Quick 6 · zram default · Calamares. Kubuntu 26.04 LTS ships KDE Plasma 6.6 LTS natively, so no PPAs and no suite hacks.

---

## Status — M1 · Shell core

| Delivers | Done when |
| --- | --- |
| Wayland session ISO (HWE kernel + complete linux-firmware), glass top panel, floating dock + sliver, desktop canvas, Dynamic Island, Files + Terminal, Plymouth splash, Calamares | ISO boots to the Aegis session; panel/dock/island render over the wallpaper |

Roadmap (M2–M4) and their repo touch-points: [`docs/MILESTONES.md`](docs/MILESTONES.md).

## Repository map

```
.github/workflows/iso.yml        free-runner ISO pipeline (on push, dispatch, callable)
.github/workflows/release.yml    tag v* → ISO → GitHub Release
.github/workflows/shell-ci.yml   aegis-shell .deb compile check
debian-live/                     live-build config: package lists, includes, chroot hooks
shell/                           Aegis Shell (Qt Quick 6 + LayerShellQt) + Debian packaging
  └ src/qml/Tokens.qml           design tokens as code — every proposal table maps here
theme/                           wallpapers · Plymouth · color schemes · desktop entries
calamares/                       installer settings, modules, Aegis branding
scripts/                         build-iso.sh · build-shell.sh · ci/ helpers
docs/                            BUILD · CI free tier · MILESTONES · DESIGN-TOKENS · APP-SLOTS · SECRETS
```

## Quickstart — your first ISO (zero local setup)

Push anything under `debian-live/`, `shell/`, `calamares/` or `scripts/` to `main` (or run **Actions → ISO → Run workflow**). The pipeline:

1. reclaims ~30 GB on the free `ubuntu-latest` runner (72 GB disk),
2. builds `aegis-shell_*.deb` inside an `ubuntu:resolute` container,
3. stages the shell + first-party app `.deb`s,
4. runs live-build inside the container → `aegis-os_*.iso` (~2.5–3.5 GB),
5. uploads the ISO + sha256 as an artifact (releases on `v*` tags).

Free-tier details and cost math: [`docs/CI-FREE-TIER.md`](docs/CI-FREE-TIER.md).

## Local build (any Linux box with Docker)

```bash
bash scripts/ci/run-in-container.sh bash scripts/build-iso.sh
# → aegis-os_*.iso in the repo root
```

Shell-only rebuild: `bash scripts/ci/run-in-container.sh bash scripts/build-shell.sh` → `artifacts/aegis-shell_*.deb`. Full guide: [`docs/BUILD.md`](docs/BUILD.md).

## First-party apps (AEGIS Browser · OS Cloud · CoreX)

The ISO reserves three `.deb` slots. Until the real links land, the dock shows stopgap launchers (OS Cloud and CoreX open their web apps; AEGIS Browser points at the `aegis-browser` binary name). Drop-in mechanisms: [`docs/APP-SLOTS.md`](docs/APP-SLOTS.md).

## The v1.4 island override

Per product decision, the Dynamic Island idles at the **iPhone Pro-class pill — 104×32 px** (proposal v1.3 had 148×30). One-line tunables: `Tokens.islandIdleWidth` / `Tokens.islandIdleHeight` in [`shell/src/qml/Tokens.qml`](shell/src/qml/Tokens.qml). Split and Charging states track the idle height; radius always tracks height.

## Boot it

```bash
# bare metal: flash the ISO to USB (Ventoy/dd/Rufus)
# or try it in QEMU with UEFI + KVM:
qemu-system-x86_64 -enable-kvm -m 4096 -bios /usr/share/ovmf/OVMF.fd \
    -cdrom aegis-os_*.iso
```

Login (live session): user `aegis`, autologin on, empty password via sudo NOPASSWD. Pick the **Aegis** session for the featured shell (Plasma Wayland remains as fallback). Double-click the Dynamic Island to cycle its states; hover the dock to see the magnification field; fold it to the sliver by leaving it idle for 4 s and poke the bottom edge to spring it back.

## Open-source foundations

Built on the shoulders of: [live-build](https://salsa.debian.org/live-team/live-build) + [casper](https://launchpad.net/ubuntu/+source/casper) (ISO engineering), [KWin / KDE Plasma 6](https://invent.kde.org/plasma/kwin) (compositor, per the proposal's stack table), [LayerShellQt](https://invent.kde.org/libraries/layer-shell-qt) ( Wayland surface layers), [Calamares](https://github.com/calamares/calamares) (installer), [Plymouth](https://gitlab.freedesktop.org/plymouth/plymouth) (boot splash), [Ubuntu](https://ubuntu.com) (base core + firmware). The shell architecture follows the CutefishOS-proven pattern ("Cutefish started it, macOS polished it — Aegis OS finishes it").

License: MIT — see [`LICENSE`](LICENSE).
