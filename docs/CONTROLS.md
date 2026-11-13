# Controls inventory — every interactive surface, its handler, its status

W37 ruling: "Produce an inventory of every interactive control (CC
tiles/rows, Settings panes, app toolbars): control -> handler -> status
(works / placeholder). Anything that cannot be made real must be hidden
or visibly marked. Publish the inventory in docs/ so the next review can
diff it."

Status vocabulary:
- WORKS — real handler, real effect, and where the boot gate proves it,
  the probe is named.
- N/A — deliberately not in this build; the surface says so in copy
  (never a silent dead control).
- BLOCKED — real ask, external blocker, the state is visible in the UI.

The boot gate (scripts/boot-capture.py) clicks the high-traffic controls
and asserts an observable state change; those are marked with their
verdict source. "A probe that cannot fail is not a probe."

## Shell

| Surface | Control | Handler | Status |
| --- | --- | --- | --- |
| Panel | Control Center glyph | `Util.ccOpen` toggle | WORKS — 05-control-center + 05c-cc-shortcut (Meta+S) |
| Panel | Battery glyph + % | binds `Util.batteryPercent/onBattery/charging` (sysfs) | WORKS — VMs read "AC power" |
| Panel | Clock | live `Qt.formatDateTime` | WORKS |
| Dock | 12 app tiles, left click | `Util.activateOrLaunch` — restore-then-launch (W27) | WORKS — 02b-files-restored + the W27 payload verdicts |
| Dock | Tile right click (first-party) | tile menu: New Window / Quit (running) / Empty Trash (Trash) (W36.2) | WORKS — new this cycle; pointer-probed on the next review round |
| Dock | Tile right click (web tiles) | Remove from Dock (`Util.removeWebShortcut`, W22) | WORKS |
| Dock | Add pill | web-shortcut menu (`Util.addWebShortcut`) | WORKS |
| Dock | Trash slot | `aegis-files --path trash:///` (W26) | WORKS — 04j-trash diff gate |
| Island | primary activity accept/decline | `Activity.respondActivity` | WORKS |
| Island | capsule click | opens CC | WORKS |
| Island | auto-hide with a window open | `Util.workspaceWindows > 0` (W20 payload) | WORKS — island assert (home 27 px visible / files 0 px hidden, v0.6.50 gate) |
| Launcher | Meta+Space | aegis-shortcuts KWin script via KGlobalAccel (W35) | WORKS — 01c-launcher-shortcut diff |
| Launcher | search field | filters `Util.allApps` | WORKS |
| Launcher | app tiles / pages | `Util.launch` | WORKS |
| CC | Wi-Fi tile | `Util.setWifiEnabled` (nmcli radio) | WORKS |
| CC | Bluetooth tile | `Util.setBluetoothEnabled` (bluetoothctl power); device surface lives in Settings/Network (D22) | WORKS |
| CC | Calm Mode tile | pins the governor to Tier C + `Activity.calm` | WORKS |
| CC | Dark Mode tile | `Util.setDarkMode` (kdeglobals ColorScheme) | WORKS — dark tile verdict: ColorScheme flips over serial (D26 gate) |
| CC | Do Not Disturb row | `Activity.dnd` | WORKS — 05b-control-center-dnd frame-diff gate |
| CC | volume / brightness sliders | `Util.setVolume/setBrightness` (wpctl / sysfs) | WORKS |
| Desktop | right click | New Folder / Change Wallpaper / Display Settings / Open Terminal (W36.1, v0.6.47) | WORKS |
| Lock | password field | setuid PAM helper `/usr/bin/aegis-auth` | WORKS |
| Notifications | banners | Activity service | WORKS |

## Settings (SettingsApp.qml, §6 pane order)

