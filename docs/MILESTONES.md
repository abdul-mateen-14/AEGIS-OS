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

## M2 · Surfaces — shipped

| Proposal item | Implementation |
| --- | --- |
| Control Center with hardware-tier badge | `shell/src/qml/ControlCenter.qml` — 348 px sheet, 12 px below panel, r 22; Wi-Fi/Bluetooth/Calm/Dark tiles, DND wide tile, Display+Sound sliders, live tier badge → governor popover (Tier A/B/C cards + Auto), footer mono echo `kwin · wayland · <live fps> fps` |
| Launcher (glass sheet) | `shell/src/qml/Launcher.qml` — full-screen sheet glass (KWin blur + 48% scrim), 8×3 grid of 62 px tiles, search pill, page dots above the dock, config-pinned + installed `.desktop` inventory |
| Notifications | `shell/src/qml/Notifications.qml` + `shell/src/activity/ActivityService.cpp` — the shell owns `org.freedesktop.Notifications`; banners 356×84, stack ≤ 3, hairline 5 s track, hover pause, DND queues silently |
| Lock/login surfaces | `shell/src/qml/Lock.qml` — full-bleed wallpaper + 42% scrim, 118 px Montserrat ExtraLight clock, monochrome avatar ring, glass password pill 300×46; PAM unlock through setuid `aegis-auth` (`src/auth/`); `aegis-lock` CLI + `org.aegis.Shell.lock()` DBus |
| Adaptive effects governor (Listing 2, tier A↔B) | `shell/src/governor/Governor.cpp` — frame-time ring over all shell surfaces, >11 ms for 2 s → B, >22 ms for 2 s → C, battery <20% → C + toast; B promotes back after 60 s clear; C manual-only; live badge in CC; state file `$XDG_RUNTIME_DIR/aegis/governor.json` + `org.aegis.Governor` DBus for KWin subscribers |
| Live Activity API for the island | `shell/src/activity/ActivityService.cpp` — `org.aegis.Island` PublishActivity/EndActivity/activityAction; priority stack enforced in C++; island states are data rows (timer/generic added); split lobes; charging is shell-owned on AC transition; demo client `aegis-activity` + `docs/LIVE-ACTIVITY-API.md` |

Delivered beyond the list: right-half panel click zone (Table 3), Wi-Fi /
volume status glyphs, Dark Mode light-rung material swap (glass + fg pair;
full audit stays in M4), `org.aegis.Shell` DBus for `lock` /
`toggleLauncher` / `toggleControlCenter`.

Honest caveats (not silently dropped):

- **Global shortcuts** (Super/F4, Super+A, F2, Super+M) work while a shell
  surface holds keyboard focus; system-wide registration needs KWin
  global-shortcut integration — planned with M3's KWin scripting work.
  Mouse paths (CC glyph, right-half zone, dock) work everywhere.
- **App menu** (focused-app + File/Edit/View/Go) needs focused-window
  tracking from KWin scripting — deferred to M3 with it.
- Panel auto-hide (Focus mode) is M3 scope with the governor's
  idle detection.

Done when: all overlays open/dismiss under their motion budgets (spring
350 CC / standard 180 Launcher / smooth 240 lock — enforced with the
Table 9 tokens, tier-C rung swaps them for 80 ms); tier badge
truth-checked against KWin (the governor measures the shell's own
composited frames and publishes the tier the badge shows).

## M3 · Depth

Mission Control, workspaces + gesture dictionary (Table 10), tiling, remaining
first-party apps, Tier C Calm Mode. Touchpoints: `Dock.qml` (sliver states),
KWin effect configs, governor demotion to C.

## M4 · Parity & beta

GTK interop layer (`adw-gtk3` + icon normalization + GTK4 CSS — chapter 08),
light theme audit (`theme/colors/AegisLight.colors`), LLVMpipe path, OTA
updates, i18n EN + 中文, beta ISO.
