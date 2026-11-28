# AEGIS OS — cutefish adoption & the Rust migration

Status: **plan adopted** (W101). Decision record: the previous in-house QML
shell (`shell/src/`) served 100 rounds but never reached the completeness of
a mature desktop; the cutefishos desktop layer is proven, actively developed
(last commit the day this plan was written) and structurally modern. AEGIS
adopts it as the desktop base, keeps every first-party AEGIS app, and moves
the AEGIS-specific shell logic to Rust crate by crate.

## Attribution and licenses (read this first)

cutefishos is third-party software and its code stays theirs:

| Upstream repo | License | Notes |
| --- | --- | --- |
| cutefish-compositor | BSD 3-clause (© 2026 Reion Wong) | the desktop base — see below |
| fishui | BSD 3-clause | widget library (apps keep their own UI) |
| filemanager, launcher, cutefish-core, qt-plugins | BSD 3-clause | reference / selective adoption |
| statusbar | GPL-3.0 | NOT adopted while GPL obligations weigh more than its value |

BSD 3-clause requires retaining the copyright notice and license text in
every distribution — the upstream `LICENSE` files are vendored untouched and
the copyright headers stay in the files. The README credits the base in one
factual line. Nothing here claims the upstream work as AEGIS original code.

## The new architecture

```
┌──────────────────────────────────────────────────────────┐
│ Aegis apps (UNCHANGED): Browser/CoreX, Files, Terminal,  │
│ Music, Store, Settings, Monitor, Editor, Calculator …    │
├──────────────────────────────────────────────────────────┤
│ Aegis shell bits (the signature visuals): Dynamic Island │
│ + Control Center + launcher integration                  │
│   → aegis-rs/ (Rust track: island-core first)            │
├──────────────────────────────────────────────────────────┤
│ cutefish-compositor (the desktop base): window mgmt,     │
│ desktop shell, lock screen, Xwayland — one process       │
│ (236k lines C++, modeled on Chromium's Exo/Ash)          │
├──────────────────────────────────────────────────────────┤
│ Debian live ISO, Calamares installer, the Aegis theme    │
└──────────────────────────────────────────────────────────┘
```

## What stays / what goes

- **Stays**: every Aegis app and its backend, the Aegis logos, the icon
  designs the user gave (settings, store, music, terminal …), the installer,
  the ISO pipeline, the design tokens as the DESIGN SPEC for the Rust
  renderer.
- **Goes (stage by stage)**: the hand-rolled QML desktop layer in
  `shell/src/` — the dock/panel/window-management stack that took 100 rounds
  of patching. It keeps running during the transition; nothing is deleted
  until its replacement boots and passes the same boot asserts.

## Stage 0 — survey (done, this commit)

Upstream cloned for reference into a workspace outside the repo. Module map
of `cutefish-compositor/src/` (what maps where in AEGIS):

| Upstream module | Purpose | AEGIS counterpart today |
| --- | --- | --- |
| `compositor/`, `render/`, `scene/`, `backend/` | Wayland server, renderer, scene graph, DRM backend | KWin (the ISO's WM) |
| `shell/` | the desktop shell: wallpaper, dock, menu bar | `shell/src/qml/Dock.qml` + `Panel.qml` |
| `input/`, `cursor/`, `accelerators/` | input pipeline, pointer acceleration | KWin input |
| `decoration/`, `switcher/` | window decorations, app switcher | KWin + the QML alt-tab |
| `session/`, `auth/` | the lock screen session | `shell/src/qml/Lock.qml` + PAM helper |
| `ipc/` | the shell's IPC surface | `org.aegis.Shell` DBus API |
| `clipboard/`, `display/`, `core/` | clipboard mgmt, display config, core utils | KWin equivalents |

## Stage 1 — the compositor boots in AEGIS (next round)

1. Vendor `cutefish-compositor` into the repo (or pin a submodule) **with
   its LICENSE files untouched**.
2. Package it for the ISO (CMake build; deps: cutefish-toolkit, the
   cutefish-framework clients, libwayland ≥ 1.23, xwayland).
3. Boot the ISO with the compositor as the session; the Aegis apps run as
   plain Wayland clients on it. Keep the QML shell packaged as the fallback
   session (a SDDM session chooser) until the compositor passes every boot
   assert the old shell passed.

## Stage 2 — the Rust track (started, this commit)

`aegis-rs/` is the Rust workspace where the AEGIS-specific shell logic is
ported crate by crate. `island-core` is the first: the Dynamic Island's
brain — priority stack (Table 5b), the geometry records, the lobe widths,
the radius rule, and the spring solver (mass 1 · stiffness 420 · damping 28)
— ported 1:1 from `Island.qml`/`Tokens.qml` with unit tests that pin the
behavior contract (idle 104×32 → Now Playing 356×96 r32 and back, split =
the top two lobes + 8 px, no-teleport spring clamp).

Next in the track: `island-shell` (the layer-shell renderer that consumes
`island-core` — surface, blur, the W90 expanded-card visuals), then
`control-center-core`, then the launcher's search ranking.

## Stage 3 — the old shell retires

When the compositor session + the Rust island pass the full boot matrix
(every assert in `scripts/boot-capture.py`), the QML dock/panel/launcher
sources move to `attic/` (kept for reference, out of the build) and the
compositor becomes the default session.
