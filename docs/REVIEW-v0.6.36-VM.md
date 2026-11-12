# AEGIS-OS — Build Instructions v0.6.36
**Reviewer:** Aegis-OS UI v1.3 author — first **real-VM usage report** of v0.6.34 (not screenshots this time; the user booted the ISO in a VM and drove the OS).
**Scope:** triage of every VM complaint with root causes found in the source. **v0.6.35 items W16–W23 all still stand** — this file adds W24–W37. The W20 KWin window tracking prerequisite from v0.6.35 is now **hard-required** (three complaints depend on it).

---

## §0 What the VM run proved

The screenshot pipeline can only prove pixels; this run proves **behavior**. Everything below was reproduced or root-caused in the source, not guessed. The single biggest structural cause: **the shell has no real window tracking (`util.h:100` — `runningCmds` is launch-recorded only)** and **dock commands are bare command-heads that don't exist on PATH for two of the three debs**.

---

## §1 Root-caused defects (W24–W30) — fix first

### W24 (fix, highest priority) — The three deb apps cannot launch: dock `cmd` is not the real command
`shell/packaging/config.json`:
```json
{ "name": "OS",     "icon": "os-private-chat", "cmd": "os-private-chat",  "resolve": true },
{ "name": "CoreX",  "icon": "corex-terminal",  "cmd": "corex-terminal",   "resolve": true }
```
`Util.launch()` runs `sh -c <cmd>`. But electron-builder debs install to **`/opt/OSPrivateChat/os-private-chat`** and **`/opt/CoreX Terminal/corex-terminal`** (note the **space** in the CoreX path) with **no `/usr/bin` symlink** — the `.desktop` Exec uses the quoted full path. So:
- OS Private Chat → `sh: os-private-chat: command not found` → nothing happens.
- CoreX → command not found (and even if the head existed it wouldn't be the real path).
- Aegis Browser launches (its wrapper `/usr/bin/aegis-browser-stable` IS on PATH) but still "doesn't work" in the VM → see W25 for its runtime causes.

Fix:
1. `findInstalledEntry` (util.cpp:528) already parses the winning `.desktop` — **also return the full `Exec=` string**. For `resolve: true` slots the dock must launch that full quoted Exec (Qt's `QProcess::splitCommand` semantics), falling back to the bare cmd only when no entry exists.
2. Keep the head-vs-`Exec`-basename matching for the **icon/name** resolution — that part is correct (it's why the real logos render).
3. Wrap every Tier B launch with a stderr/stdout log: `~/.local/state/aegis/launch/<app>.log` (timestamped, last 50 lines kept) so VM failures are diagnosable by the user sending one file.
4. **Boot-test probe per Tier B app**: launch it, wait ≤20 s, assert the process exists (`pgrep -f` the Exec head) and capture its screenshot; verdict token per app. "Installs but doesn't launch" must go red in CI, not be discovered by you in a VM.

### W25 (fix) — Electron/Chromium runtime under the VM: sandbox and GPU
Even with W24, Chromium-family apps fail in VMs for two known reasons:
1. **SUID sandbox**: `chrome-sandbox` must be root-owned `4755`. The 0900 deb-install hook must `chmod 4755` the `chrome-sandbox` file of each installed app (Aegis Browser `/opt/aegis-browser*/chrome-sandbox`, CoreX, OS Private Chat) — dpkg from the includes path may not preserve it.
2. **GPU absence**: no accelerated GL in a stock VM → Chromium crashes or renders black. Ship an env-guarded fallback: when the session has no GL renderer (or a `AEGIS_VM_MODE=1` boot param / detected VirtualBox/VMware DMI), launch Chromium apps with `--disable-gpu --disable-software-rasterizer-vebose`… concretely: `--disable-gpu` plus `--no-sandbox` **only** if the SUID helper check fails. Put the flags in a tiny wrapper (`aegis-electron-launch`) rather than editing debs, so updates keep working.
3. Probe: after W24's launch probe, assert the window actually mapped (KWin window count includes the app), not just the process — a crashed-after-start process must go red.

### W26 (fix) — Trash opens Files Home, not Trash
`config.json`: `{ "name": "Trash", "cmd": "aegis-files" }` — the Files binary accepts **no path argument** (no arg parsing exists in `apps-main.cpp`), so it always opens Home. The Files sidebar already navigates to `Files.trashUrl()` correctly, so the page itself works.
Fix:
1. Add `--path <url>` argument parsing to `aegis-files` (open the window at that location; default Home when absent).
2. Dock Trash slot: `cmd: "aegis-files --path trash:///"` (config change + launch path passes it through `sh -c` unchanged).
3. Also honor `--path` for "Open folder" actions elsewhere (desktop context menu, W36).
4. Boot-test assert: click the dock Trash slot, screenshot, assert the sidebar Trash row is active (the probe harness already has the dock click map).

### W27 (fix, depends on v0.6.35 W20) — Minimize does something unknown; re-click opens a NEW window
`Dock.qml::launch()` always calls `Util.launch(cmd)` — there is no restore path. Combined with no window tracking, a minimized app can never come back from the dock.
Fix (this is why **W20's KWin window tracking is now a blocker**):
1. KWin script pushes window events (windowAdded/Removed/activeWindowChanged + `minimized` flag + app-id) to `org.aegis.Shell` → `Util.runningCmds` becomes the real window list (keep the QML contract).
2. `Util.activateOrLaunch(cmd)`: if a window with that app-id exists → `workspace.activeWindow = win` / unminimize via the KWin script (`callDBus`); else launch.
3. Dock tile click → `activateOrLaunch`. Minimize animation rides W21 (dock-anchored shrink), so minimize visually "goes somewhere" (into its dock tile) instead of the current unexplained vanish.
4. Probe: launch Files, minimize via KWin shortcut, click dock tile, assert window unminimized + active — file-based verdict like the rest of the harness.

### W28 (fix) — Files properties sheet shows blank fields ("document fields are placeholders")
`filemanager.h::metaFor()` inserts only `name/isDir/tint/label/icon/mime` — but `FilesApp.qml:565-569` binds `info.size`, `info.modified`, `info.path`. Those are always empty.
Fix: populate in `metaFor`: humanized size (`QFileInfo::size()`, B/KB/MB/GB), modified (`lastModified()` local, "12 Nov 2026 14:32"), path (`absoluteFilePath()`; elided in QML already). Recapture `02-files.png` with the properties sheet open and add it to the set so this stays asserted.

### W29 (fix) — Monitor: "0.0 GB of 0.0 GB", empty Cores card, CPU 0.0% forever
The screenshot showed real per-process RSS, so `/proc` is readable — but `MemTotal` and the per-core list parsed to zero/empty on the runner kernel, and the CPU column stays 0.0% (delta needs a settled second sample).
Fix:
1. Debug the parser against the actual `/proc/meminfo` and `/proc/stat` on the ISO (print the raw lines in the probe once, then fix the format handling — e.g. the `MemTotal:  12345 kB` field spacing, `cpuN` lines with 8+ fields).
2. Unit-test `MonitorBackend::refresh()` against fixture files (nobody should ever ship a /proc parser without one).
3. When a source is genuinely unavailable (VM without battery, etc.) **hide the card or show "unavailable"** — never an empty card.
4. Probe asserts: memory total > 0, cores count ≥ 1, CPU% updates between two refreshes.

### W30 (fix) — Settings panes must degrade gracefully and show real data
The panes exist (Displays/Sound/Network/Users all have real code) but in the VM they rendered thin/empty, reading as placeholders:
1. **Displays**: shows "kscreen-doctor not available — no output list". Ensure `kscreen` is in the package list (it is NOT today — plasma-workspace doesn't guarantee it). Render resolution/refresh per output, scale selector, and the **presentation toggle** (see W33).
2. **Sound**: `Sound.sinks` from `wpctl` — in a VM with no audio device the list is empty: show "No output device" with the PipeWire state, not a blank pane. Volume slider must bind the default sink.
3. **Network**: the pane has a Wi-Fi switch + a networks list — but **WPA networks can't be joined**: `Network.connectTo(ssid)` only handles open networks ("WPA networks need a stored secret" note at SettingsApp.qml:1302). In a VM the default NIC is usually **ethernet**, so the wifi list is empty and the whole pane looks dead. Fix properly in W32.
4. **Users**: works via AccountsService; verify in VM (live user has no password set — the "set password" flow must work for the live session).

---

## §2 Feature work from the VM ruling (W31–W37)

### W31 (fix/design) — Settings sidebar icons: replace the colored circles
The panes model is `{ label, tint }` only — the sidebar renders plain tinted circles, not the v1.3-proposed glyphs. The CC tiles already use real glyphs, so the icon set exists. Mapping (same tint, glyph per §6):
Wallpaper → image/mountain glyph · Appearance → palette · Desktop Effects → sparkles/wand · Drivers & Firmware → chip · Displays → monitor · Sound → speaker-wave · Network → wifi · Users → person · Aegis ID rail → existing avatar. Render as outline glyphs (icon theme, not emoji), 18 px in the tint circle or replacing it — match the v1.3 settings sheet; deliver a sidebar screenshot for approval.

### W32 (feature) — Wi-Fi must actually join, Bluetooth must actually pair
Today: no WPA secret flow, no Bluetooth UI at all (util.cpp only powers bluetoothctl on/off). The user cannot connect to anything.
1. **WPA join**: tapping a network opens a password sheet → `nmcli device wifi connect <ssid> password <secret>` (or `nmcli connection add type wifi ...`; keep nmcli as the backend — it's already the data source). Show spinner while connecting, error state on wrong secret, saved networks section with Forget.
2. **Wired section**: VMs have ethernet, not wifi — show the wired device + "Cable unplugged/connected" state so the pane is never dead.
3. **Bluetooth**: device list via `bluetoothctl devices`/`scan on`, pair/trust/connect actions, connected-audio indicator. Put it as a Bluetooth section in the Network pane (and keep the CC tile as a toggle). Pairing dialog with the confirmation code.
4. CC Wi-Fi tile and Settings switch must stay in sync (`refreshLinkStates` already exists — extend it to per-connection state).
5. Probe: in the QEMU runner, join the usermode-network is ethernet-only — so assert the wired section renders and the wifi list reports "No Wi-Fi device" honestly instead of empty.

### W33 (feature) — Drivers & Firmware: the presentation/print/USB/charging manager
User ruling verbatim intent: the Drivers pane should carry what Windows delivers out of the box for laptop life — **presentations (external display/projector), PDFs, printing, scanning, USB, charging**.
The ISO already ships the heavy parts (cups, printer-driver-gutenprint, sane-utils, simple-scan, fwupd, linux-firmware, va-driver-all, mesa) — this is UI wiring plus one package:
1. **Device inventory**: `lspci`/`lsusb`/`lsblk` list with categories (Graphics, Network, Audio, Storage, USB), driver name per device where resolvable, and fwupd status per device.
2. **Printing**: detected CUPS queues + "Add printer" (open the CUPS flow or a minimal add-dialog via `lpadmin -p … -v … -m everywhere`), test page button, queue status. **Add `cups-pdf` to the package list** so "Print to PDF" exists as a printer out of the box — that's the "pdfs" part of the ruling.
3. **Scanning**: `simple-scan` launcher + detected scanner state.
4. **Presentation mode**: one toggle that (a) inhibits sleep/screen-off (powerdevil/org.freedesktop.ScreenSaver inhibit), (b) wakes/extends the external output via `kscreen-doctor` if connected, (c) keeps brightness at max. This is the "presentations using laptops" ask — ship it in Displays pane too as a quick toggle.
5. **Power & charging**: battery status/percent/health via UPower, charging state, plug/battery icon in the top bar reflecting charge level (the top bar battery icon is static today), low-battery notification. VMs without a battery: show "AC power" honestly.
6. **Firmware updates**: `fwupdmgr get-updates` list + refresh button (best-effort, clearly offline-safe).
Probe: assert the pane renders sections even with no devices (VM has few) — never blank.

### W34 (fix + feature) — Aegis ID sign-in: say WHY it failed; wire avatar + username
The sign-in form, states (`working/signedIn/signedOut/error`), error text and Enter-to-submit all exist in code — what's missing is diagnosis and the new backend fields.
1. **Classify errors**: network unreachable vs wrong credentials vs backend 5xx. Surface: "Can't reach the Aegis sync service — check the network" (with a Retry) vs "Wrong email or password". The user's exact complaint: "I don't know whether the backend is connected or not". Add a small backend state line under the form (reachable/last attempt).
2. The chain in the VM was: no Wi-Fi join (W32) → no network → sign-in fails silently-ish. Fixing W32 fixes half of this; the error text makes the rest visible.
3. **New backend capabilities — avatar and username**: the sync backend now supports both. Extend `AegisId` (C++): fetch profile after sign-in (username, avatar URL — download to `~/.cache/aegis/avatar.png`), expose `displayName` and `avatarUrl` as properties. Wire: Settings Aegis ID rail (currently `AegisId.signedIn ? AegisId.email : Util.userName` — switch to username with email as secondary line), the account card, and the lock screen avatar (fall back to the local AccountsService avatar when signed out).
4. Focus check: the email field must take keyboard focus when the sheet opens, and verify typing works in the VM (XKB — this may be the same root cause as "keyboard keys not working", see W35).

### W35 (fix) — Keyboard: type-in-fields and the shortcut dictionary
"Many keyboard keys are not working" is ambiguous — split it:
1. **Typing**: verify text input in Settings fields, Konsole, Files search, Editor, and the XWayland/Electron apps in the VM. If it's a keyboard-layout/grab issue (SDDM → session XKB handoff), fix the session keyboard config (localectl/kwinrc keyboard settings) — include the layout in the boot-test probe by typing into a field and asserting the text appears in a screenshot.
2. **Shortcuts**: the Table-10 dictionary (Meta+W overview, Meta+Ctrl+arrows desktops, Meta+T tiling) currently relies on KWin stock defaults — write them **explicitly** to `kglobalshortcutsrc` so they can't drift with KWin versions, plus the macOS-style set the shell already exposes via DBus: Meta+Space → launcher (`toggleLauncher`), Meta+S → control center (`toggleControlCenter`), Meta+Q → close window, Meta+M → minimize, Meta+D → show desktop.
3. Assert: boot-test injects each binding (`qdbus org.kde.KWin /KWin supportInformation` isn't enough — actually trigger via `kdotool`-style input or the probe's keyboard channel) and asserts the visible state change, file-based verdicts like the rest.

### W36 (feature) — Right-click everywhere it's missing
Desktop (`Desktop.qml` is only a wallpaper `Image` — no input handlers) and Dock have no context menus.
1. **Desktop right-click**: New Folder (in ~/Desktop), Change Wallpaper → Settings/Wallpaper, Display Settings → Settings/Displays, Open Terminal Here, Clean Up (icon sort — once desktop icons exist).
2. **Dock right-click per tile**: New Window (first-party apps), Show/Hide (running), Quit (running), Open Trash (Trash tile → also "Empty Trash" with confirm), plus "Add to Dock…" (web shortcut, W22 of v0.6.35) on the dock background.
3. Keep the Files grid/list menus they already have — consistent item order with the desktop menu (New Folder / Open / Move to Trash / Rename / Properties).

### W37 (process) — Dead-control sweep
The user hit "many buttons … just placeholder" and "many other apps just showing placeholders". The CI probe must own this forever:
1. Produce an **inventory** of every interactive control (CC tiles/rows, Settings panes, app toolbars): control → handler → status (works / placeholder).
2. Anything that cannot be made real in this cycle **must be hidden or visibly marked "Not available in this build"** — no silent dead buttons.
3. Extend the boot-test probe to click the high-traffic controls (CC toggles, DND, Dark Mode, Settings switches) and assert an observable state change (config file/token change), file-based verdict per control.
4. Publish the inventory in `docs/` so the next review can diff it.

---

## §3 Diagnostics requested from the user's VM run

To close the two un-root-caused items (splash, VM specifics):
1. **Which VM** (VirtualBox / VMware / QEMU-KVM) and which GRUB entry (normal or the `nomodeset` one)?
2. `/run/plymouth-boot-debug.log` from a boot where the splash showed terminal lines instead of the mark. grub.conf already carries `quiet splash` + the debug log, and the W14 ladder painted the mark on the CI runner — the likely cause is plymouthd failing to get a DRM surface on the VM's GPU and dropping to console; the log will confirm. If confirmed: pin `plymouth-theme-spinner`'s alternatives priority check into boot-test AND add a VM-candidate fallback (simple `two-step` with `no-vesa`/drm flags, or `plymouth.use-simpledrm` kernel arg on the VM entry).
3. After W24's launch logging: the three files under `~/.local/state/aegis/launch/` for OS/CoreX/Browser.

---

## §4 Carry-overs and rules

- **v0.6.35 (W16–W23) stands unchanged.** W20 (window tracking) and W21 (dock-anchored open/close animations) are prerequisites for W27 here — land them in v0.6.36 together. W16 (Files tints), W17 (Monitor) fold into W28/W29's scope naturally.
- Every fix above gets a probe; a probe that cannot fail is not a probe (v0.6.20 lesson).
- No web tiles in the default dock; W22's opt-in web shortcuts still apply.
- One anatomy for traffic lights; no regression on v0.6.34's wins (boot mark, single terminal header, battery, DND row, real icons).

*Ship order recommendation: W24 + W25 + W26 + W28 first (user-visible breakage with known root causes), then W20 + W27 (tracking + restore), then W31–W36 features, W37 sweep gates the release.*