| Pane | Control | Handler | Status |
| --- | --- | --- | --- |
| Wallpaper | picker grid + cards | `Util.setWallpaper` | WORKS |
| Appearance | accent cards, dark toggle | `Util.setAccent/setDarkMode` (tokens.conf + kdeglobals) | WORKS |
| Desktop Effects | stock effects list | kwinrc writes + KWin reconfigure | WORKS |
| Drivers & Firmware | device inventory (lspci -k with per-device kernel driver, lsusb, lsblk) | `DriversBackend.refresh` (D23) | WORKS — 04m-drivers capture; empty classes render explicit empty lines, never blank |
| Drivers & Firmware | Printing: queues, Test page, Open CUPS | `lpstat -p` / `lp -d` / xdg-open localhost:631 (D23) | WORKS; Print-to-PDF BLOCKED — cups-pdf is gone from the resolute archive (TASKS D16), the pane states it in copy |
| Drivers & Firmware | Scanning: Open scan | `simple-scan` launcher; "ready"/"missing" state | WORKS |
| Drivers & Firmware | Power & charging | `Util.onBattery/batteryPercent/charging` | WORKS — VMs read "AC power" |
| Drivers & Firmware | Firmware: Check | `fwupdmgr get-updates` best-effort (4 s cap, offline-safe) (D23) | WORKS — "unavailable" state is explicit |
| Displays | Presentation mode toggle | `DisplaysBackend.setPresentation` — org.freedesktop.ScreenSaver Inhibit + state file (D21) | WORKS — presentation state file verdict (04l2-displays-on + grep) |
| Displays | per-output resolution menu | `kscreen-doctor output.<name>.mode.<mode>` | WORKS |
| Displays | per-output scale buttons | `kscreen-doctor output.<name>.scale.<s>` | WORKS |
| Displays | Night light | kwinrc NightColor + reconfigure | WORKS |
| Sound | sinks/sources, volume, mute, default | wpctl (PipeWire) with honest "nowpctl/nodevice" states (W30.2) | WORKS |
| Network | wired rows (Connected / Cable connected / unplugged) | NetworkManager DeviceType 1 + Carrier (W30.3) | WORKS — the VM round's ethernet is the proof surface |
| Network | Wi-Fi switch + networks list + WPA join sheet | nmcli / NM D-Bus; secret sheet (W32.1) | WORKS |
| Network | Bluetooth section: adapter state, device rows, Pair/Connect/Disconnect/Forget, Scan | `BluetoothBackend` (bluetoothctl) (D22) | WORKS — "No Bluetooth adapter" is the honest VM state |
| Users | real name rename, admin flag, avatar | AccountsService D-Bus | WORKS |
| Aegis ID | sign in / register / kdf-params with error classification + backend-state line | `AegisId.classifyError` (W34.1) | WORKS — 04b-aegis-id capture |

## First-party apps

| App | Surface | Status |
| --- | --- | --- |
| Files | search, view toggles, sidebar, properties sheet (size/modified/path), kind tints, trash view | WORKS — W16/W26/W28 shipped; tint assert gates the PDF tint |
| Terminal | konsole with the Aegis profile | WORKS — XKB typing probe: typed `touch /tmp/aegis-xkb-ok` produces the file (D24 gate) |
| Monitor | CPU/Memory/Cores/Processes cards | WORKS — monitor card assert (717 accent px) |
| Music / Calculator / Editor | shipped M2/M3 | WORKS |
| Store | search (filters the catalog), categories, Install/Remove | WORKS — `sudo -n apt-get` via the 0610 NOPASSWD hook; 04k-store gate |
| Store | search-index from the real archive, app detail pages, update-all | N/A — recorded for a later round (T14 status note) |

## Keyboard dictionary (W35 — pinned, not assumed)

/etc/xdg/kglobalshortcutsrc pins the stock dictionary with the exact
action ids from the KWin 6.6.0 source; the shell actions ride the
aegis-shortcuts KWin script through KGlobalAccel (kglobalacceld starts
with the session):

| Binding | Action | Source |
| --- | --- | --- |
| Meta+Space | Aegis Launcher (toggleLauncher) | aegis-shortcuts script |
| Meta+S | Aegis Control Center (toggleControlCenter) | aegis-shortcuts script |
| Meta+Q (Alt+F4 kept) | Window Close | kglobalshortcutsrc pin |
| Meta+M | Window Minimize | kglobalshortcutsrc pin |
| Meta+D | Show Desktop | kglobalshortcutsrc pin |
| Meta+W | Overview | kglobalshortcutsrc pin |
| Meta+T | Edit Tiles | kglobalshortcutsrc pin |
| Ctrl+Meta+arrows | Switch One Desktop Right/Left/Up/Down | kglobalshortcutsrc pin |

## Blocked / not-available ledger

| Ask | Status | Where it shows |
| --- | --- | --- |
| Print to PDF (cups-pdf) | BLOCKED — package gone from the resolute archive (D16); waits for a reintroduction or a locally built deb | Drivers pane copy |
| Dock-anchored minimize animation | N/A on 6.6 — JS effects get only windowAdded/Closed/Activated (verified against the 6.6.0 source); the stock squash effect animates minimize/restore instead | kwinrc comment + TASKS D20 |
| Store: real-archive search index, detail pages, update-all | N/A — curated catalog this round | T14 status note |
| Live greeter | N/A — the live ISO autologins; the greeter path is asserted on an installed boot only (greeter_assert unwired by design) | boot harness note |
