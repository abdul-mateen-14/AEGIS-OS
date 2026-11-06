# Ship sequence — proposal §9.2 mapped to this repository

Each milestone ships something usable on its own; the design system (Tokens.qml)
lands in M1 and never changes shape after.

## M1 · Shell core — **this repository**

Scope: Wayland session ISO (complete linux-firmware + HWE kernel), panel, dock
with sliver, desktop, Files + Terminal, Tier A effects, glass tokens as code.

| Proposal item | Implementation |
| --- | --- |
| Ubuntu LTS core, minimal seed, zram | `debian-live/auto/config` (minbase debootstrap), `etc/default/zramswap` + zramswap hook |
| KWin 6 Wayland session | `shell/src/session/aegis-session`, `usr/share/wayland-sessions/aegis.desktop` |
| 28 px glass top panel | `shell/src/qml/Panel.qml` (+ LayerShellQt exclusive zone in `main.cpp`) |
| Floating dock + sliver | `shell/src/qml/Dock.qml` (§2.2 recipe: map → spring → write) |
| Dynamic Island | `shell/src/qml/Island.qml` (Table 5b states; v1.4 idle 104×32) |
| Desktop canvas | `shell/src/qml/Desktop.qml` (wallpaper only until M2) |
| Files + Terminal | Dolphin + Konsole, Aegis entries in `theme/desktop-entries/` |
| Plymouth splash | `theme/plymouth/` + `0200-plymouth.hook.chroot` |
| Installer | `calamares/` (settings, modules, branding) |
| First-party apps | `.deb` slots — `docs/APP-SLOTS.md` |

Done when: the ISO boots on the four test machines and the Table 20 budgets
are measured and published (add them to `docs/MILESTONES.md` when measured).

## M2 · Surfaces — next

- Control Center with hardware-tier badge → `shell/src/qml/ControlCenter.qml`
- Launcher (glass sheet) → `shell/src/qml/Launcher.qml`
- Notifications (island publishes them; CC queues the rest)
- Lock/login surfaces → `shell/src/qml/Lock.qml`
- Adaptive effects governor (Listing 2 state machine, tier A↔B) →
  `shell/src/governor/`
- Live Activity API for the island (DBus service) → `shell/src/activity/`

Done when: all overlays open/dismiss under their motion budgets; tier badge
truth-checked against KWin.

## M3 · Depth

Mission Control, workspaces + gesture dictionary (Table 10), tiling, remaining
first-party apps, Tier C Calm Mode. Touchpoints: `Dock.qml` (sliver states),
KWin effect configs, governor demotion to C.

## M4 · Parity & beta

GTK interop layer (`adw-gtk3` + icon normalization + GTK4 CSS — chapter 08),
light theme audit (`theme/colors/AegisLight.colors`), LLVMpipe path, OTA
updates, i18n EN + 中文, beta ISO.
