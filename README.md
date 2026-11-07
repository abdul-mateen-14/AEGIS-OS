# Aegis OS

Liquid-glass desktop OS — a **KWin 6 Wayland compositor with a Qt Quick 6 shell**, built entirely on **GitHub Actions free runners**.

> Hardened by default. Quiet chrome, colorful content. Calm. Fast.

This repository implements the [Aegis OS UI Design Proposal v1.3](docs/DESIGN-TOKENS.md) as a real, buildable OS: a live ISO with the Aegis Shell (28 px glass panel, floating dock with macOS-grade magnification, Dynamic Island), the M2 surfaces (Control Center, Launcher, notification banners, lock screen, adaptive effects governor), branded Plymouth boot splash, glass tokens as code, and a fully graphical installer.

For engineers: platform lineage, components and licenses live in [`docs/NOTICE.md`](docs/NOTICE.md).

---

## Status — M2 · Surfaces

| Delivers | Done when |
| --- | --- |
| M1 shell core (see [MILESTONES](docs/MILESTONES.md)) + **Control Center** (348 px sheet — tiles, sliders, live tier badge → governor popover), **Launcher** (8×3 glass grid, type-to-filter), **notification banners** (356×84, stack ≤ 3, `org.freedesktop.Notifications` compatible), **lock screen** (118 px thin clock, PAM unlock), **adaptive effects governor** (tier A↔B↔C, live badge), **Live Activity API** (`org.aegis.Island`) | All overlays open/dismiss under their motion budgets; tier badge truth-checked against KWin |

M1 record and M3/M4 roadmap: [`docs/MILESTONES.md`](docs/MILESTONES.md). App-facing island docs: [`docs/LIVE-ACTIVITY-API.md`](docs/LIVE-ACTIVITY-API.md).

## Repository map

```
.github/workflows/iso.yml        free-runner ISO pipeline (on push, dispatch, callable)
.github/workflows/release.yml    tag v* → ISO → GitHub Release
.github/workflows/shell-ci.yml   aegis-shell .deb compile check
debian-live/                     live-build config: package lists, includes, chroot hooks
shell/                           Aegis Shell (Qt Quick 6 + LayerShellQt) + Debian packaging
  └ src/qml/Tokens.qml           design tokens as code — every proposal table maps here
  └ src/governor/                adaptive effects governor (tier A↔B↔C)
  └ src/activity/                Live Activity API + notifications daemon
  └ src/auth/                    setuid PAM verifier for the lock screen
theme/                           wallpapers · Plymouth · color schemes · desktop entries
calamares/                       installer settings, modules, Aegis branding
scripts/                         build-iso.sh · build-shell.sh · ci/ helpers
docs/                            BUILD · CI free tier · MILESTONES · DESIGN-TOKENS · LIVE-ACTIVITY-API · APP-SLOTS · SECRETS
```

## Quickstart — your first ISO (zero local setup)

Push anything under `debian-live/`, `shell/`, `calamares/` or `scripts/` to `main` (or run **Actions → ISO → Run workflow**). The pipeline:

1. reclaims ~30 GB on the free `ubuntu-latest` runner (72 GB disk),
2. builds `aegis-shell_*.deb` inside an `ubuntu:resolute` container,
3. stages the shell + first-party app `.deb`s,
4. runs live-build inside the container → `AegisOS-*-amd64.iso` (~2.5–3.5 GB),
5. uploads the ISO + sha256 as an artifact (releases on `v*` tags).

Free-tier details and cost math: [`docs/CI-FREE-TIER.md`](docs/CI-FREE-TIER.md).

## Local build (any Linux box with Docker)

```bash
bash scripts/ci/run-in-container.sh bash scripts/build-iso.sh
# → AegisOS-*-amd64.iso in the repo root
```

Shell-only rebuild: `bash scripts/ci/run-in-container.sh bash scripts/build-shell.sh` → `artifacts/aegis-shell_*.deb`. Full guide: [`docs/BUILD.md`](docs/BUILD.md).

## First-party apps (AEGIS Browser · OS Cloud · CoreX)

The ISO reserves three `.deb` slots. Until the real links land, the dock shows stopgap launchers (OS Cloud and CoreX open their web apps; AEGIS Browser points at the `aegis-browser` binary name). Drop-in mechanisms: [`docs/APP-SLOTS.md`](docs/APP-SLOTS.md).

## The v1.4 island override

Per product decision, the Dynamic Island idles at the **iPhone Pro-class pill — 104×32 px** (proposal v1.3 had 148×30). One-line tunables: `Tokens.islandIdleWidth` / `Tokens.islandIdleHeight` in [`shell/src/qml/Tokens.qml`](shell/src/qml/Tokens.qml). Split and Charging states track the idle height; radius always tracks height.

## Download a release ISO

Grab the ISO from [Releases](https://github.com/abdul-mateen-14/AEGIS-OS/releases). It ships as numbered parts plus a checksum file — reassemble and verify:

```bash
cat *.iso.part-* > AegisOS.iso
sha256sum -c SHA256SUMS
```

## Boot it

```bash
# bare metal: flash the ISO to USB (Ventoy/dd/Rufus)
# or try it in QEMU with UEFI + KVM:
qemu-system-x86_64 -enable-kvm -m 4096 -bios /usr/share/ovmf/OVMF.fd \
    -cdrom AegisOS-*-amd64.iso
```

Login (live session): user `aegis`, autologin on, empty password via sudo NOPASSWD. The **Aegis** session is the featured one; a stock compatibility session ships as fallback.

M2 quick tour: click the right half of the top panel (or the sliders glyph) for **Control Center** — flip tiles, drag Display/Sound, and tap the tier badge to drive the effects governor by hand. Open the **Launcher** from a shell surface or via DBus (`busctl --user call org.aegis.Shell /org/aegis/Shell org.aegis.Shell toggleLauncher`) and just type to filter. Lock with `aegis-lock`. Feed the island a live activity:

```bash
aegis-activity publish demo media title="Aurora Drift" artist="Aegis Sound"
aegis-activity end demo
```

Hover the dock for the magnification field; fold it to the sliver by leaving it idle for 4 s and poke the bottom edge to spring it back.

## Third-party components

Platform lineage and license notices: [`docs/NOTICE.md`](docs/NOTICE.md).

License: MIT — see [`LICENSE`](LICENSE).
