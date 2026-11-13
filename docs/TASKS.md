# TASKS — Aegis OS work orders

This file is the cross-session memory. Every task gets a number; the status
vocabulary is TODO / DOING / DONE (in tree) / SHIPPED (in a release tag).
Update it after every step so a context cycle, session refresh or crash
cannot lose the plan.

- Repo: github.com/abdul-mateen-14/AEGIS-OS, local checkout
  /home/z/my-project/work/AEGIS-OS
- Release flow: push main -> tag vx.y.z -> Release CI builds the ISO ->
  Boot Test is triggered manually with workflow_dispatch (inputs.tag) on a
  GitHub runner -> captures land in docs/screenshots/<tag>/ on main
- Pre-push: run scripts/qml-guard.py, keep commit messages free of
  backticks, git pull --rebase before pushing (boot tests commit to main)

---

## T14 — v0.6.42: the Store (user request) (DOING)

Opened 2026-11-12 from the user ruling: "add an appstore with all the
famous ubuntu and debian etc apps".

- D1 DONE — StoreBackend (systembackends.h): one curated catalog of 20
  famous archive apps (VLC, GIMP, Inkscape, Blender, Krita, Audacity,
  OBS Studio, LibreOffice, Thunderbird, Firefox, Telegram Desktop,
  FileZilla, Transmission, KeePassXC, Flameshot, GParted, Synaptic,
  htop, Kate, Git — every one in the Ubuntu/Debian archive, nothing
  from third-party repos), dpkg-query for the installed state, install/
  remove through sudo -n apt-get (NOPASSWD via 0610), the output
  streamed to ~/.local/state/aegis-shell/aegis/store/<id>.log and the
  status line. Category tints ride the §8.1 palette.
- D2 DONE — StoreApp.qml: sidebar (search + categories) + cards with
  letter tiles in the category tint, Install/Working…/Installed
  buttons (Remove on installed), the status bar. Rides aegis-apps;
  the store icon (aegis-store) ships in the Aegis theme.
- D3 DONE — wiring: aegis-store wrapper + CMake install(PROGRAMS) +
  aegis-store.desktop + apps-main store->StoreApp.qml + the Store
  singleton registered (Aegis.Store/Store) + the dock slot (Store
  after Monitor — 12 tiles, tray 730 px) in config.json AND the
  util.cpp defaultConfig mirror; the boot harness gained the
  04k-store capture (click_idx 9; Settings -> 10, Trash -> 11) and
  the gate grew the store key.

### Status

- SHIPPED IN TREE (v0.6.42 tag next). The boot run verifies the store
  opens with the catalog rendered. NOT in this cycle: a search-index
  from the real archive (the catalog is curated), app detail pages,
  update-all — recorded for a later round if the reviewer wants them.

---

## T13 — v0.6.39-v0.6.50: VM usage round — W24-W37 (batch 1 SHIPPED, batch 2 DOING)

Opened 2026-11-12 from the first REAL-VM usage report of v0.6.34
(docs/REVIEW-v0.6.36-VM.md, committed verbatim — behavior evidence, not
pixels). The reviewer's scope note: W16-W23 still stand; this adds
W24-W37. TRIAGE against what already shipped in T12 (v0.6.35-v0.6.38):

- ALREADY DONE (the reviewer reviewed v0.6.34 in the VM):
  - W29 = T12 D1 (W17): the /proc atEnd trap was found and fixed, the
    unavailable states shipped, the boot gate asserts the Monitor cards
    (719 accent px on the last full green run). The reviewer's "print
    the raw lines in the probe once" debugging pass was replaced by the
    POSIX-level root cause + the pixel gate.
  - W20 prerequisite = T12 D8, with FOUR shipped-green-class breaks
    found and fixed by the boot gate (kwinrc key shape, DBus path,
    resourceClass filter for the shell's own layer surfaces which DO
    pass normalWindow on 6.6, and the callDBus double-vs-int
    marshalling — the contract is now ONE JSON string). The island
    auto-hide chain verification is the ONLY item still open: run 7
    (v0.6.38) showed the island NOT hiding with a window open while
    every other assert is green. Debug instrumentation ships with T13:
    Util.windowListRaw() (the last raw JSON payload the script pushed)
    + the window-state dump reads the DBus address from the
    aegis-shell environ (the first pgrep match was the
    dbus-run-session parent, whose environ lacks the address).
  - W22 (web shortcuts) = T12 D10, shipped.
  - W16/W17 fold into W28/W29 as the review says — W16 shipped (tint
    gate 395 px green), W28 is NEW (the properties fields below).
- T13 batch 1 (this cycle, the reviewer's own ship order: W24+W25+W26+
  W28 first, then W20/W27):
  - D1 (W24): the three deb apps cannot launch — dock cmd is a bare
    command head that is not on PATH. findInstalledEntry already parses
    the winning .desktop: also return the full Exec= string; resolve:
    true slots launch that full quoted Exec (QProcess::splitCommand
    semantics), bare cmd only as the fallback; wrap every Tier B launch
    with a timestamped log at ~/.local/state/aegis/launch/<app>.log
    (last 50 lines); boot-test probe per Tier B app (pgrep the Exec
    head + the existing capture).
  - D2 (W25): electron/Chromium under the VM — chmod 4755 the
    chrome-sandbox of each installed electron app in the 0900 hook; an
    aegis-electron-launch wrapper adds --disable-gpu (and --no-sandbox
    only when the SUID check fails) when in a VM; the W24 probe asserts
    the window MAPPED, not just the process.
  - D3 (W26): Trash opens Files Home — aegis-files gains --path <url>
    parsing (apps-main argv), the Trash dock slot becomes
    aegis-files --path trash:///, the boot test clicks Trash and
    asserts the sidebar Trash row active.
  - D4 (W28): the Files properties sheet binds info.size/modified/path
    which metaFor never populates — add humanized size, local
    timestamp, absolute path; recapture 02-files with the sheet open.
  - D5 (W20 finish + W27): windowListRaw() instrumentation + the dump
    fix; on green, W27 (activateOrLaunch + unminimize via the script)
    rides the same tracking.
- T13 batch 2 (NEXT cycle, recorded so nothing is lost): W30 (Settings
  panes degrade gracefully: kscreen package, Sound empty-state, wired
  section), W31 (sidebar glyphs), W32 (WPA join + bluetooth UI), W33
  (Drivers pane: printing/cups-pdf/scan/presentation/charging), W34
  (Aegis ID error classification + avatar/username), W35 (keyboard:
  XKB verify + explicit kglobalshortcutsrc), W36 (desktop context
  menu), W37 (dead-control sweep + inventory in docs/).

### Status

- D19 — v0.6.50 BOOT TEST GREEN. THE FULL GATE PASSED FOR THE FIRST TIME
  SINCE THE TIER B APPS JOINED IT. Eleven apps open with diffs: files
  20.8, terminal 22.4, settings 20.7, music 15.6, calculator 6.8,
  editor 15.3, monitor 14.6, browser 53.7 (attempt 0 — wrapped resolved
  Exec /usr/bin/aegis-browser-stable %U), os 29.5 (attempt 0),
  COREX 39.2 (attempt 1, the dock click — the capture 04i-corex.png
  shows the real CoreX window with its own honest offline page, the
  runner VM has no network, the same ERR_INTERNET_DISCONNECTED class as
  os), store 19.4, trash 23.8. Asserts: header geometry PASS, tint 395,
  monitor 717, island 27/0, magnify 4/28. Screenshots zip attached to
  the v0.6.50 release and committed to docs/screenshots/v0.6.50/.
  W24/W25/W26/W28 + the W20 island chain + W21 magnify: ALL SHIPPED AND
  PROVEN. T14 (the Store) rides green since v0.6.42 (SHIPPED — the
  04k-store capture is in the v0.6.50 set). Batch 2 progress in tree
  (D11-D18): Sound honest states, the wired Network section, the §6
  sidebar glyphs, the WPA join sheet, the Aegis ID failure
  classification + backend-state line, the desktop right-click menu,
  kscreen packaged, the CoreX quoted-Exec fix end to end. CoreX needed
  eleven boot runs, two ISO reds, one session abort, and a quote — the
  entry is now matched, the wrapper engaged, the sandbox flags reach
  electron.

### batch 2 finish — v0.6.51-v0.6.53 (DOING; opened 2026-11-13)

The v0.6.50 green run unblocked the rest: the W20 island chain is
proven, so W27 rides now. Everything below was verified against the
KWin 6.6.0 source (github.com/KDE/kwin, tag v6.6.0) before planning:
scripts get registerShortcut as a global (scripting.cpp:241,376,
KGlobalAccel-backed), constructible QTimer (scripting.cpp:218),
LIVE readConfig (Script::config() = kwinApp()->config()->group —
Options line 86 installs KConfigWatcher on that shared config, so
external writes reparse), workspace.activeWindow is WRITABLE and
Window.minimized is WRITABLE (window.h:397) — but JS EFFECTS get none
of the mutation API (scriptedeffect.cpp injects effects/effect/static
KWin only) and expose only windowAdded/Closed/Activated to JS, so the
activation executor MUST be the windowwatch SCRIPT and the minimize
animation cannot be dock-anchored from our JS effect on 6.6.

- D20 (W27) — activateOrLaunch: the windowwatch payload grows allIds
  (trackable incl. MINIMIZED — ids stays visible-only for the island
  predicate) and active (the resourceClass of workspace.activeWindow).
  A 150 ms QTimer polls readConfig(ActivateSeq); the shell's
  activateOrLaunch(cmd) writes kwinrc [Script-aegis-windowwatch]
  ActivateRequest/ActivateSeq when the head is in allIds (the same
  QSettings+KConfigWatcher transport the TileMap already proves), else
  launches. Dock tile click switches to activateOrLaunch(cmd, launch).
  Minimize/restore animation: enable the stock squash effect (its whole
  purpose); the dock-anchored shrink stays blocked by the 6.6 JS API —
  recorded, not hidden. Harness: open Files, minimize via the pinned
  Meta+M, dump state (count drops, ids without files, allIds WITH
  files), click the Files tile, dump again (active == aegis-files).
- D21 (W30.1 UI half) — the Displays pane keeps its per-output rows
  (resolution menu, scale buttons — both already shipped) and gains the
  PRESENTATION toggle: ScreenSaver Inhibit via org.freedesktop.ScreenSaver
  (cookie kept), brightness to max and restored, state persisted to
  ~/.local/state/aegis-shell/aegis/presentation for a file-based
  verdict. Harness: aegis-settings 4 capture with the toggle clicked.
- D22 (W32.3) — BluetoothBackend: bluetoothctl show / devices Paired /
  info per device; connect/disconnect/pair/trust one-shot commands;
  scan best-effort; honest "No Bluetooth adapter" state (the VM round).
  Bluetooth section at the bottom of the Network pane; the CC tile
  keeps toggling power via Util.setBluetoothEnabled.
- D23 (W33) — the Drivers & Firmware pane stops being the static
  BUILT-IN placeholder list (the W37 poster child): DriversBackend with
  lspci -k device categories + "Kernel driver in use", lsusb, lsblk,
  lpstat print queues + test page + Open CUPS, simple-scan launcher,
  Power & charging (UPower sysfs — Util already reads it; VMs read
  "AC power" honestly), fwupdmgr get-updates best-effort (3 s cap),
  Print-to-PDF shown as "not available — cups-pdf missing from the
  archive" (D16). Every section renders an explicit empty state; never
  blank. Harness: aegis-settings 3 capture.
- D24 (W35) — keyboard: etc/xdg/kglobalshortcutsrc pins the stock
  dictionary with the EXACT action ids from kwin 6.6 source (useractions
  .cpp initShortcut + virtualdesktops.cpp addAction + overvieweffect
  "Overview" + tileseditoreffect "Edit Tiles"): Window Close=Meta+Q
  (Alt+F4 kept — the harness closes with it), Window Minimize=Meta+M,
  Show Desktop=Meta+D, Overview=Meta+W, Edit Tiles=Meta+T, Switch One
  Desktop Right/Left/Up/Down=Ctrl+Meta+arrows. A NEW kwin script
  aegis-shortcuts registers the shell actions through
  registerShortcut("Aegis Launcher", Meta+Space -> toggleLauncher) and
  ("Aegis Control Center", Meta+S -> toggleControlCenter) — they land
  in kglobalshortcutsrc as file-assertable state; aegis-session starts
  kglobalacceld (ships via plasma-workspace Depends, kglobalacceld
  >= 6.2.90). The typing probe: after Terminal opens the harness types
  touch /tmp/aegis-xkb-ok RET over the keyboard channel and greps the
  file over serial — the XKB end-to-end proof. Plus launcher/control-
  center captures via the pinned Meta+Space/Meta+S.
- D25 (W21 hygiene, from D15's konsole.log note) — publishDockTileMap's
  JSON rides QSettings IniFormat which escapes the quotes as \" — an
  INVALID KConfig escape ("Invalid escape sequence «\"»" in the guest
  journal, twice at session start). The TileMap format becomes
  quote-free "id=cx,cy;id2=cx,cy" — writer (util.cpp), builder (Dock
  .qml) and reader (dockzoom main.js) change together; the warning dies
  at the source.
- D26 (W37) — the dead-control sweep: docs/CONTROLS.md inventories every
  interactive control (control -> handler -> status: works / hidden /
  not-available); anything unreal gets hidden or visibly marked; the
  harness clicks the CC dark-mode tile and asserts the kdeglobals token
  flips over serial (DND already has its capture), the Drivers pane
  placeholder is dead no more (D23).
- D27 — boot run + ship v0.6.51.
- D28 — v0.6.51 BOOT RUN RED, three root causes in one artifact chain
  (run 43361014310, failed at the T7 header assert):
  1. THE SHORTCUT PINS WERE INVISIBLE. The harness Meta+M dumped the
     payload with count=1, ids still carrying aegis-files — the window
     never minimized, because Meta+M is NOT a stock KWin binding and the
     pinned dictionary never loaded: kglobalacceld opens
     kglobalshortcutsrc with KConfig::SimpleConfig (= 0x00, "just a
     single config file" — verified against kconfig.h:97), so /etc/xdg/
     is NOT in its cascade. FIX: aegis-session seeds
     $HOME/.config/kglobalshortcutsrc from /etc/xdg before the daemon
     starts, and the file's defaults field is lowercase "none" (the
     daemon's keysFromString compares "none" case-sensitively and an
     invalid default would insert an empty QKeySequence). The aegis
     -shortcuts RUNTIME registrations were never in doubt: the launcher
     capture diffed 23.6 vs home — Meta+Space genuinely opened the
     launcher through KGlobalAccel.
  2. THE ACTIVATION RACE. After the dock click the payload read active:
     "" — the click's own focus processing undid the one-shot
     workspace.activeWindow = w. The trailing alt+F4 then fired on NO
     active window (kglobalacceld grabs Alt+F4 for kwin's Window Close —
     the app-level Qt theme shortcut never sees it once the daemon
     owns the binding), files stayed on screen, and the header assert's
     hairline detector picked up FILES' top edge at y=105, 7 px above
     the real terminal top at y=112 — "terminal dot drop 27.5" was the
     wrong window's anatomy, not a caption regression (the terminal dot
     cy is 132.5 in BOTH runs; measured on both captures).
     FIX: the script keeps the request PENDING for ~1.2 s and re-applies
     it every tick while the active class does not match (self-healing;
     a foreign focus change after the settle wins). The harness dumps
     the kwinrc request line as a diagnostic.
  3. THE BLUEZ STALL. BluetoothBackend's constructor ran bluetoothctl
     show on EVERY apps-main launch; with no adapter the DBus activation
     waited toward the 25 s system-bus timeout (fwupd triggered it, the
     journal shows the bluez service skipped on
     ConditionPathIsDirectory=/sys/class/bluetooth). FIX: the backend
     mirrors the unit's own condition — no /sys/class/bluetooth, no
     bluetoothctl round trip, straight to the honest "noadapter" state.
  Ship: v0.6.52 = the three fixes + nothing else; the choreography
  returns to the proven path once Meta+M actually minimizes.
- D29 — v0.6.52 BOOT RUN RED, postmortem on run 43365428240 (four
  assert failures, all four diagnosed against the artifacts; the rest
  of the gate is the GREENEST EVER):
  1. THE W27 PAIR RAN ON NO DATA. All three dump_window_state calls
     died at "Expecting value: line 1 column 1 (char 0)" — the
     harness parser only handled the bare-quote busctl form, but
     busctl prints string replies as: s "{\"count\":0,...}" (the
     TYPE LETTER first, then the string quoted with inner quotes
     escaped — captured verbatim in the v0.6.50 raw diag). json.loads
     failed on the leading s, dump_window_state returned None, and
     both W27 verdicts defaulted false. The chain itself was ALIVE:
     the island assert passed (home 27 px visible, files 0 px hidden)
     and the activate-request kwinrc dump showed the shell writing
     ActivateRequest=aegis-files / ActivateSeq=1 — the shell side of
     activateOrLaunch worked on the first try. FIX: the parser strips
     the s prefix, unquotes in the safe order (protect \\, unquote
     \", restore \\), returns None only for a genuinely empty payload
     (no push yet at idle home) and logs a raw excerpt when parsing
     still fails. Whether Meta+M actually minimized stays UNKNOWN
     until the next run reads the real payload.
  2. THE PRESENTATION CLICK WAS 152 PX OFF. The modeled point
     (434, 207) assumed pane content at y157, but the capture
     (04l2-displays-on.png) puts the GlassSwitch indicator at
     (433, 359): the AppWindow anatomy is 44 px titlebar + 52 px
     opaque toolbar strip, and the pane body sits lower still — the
     model missed the toolbar layer entirely. X was right (434 inside
     the 415-452 pill), Y was never close. The click is now
     SELF-CALIBRATING: the GlassSwitch knob is a 20 px pure-white
     blob (255,255,255; the fg text tops out at 242 — measured), the
     scan finds it in the indicator column, clicks it, re-scans after
     the toggle (the knob moved to the track's right end) and clicks
     again; fallback (433, 359) from the v0.6.52 measurement.
  3. THE DARK TILE CLICK WAS NEVER THE PROBLEM. 05c-dark-toggled.png
     shows Dark Mode UNCHECKED and the CC sheet re-rendered LIGHT
     glass — the click at (1172, 234) landed and Util.setDarkMode
     ran; 2.5 s later ~/.config/kdeglobals still read AegisDark. The
     QSettings(kdeglobals, IniFormat) write did not land and the
     precise failure mode is UNPROVEN (no local Qt to repro; the
     skeleton file carries # comment lines that QSettings may not
     treat as comments, but any successful sync would have rewritten
     the token regardless — so the write itself did not reach disk).
     FIX (removes the variable): util.cpp setDarkMode now does a
     deterministic QSaveFile rewrite — read the file, replace ONLY
     the ColorScheme line inside [General] (insert into [General]
     when absent, append a section when the file is empty), commit
     atomically, everything else byte-for-byte preserved (the W18
     comment pins ride along) — and mirrors the rung into a theme
     state file ~/.local/state/aegis-shell/aegis/theme (dark|light,
     the same GenericStateLocation pattern as the presentation file).
     qWarning on both failure branches.
  4. THE GATE GREW THE MATCHING VERDICTS. The dark-tile probe now
     rm -f's the theme file first, reads the state file after the
     click (the shell-applied channel) and POLLS the kdeglobals
     token up to three times (the config-write channel); both must
     pass or the assert names which channel failed. The diag section
     gained ===USER-KDEGLOBALS=== (ls -la + cat of ~/.config/
     kdeglobals — ownership answers the write-permission question,
     content answers the write). The two greps in the old probe
     defined _token AFTER its first use (latent NameError on the
     retry path) — fixed.
  5. KNOWN-BENIGN, RECORDED: the click-map rebuild failed again with
     "Coordinate 'right' is less than 'left'" — it also failed on the
     v0.6.50 GREEN run; the config map (12 tiles) matches the guest
     and every dock click landed, so the fallback is correct. Not
     chased this cycle.
  Everything else in run 43365428240 was GREEN: header geometry PASS,
  xkb typing PASS (D28's kglobalshortcutsrc seed works — typed
  keystrokes land in konsole), all six probes CLEAN, tint 395 /
  monitor 801 / island 27-0 / magnify 4-28, all eleven app opens
  with diffs (browser 11.9 attempt 0, os 29.5, corex 39.2 attempt 1,
  store 19.4, trash 23.8), launcher + CC shortcut captures green,
  MARK SPLASH CONFIRMED. v0.6.53 = these fixes only.
- D30 — v0.6.53 BOOT RUN: run 43383015905, ONE assert left red, and
  it exposed the deepest defect of the cycle. ELEVEN OF TWELVE GATES
  GREEN, including all three D29 fixes PROVEN:
  1. THE PARSER FIX WORKED. window-state dumps parse: home
     {"count":0,"ids":[],"allIds":[],"active":""}; after Meta+M
     {"count":0,"ids":[],"allIds":["aegis-files"],"active":""} —
     W27 MINIMIZE PASSED: the D28 kglobalshortcutsrc seed WORKS
     (Meta+M really minimizes), the payload contract (allIds keeps,
     ids loses, active empties) is exact.
  2. THE KNOB SCAN WORKED. presentation knob scan: (425, 358),
     clicked, state file ON — W30.1 PASSED (the v0.6.52 modeled
     point was 152 px off; self-calibration is immune to the pane
     layout).
  3. THE QSaveFile REWRITE WORKED. dark tile verdict:
     AegisDark -> AegisLight + state file light — W37 PASSED, and
     this also proves the v0.6.52 failure was the QSettings write
     itself (the click had always been fine).
  4. THE LAST RED: W27 RESTORE. The shell wrote the request (kwinrc
     dump: ActivateRequest=aegis-files, ActivateSeq=1), the script
     was alive (markers: "js: aegis-windowwatch: activate poll
     armed" + "loaded" in the session log), the JS is valid against
     the 6.6 wrapper (stackingOrder IS a Q_PROPERTY —
     workspace_wrapper.h:66; activeWindow WRITE :34; minimized
     WRITE window.h:397; isMatchable accepts minimized) — and the
     window never came back (02b-files-restored diff 3.2 = no
     window on screen). ROOT CAUSE, verified against the kconfig
     v6.13.0 + kwin 6.6.0 sources: KConfigWatcher is NOT a
     filesystem watcher. It subscribes to the org.kde.kconfig.notify
     ConfigChanged DBus signal (kconfigwatcher.cpp:89-94) which ONLY
     KConfig-based writers emit — the signal rides KConfig::sync
     (kconfig.cpp:506-508). QSettings never sends it, so EVERY
     QSettings write to kwinrc since v0.6.39 has been invisible to
     KWin: the windowwatch poll kept reading the load-time
     ActivateSeq=0, and the dockzoom effect's TileMap was equally
     dead (the "the TileMap already proves this transport" claim in
     the D20/D21 comments was wrong — no gate ever exercised it).
     FIX (two halves): (a) util.cpp nudgeKWinConfig() — after every
     kwinrc write (activateOrLaunch, publishDockTileMap) the shell
     fires an async org.kde.KWin.reloadConfig on the session bus;
     verified chain dbusinterface.cpp:48 -> Workspace::slotReload
     Config -> reconfigure() -> 200 ms timer -> slotReconfigure ->
     kwinApp()->config()->reparseConfiguration() (workspace.cpp:979,
     996) — exactly the shared config Script::config() reads, so the
     script's next 150 ms tick sees the new ActivateSeq.
     (b) aegis-dockzoom main.js — readMap() now runs at the start of
     growFromTile AND shrinkIntoTile: the reparse refreshes the
     shared config but does NOT emit the effects' notify-based
     configChanged (effecthandler.cpp:153 wires effect configChanged
     to KConfigWatcher, not to reparse), so the per-animation re-read
     is the only way the effect sees a mid-session TileMap update.
     Stale comments corrected in util.h/util.cpp. v0.6.54 = these
     two fixes + nothing else.

### Status

- SHELL CI CAUGHT ONE (run 43357952556, red on 50f5a55): the resolved
  Exec parameter of activateOrLaunch was named launch — it shadowed
  Util::launch and the call compiled as a call on a QString. Renamed to
  resolved (a8ee138); CI green on run 43358278199. Lesson: the local
  audit checks JS and QML but not C++ — qml-guard's range does not
  cover the shadowing class of error; the CI compile IS the C++ gate.
- D20-D26 IN TREE (v0.6.51 tag next). D20: the payload carries allIds +
  active; the 150 ms poll executor is armed in the windowwatch script
  (marker: "aegis-windowwatch: activate poll armed"); Util
  .activateOrLaunch writes [Script-aegis-windowwatch] (argumented cmds
  like the Trash slot NEVER activate — head == cmd only); the dock tile
  click rides it; squash is enabled for the minimize/restore animation.
  D21: the presentation toggle (ScreenSaver inhibit + the state file)
  sits first in the Displays pane. D22: BluetoothBackend + the Network
  pane section (honest noadapter/off/empty states). D23: the Drivers
  pane is the real inventory (pci/usb/storage/printers/scan/firmware;
  cups-pdf stated as blocked in copy). D24: kglobalshortcutsrc pins the
  stock dictionary (exact ids from the 6.6.0 source), aegis-shortcuts
  registers Meta+Space/Meta+S, aegis-session starts kglobalacceld, the
  harness types touch /tmp/aegis-xkb-ok into the focused terminal. D25:
  TileMap is quote-free head=cx,cy pairs. D26: docs/CONTROLS.md
  published; the dock tile menu (W36.2 New Window/Quit/Empty Trash —
  right-click was a silent no-op) landed with Util.quitApp/emptyTrash;
  the CC dark tile has its kdeglobals verdict. Harness additions: the
  W27 minimize/restore payload probe, the XKB typing probe, the
  launcher + CC shortcut captures, the Displays pane toggle click +
  state-file grep, the Drivers pane capture, the dark tile click + token
  grep — five NEW gate keys (w27_minimized, w27_restored, xkb_ok,
  presentation_on, dark_flipped). QEMU qcode audit: the Meta key is
  meta_l (there is no plain meta — verified against pc-bios/keymaps/
  en-us), spc/slash/minus/ret/esc confirmed.
- BATCH 1 SHIPPED (v0.6.50):
  - D1 (W24) DONE: findInstalledEntry returns the full Exec=; dockApps
    carries it as the slot's launch field (cmd stays the bare head for
    isRunning/tracking); the dock tile launches modelData.launch first;
    every Util.launch appends a timestamped line + the process output to
    ~/.local/state/aegis/launch/<head>.log (rotated to 50 lines); the
    boot harness resolves the Exec from the guest's .desktop entry for
    the Tier B probes (launch_cmd="desktop") and the release gate grew
    browser/os/corex keys; a ===LAUNCH-LOGS=== diag dumps the logs in CI.
  - D2 (W25) DONE: the 0900 hook chmods 4755 every chrome-sandbox under
    /opt; /usr/bin/aegis-electron-launch guards electron launches
    (--disable-gpu in a VM via DMI/AEGIS_VM_MODE, --no-sandbox only when
    the SUID bit is missing); dockApps wraps the Exec when a
    chrome-sandbox sits next to the binary (splitCommand — the CoreX
    path has a space); the diff-vs-home probe is the window-MAPPED proof.
  - D3 (W26) DONE: aegis-files parses --path <url> (apps-main argv -> a
    aegisInitialPath context property -> navigateTo on completion);
    the Trash slot is aegis-files --path trash:/// in config.json AND
    the util.cpp defaultConfig mirror; the boot test clicks the Trash
    tile and captures 04j-trash.
  - D4 (W28) DONE: propertiesOf is URL-defensive (a file:// input read
    as size 0 + epoch mtime — the placeholder look), GB tier added, the
    modified format is the v1.3 "d MMM yyyy HH:mm". The fields were
    already populated since 299e521 — the review's metaFor citation was
    the wrong function; the defensive fix + capture cover the report.
  - D5 (W20 instrumentation) DONE: Util.windowListRaw() returns the last
    raw payload the script pushed (empty = the push never arrived); the
    window-state dump takes the DBus address from the aegis-shell
    environ (the aegis-session grep matched the dbus-run-session parent).
  - W27 (activateOrLaunch) rides the SAME tracking — deferred to batch 2
    until the island chain is proven green (run 7 left it open).
- T13 batch 2 (NEXT cycle, recorded so nothing is lost): W30 (Settings
  panes degrade gracefully: kscreen package, Sound empty-state, wired
  section), W31 (sidebar glyphs), W32 (WPA join + bluetooth UI), W33
  (Drivers pane: printing/cups-pdf/scan/presentation/charging), W34
  (Aegis ID error classification + avatar/username), W35 (keyboard:
  XKB verify + explicit kglobalshortcutsrc), W36 (desktop context
  menu), W37 (dead-control sweep + inventory in docs/).

---

## T12 — v0.6.35: reviewer round 5 — W16-W23 (SHIPPED)

Opened 2026-11-12 from the uploaded review of v0.6.34
(docs/REVIEW-v0.6.35.md — committed verbatim, rulings quoted from it).
Scope: 4 fixes + 1 verify + 1 carry-over, 3 features, 4 test gaps.
Work order below is dependency-aware; the review's own order is W16-W23.

### Subtasks

- D1 — W17 Monitor honesty (review §2): the v0.6.34 04f capture shows an
  EMPTY Cores card and "0.0 GB of 0.0 GB" Memory while the process table
  renders real RSS — so /proc reading works but the meminfo and per-core
  parsers are broken. Fix the parsers (MemTotal KiB->GB, per-core from
  /proc/stat); when a source is unavailable hide the card or show an
  explicit unavailable placeholder — never a blank card. Assert lands
  with W23.3.
- D2 — W18 font pin (review §2): etc/xdg/kdeglobals has no [WM]
  activeFont and no [General] font, so captions and Qt widgets fall back
  to the session default instead of Montserrat 13 DemiBold / Montserrat
  10. Ship the Qt6 KConfig serialization (Montserrat,13,-1,5,600,... /
  Montserrat,10,-1,5,400,...); W23.1 asserts the keys exist, the
  terminal caption crop re-checks the glyphs.
- D3 — W19 GTK decoration layout (review §2): gtk-decoration-layout=
  close,minimize,maximize: into gtk-3.0 AND gtk-4.0 settings.ini — skel
  AND the aegis-gtk-sync writer in hook 0810.
- D4 — W16 Files kind tints (review §2): image://icons gets a ?tint=
  query param and the provider recolors the SVG stroke at request time;
  document kinds map to document glyphs (PDF -> doc-page #FA2D48,
  archive -> box #FF9F0A, text -> doc-line #3E8BFF; folder/image/audio/
  video unchanged). Assert = W23.3 tint check on report.pdf.
- D5 — V1 dock magnification clip (review §2): the pill padding must
  grow by the magnification delta (Files clipped at the left edge in
  01b-dock-magnify.png). W23.4 adds the magnified capture + assert.
- D6 — carry-over (review §2): add the 18 px Aegis mark to the Control
  Center header and Settings (v1.3 ruling stands; say so in the release
  notes so the reviewer can close the item).
- D7 — W23 test gaps (review §4): (1) parse the ===KWINRC=== dump and
  FAIL the release on decoration drift (theme, ButtonsOnLeft, BorderSize
  — the v0.6.20 class of shipped-green regressions); (2) capture the
  SDDM greeter between splash and session + pixel assert (mark present,
  progress line present — boot-14/15 are pure black today); (3) the
  W16 tint assert and W17 monitor-card assert in the probe verdicts;
  (4) the magnified-dock capture.
- D8 — W20 island auto-hide (review §3): real window tracking first —
  a shipped KWin script (workspace.windowAdded/Removed/activeWindow-
  Changed) counts normal windows on the active workspace + maximized/
  fullscreen flag and pushes org.aegis.Shell.windowListChanged(count,
  anyFull); Util keeps the QML contract (isRunning / runningCmdsChanged)
  and drops the launch-recorded backing store (closes the util.h:100
  gap; dock running dots start working for foreign-launched apps).
  Island behavior: idle island hides when the active workspace has a
  window; hide = scale 1->0 transformOrigin Center + fade ~200 ms
  InCubic; show on any non-idle activity (notification/charging/timer/
  Aegis-ID/nowPlaying) or empty workspace again (~320 ms OutBack grow);
  activity states ALWAYS win over the window predicate.
- D9 — W21 dock-anchored open/close (review §3, lands after D8): KWin
  scripted effect aegis-dockzoom — open grows scale 0.3->1 from the
  dock tile center ~280 ms OutCubic, close/minimize reverse ~200 ms
  InCubic; shell publishes app-id -> icon-rect map via DBus or
  $XDG_RUNTIME_DIR/aegis/dock-map.json; normal windows only, never
  layer-shell surfaces or popups. Fallback if the scripted effect is
  unstable on 6.6: stock kwin4_effect_scale ~240 ms center origin
  (documented, acceptable).
- D10 — W22 web shortcuts, strictly opt-in (review §3): zero web tiles
  in the default dock (W9 holds); Add to Dock... flow (paste URL ->
  fetch title + apple-touch-icon/favicon.ico/letter-tile fallback ->
  ~/.local/share/aegis/webicons/<hash>.png + aegis-web-<hash>.desktop
  with Exec=xdg-open), remove deletes both files, user entries append
  after the last first-party slot before Trash. Dedupe ALL .desktop
  walkers by StartupWMClass/Exec basename (the browser deb ships two
  identical entries — aegis-browser.desktop + org.aegisbrowser.Aegis).
- D11 — release: qml-guard -> commit -> pull --rebase -> push -> tag
  v0.6.35 -> Release CI -> Boot Test inputs.tag v0.6.35 -> verify the
  extended capture set (greeter, magnify, tint, monitor cards, kwinrc
  assert) -> close T12.

### Status

- SHIPPED IN TREE (v0.6.35 tag next) — the full D1-D10 batch:
  - D1 (W17): ROOT CAUSE found and proven — /proc files stat to size 0,
    so QFile::atEnd() is true immediately and every while(!in.atEnd())
    loop over /proc/stat, /proc/meminfo and /proc/net/dev read NOTHING
    (empty Cores card, cpu 0.0, "0.0 GB of 0.0 GB" — while the process
    table worked because it does per-pid readLine with no atEnd). All
    three loops rewritten to the readLine-until-null pattern; the trap
    proven with a standalone POSIX check (stat 0 B, real bytes > 0).
    MonitorApp.qml grew the honest states (em-dash + "unavailable",
    "per-core usage unavailable") so a dead source can never render as
    a lie again.
  - D2 (W18): kdeglobals [WM] activeFont=Montserrat,13,-1,5,600,0,0,0,0,0
    and [General] font=Montserrat,10,-1,5,400,0,0,0,0,0 (Qt6 KConfig
    serialization, OpenType weight scale).
  - D3 (W19): gtk-decoration-layout=close,minimize,maximize: in BOTH
    settings.ini writers of hook 0810 (skel + aegis-gtk-sync).
  - D4 (W16): image://icons gained ?tint=%23RRGGBB — both IconProviders
    (shell + apps hosts) template-recolor the raster (keep alpha, swap
    RGB); three new theme glyphs (aegis-doc-page/-archive/-text, stroke
    style matched to the theme); metaFor maps PDF/archive/text to them
    with a new tintable role; FilesApp grid + list requests carry the
    tint; folder/image/audio/video stay pre-colored (tintable false).
  - D5 (V1): the tray grew a fieldGrowth property — the solver writes
    the largest spring rise over B and the pill padding follows, so the
    end tiles clear the rounded corners while the field is live
    (measured on v0.6.34: rest clearance 4 px, magnified 4 px — the
    padding never grew).
  - D6: 18 px mark in the Control Center header and a mark+wordmark
    brand row atop the Settings sidebar (the v1.3 ruling stands).
  - D7 (W23): FIVE new gate asserts, each offline-validated against the
    v0.6.34 captures BEFORE shipping (every one read RED on the known-
    broken data): config_assert parses ===KWINRC===/===KDEGLOBALS=== and
    fails on decoration/plugin/font drift (the section parser bug — a
    lazy lookahead truncating sections to one line — was caught by the
    same simulation); greeter_assert scans the pre-desktop frames for
    the greeter's clock/progress signature (boot cadence densified to
    2.5 s for frames 12-26); tint_assert gates the PDF glyph at 450 px
    (the tinted label alone is ~250 — measured); monitor_card_assert
    gates the exact-accent fill pixels at 25 (loose window matched the
    wallpaper at 420 — measured); magnify_clearance_assert requires the
    magnified end-tile clearance to beat rest by 8 px. MonitorBackend
    additionally warns "failed to read /proc/meminfo|/proc/stat" per
    dead source so the probe verdicts arbitrate partial failures.
  - D8 (W20): the aegis-windowwatch KWin script (windowAdded/Removed/
    Activated -> recount -> org.aegis.Shell.windowListChanged(count,
    anyFull, idsJoined)) — the ids travel as ONE STRING because callDBus
    marshals JS arrays as DBus "av" which will not demarshal into a
    QStringList slot. Util grew workspaceWindows/anyWindowFull +
    windowListChanged; isRunning answers from the launch records AND
    the window ids (the QML contract unchanged; the dock dots now work
    for foreign-launched apps); apps-main pins the Wayland app_id to
    aegis-<which> so resourceClass matches the dock cmds. Island: the
    idle capsule dissolves (scale 1->0, center origin, 200 ms InCubic +
    fade) while Util.workspaceWindows > 0 and grows back with the
    OutBack spring; non-idle states always win.
  - D9 (W21): the aegis-dockzoom scripted effect — modeled line-by-line
    on the stock scale effect (KWin 6.6 ships scale AS A JS EFFECT —
    the authoritative API reference). Open: scale 0.3->1 + opacity +
    Position from the tile center (280 ms OutCubic); close reverse
    (200 ms InCubic). KWin anchors Scale at edges/corners only, so the
    tile anchoring is the Position pair. JS effects have NO callDBus in
    6.6 (window scripts do) — the tile map travels through kwinrc
    [Effect-aegis-dockzoom] TileMap written by Util.publishDockTileMap
    from Dock.qml's resting layout. The stock scale effect is disabled
    (same exclusive category). DOCUMENTED DELTA: minimize/restore has
    no scripted hook in 6.6 (EffectsHandler exposes only windowAdded/
    Closed/Activated/Deleted to JS) — open/close ship, minimize/
    restore waits for a C++ effect.
  - D10 (W22): strictly opt-in web shortcuts — right-click on the tray
    glass opens the Add pill (paste a link, Enter adds, Esc cancels;
    the dock surface's keyboard is OnDemand); Util.addWebShortcut
    fetches the page (title, apple-touch-icon -> favicon -> letter
    tile in the theme color), stores
    ~/.local/share/aegis/webicons/<id>.png +
    ~/.local/share/applications/aegis-web-<id>.desktop
    (Exec=xdg-open, StartupWMClass=aegis-web-<id>); dockApps appends
    the user entries before Trash (a network failure still lands the
    shortcut with the letter tile); right-click on a web tile offers
    Remove. The resolvers dedupe by Exec basename AND StartupWMClass
    (the browser deb ships two identical entries); the providers
    accept absolute icon paths; dockApps grew NOTIFY (was CONSTANT —
    the dock could never refresh).
- D11 — release: IN FLIGHT. v0.6.35 tagged at fda5ace (Release run
  43163420575 GREEN, ISO published; Shell CI compiled the full C++
  batch). First Boot Test (run 43166164076, FAILED) — the PRODUCT IS
  GREEN (11 tiles + browser, header PASS, ALL SIX probes CLEAN with
  the monitor's own PV-n, monitor assert 599 accent px = the W17 fix
  proven in-guest, config asserts clean, W16/W20/W21 shipped), the
  two reds were HARNESS CALIBRATION:
  1. greeter assert: the live ISO NEVER SHOWS the greeter — SDDM
     autologins straight into the session (serial: sddm-helper --start
     dbus-run-session --autologin, no sddm-greeter process), and
     boot-14/15/16 are the pure-black SDDM-to-session handoff gap the
     reviewer saw in v0.6.34. The mark+clock+progress pixel check
     applies to the INSTALLED path only; the boot gate now asserts the
     theme FILES ship instead (===SDDM-THEME===: Main.qml, mark.png,
     metadata.desktop — a sync-includes slip still goes red) and
     greeter_assert stays in the file UNWIRED for that future gate.
     TELL THE REVIEWER: their W23.2 premise does not hold on the live
     path; the theme-presence gate is the honest equivalent.
  2. tint gate 450 was miscalibrated: the MEASURED red decomposition is
     broken=237 (the pre-colored music glyph's edge AA 223 + a 14 px
     sidebar artifact) vs fixed=395 (same 237 + ~158 for the red
     doc-page outline stroke at 44 px — an outline glyph, not a fill).
     The fix is VISUALLY confirmed (artifact crop: red doc-page glyph
     on the pdf card, amber archive box, blue text page). Gate moved
     to 300, dead center between the two measured states.
  3. magnify assert was unmeasurable because the FIX WORKED: the pill
     grew leftward past the W/5 scan start (edge 271 -> 246, clearance
     4 -> 29 px). Scan now starts at W/10; expected rest 4 / mag 29.
  Harness recalibrated (94b0ec7) and re-dispatched on the SAME
  v0.6.35 ISO — the harness runs from main, no re-release needed.
- D11 run 2 (43169048444, SUCCESS — captures committed + zip attached):
  every calibrated assert green (tint 395, monitor 719, magnify
  rest 4 / mag 29, config clean, six probes CLEAN). BUT the captures
  exposed a SILENT W20 break the gate could not see: the island stayed
  visible with windows open. ROOT CAUSE: the windowwatch script called
  DBus path "/" while Util registers "/org/aegis/Shell" (the same path
  the busctl ladder uses) — every push failed silently, the count
  stayed 0. THE T11-D5 CLASS (interface/path contract mismatch) on the
  path this time. Fix: the script now calls /org/aegis/Shell; TWO new
  gate pieces close the blind spot: (1) ===KWIN-SCRIPTS=== diag +
  config_assert requires isScriptLoaded(aegis-windowwatch)=true;
  (2) island_autohide_assert — the idle island must be VISIBLE on
  01-home (mark ~27 px) and HIDDEN in 02-files (a window is open;
  <= 8 px) — the chain proven end to end, the shipped-green class
  killed. Re-dispatched again on the same ISO.
- D11 run 3 (FAILED — and the new asserts did EXACTLY their job):
  isScriptLoaded said "b false" — the script NEVER loaded. Root cause:
  the kwinrc key shape. KWin keys plugins by the VERBATIM id + Enabled
  (kwin4_effect_shapecornersEnabled for id kwin4_effect_shapecorners,
  scaleEnabled for id scale) — my camelCase aegisWindowwatchEnabled /
  aegisDockzoomEnabled matched nothing, so neither the windowwatch
  script nor the dockzoom effect ever loaded. Fix: kwinrc now carries
  aegis-windowwatchEnabled=true and aegis-dockzoomEnabled=true; the
  config needles updated to the verbatim-id keys; a ===KWIN-EFFECTS===
  diag (org.kde.KWin.loadedEffects) added and asserted for
  aegis-dockzoom. NOTE: kwinrc ships INSIDE the ISO, so this fix needs
  a new release — v0.6.36 (the v0.6.35 ISO cannot load the script no
  matter what main carries). v0.6.35 remains product-valid for
  everything else; v0.6.36 supersedes it with W20/W21 actually live.
- D11 runs 4-5 (v0.6.36, FAILED then diagnostic FAILED): the verbatim-id
  keys worked (isScriptLoaded said "b true") and the new asserts
  immediately exposed the NEXT layer: the island went INVISIBLE
  EVERYWHERE — 0 px on the idle home (the marker pill gone from the
  first desktop frame; run-2's captures show it rendered at the same
  frame). Cross-run discriminator: v0.6.35 (plugins inert) = island
  visible at boot-21 + home; v0.6.36 (plugins live) = absent from the
  first desktop frame. ROOT CAUSE: KWin 6.6 layer-shell surfaces PASS
  w.normalWindow in the scripting API — the windowwatch script counted
  the shell's own four surfaces (desktop/panel/island/dock) from the
  moment they mapped, so workspaceWindows >= 4 forever and the idle
  island dissolved and never returned. THE RULING ANTICIPATED IT
  ("never layer-shell shell surfaces") — the fix is the resourceClass
  guard: both the windowwatch script and the dockzoom effect now skip
  resourceClass "aegis-shell" outright. Also fixed this round: the
  window-state dump reads the DBus address from the aegis-session
  environ (the shell lives on the dbus-run-session bus, NOT the systemd
  user bus the serial console resolves — "The name org.aegis.Shell was
  not provided"); the isEffectLoaded busctl call has a signature
  mismatch on 6.6 ("Too few parameters") so the effect's load proof is
  now a journal MARKER: both plugins print "aegis-<name>: loaded" at
  startup and config_assert requires both markers in ===KWIN-LOADS===.
  v0.6.37 = resourceClass filters + markers (ISO change, new tag).
- D11 run 6 (v0.6.37, FAILED — and each assert is now pulling its
  weight): the resourceClass filter WORKED (island back at the idle
  home, 27 px — the shell surfaces are no longer counted), isScriptLoaded
  true — but files still showed the island (27 px) and the two journal
  marker asserts fired (KWin script print() does NOT reach journald on
  this stack — marker gate removed, the island assert is the end-to-end
  proof). ROOT CAUSE of the never-hiding island found IN THE KWIN
  SOURCE: Script::callDBus does dbusArguments << jsArgument.toVariant()
  — a JS number becomes QVariant(double), DBus 'd' — and the Util slot
  was (int, bool, QString) = (i,b,s). NO SLOT EVER MATCHED. Every push
  since W20 landed failed silently: run 2 wrong keys, run 4 wrong path +
  wrong keys, run 5 shell surfaces counted, run 6 the 'd' vs 'i' type.
  FIX: the contract is now ONE JSON STRING argument — windowListChanged
  (QString json) parses {"count", "anyFull", "ids"}; the script sends
  JSON.stringify({count, anyFull, ids}). No type roulette possible.
  v0.6.38 = the JSON contract (ISO change, new tag).
- D6 — v0.6.39 run 8 (FAILED, and the batch-1 instrumentation paid for
  itself immediately):
  1. W20 IS ALIVE END TO END: the window-state dump (fixed address from
     the aegis-shell environ) read windowListRaw =
     {"count":0,"anyFull":false,"ids":[]} — the script pushes arrive in
     Util. BUT the count never moved off 0 when Files opened. ROOT
     CAUSE: workspace.activeDesktop is not usable in the 6.6 scripting
     API (undefined) — onDesktop() failed EVERY window that sits on a
     specific desktop (indexOf(undefined) = -1) and only windows on all
     desktops would count. FIX: deskOk guard — when the active desktop
     is unknowable, count ALL trackable windows (the honest
     approximation of the ruling's predicate).
  2. W24 launch logs: the diag found no files at
     ~/.local/state/aegis/launch/ because Qt's StateLocation APPENDS
     the app name — the shell's logs live at
     ~/.local/state/aegis-shell/aegis/launch/. Diag glob fixed to
     /home/aegis/.local/state/*/aegis/launch/*.log.
  3. The Properties.Get of workspaceWindows failed on this object
     ("Interface org.aegis.Shell was not found") while the windowListRaw
     invokable worked — the dump now reads ONLY windowListRaw (it
     carries count/anyFull/ids anyway).
  4. THE TIER B DEBS DID NOT OPEN (browser/os/corex diff 0.0-3.5, the
     gate went red on all three — the honest W24 red the review asked
     for). The dock-click attempt (resolver + wrapper) also failed, so
     the electron apps do not start even guarded, OR the wrapper never
     engaged. The launch logs (with the fixed path) name it on the next
     run. NOT yet fixed — the diagnosis continues in v0.6.40.
  v0.6.40 = the activeDesktop guard + the diag fixes; the Tier B
  launch diagnosis rides the same run.
- D7 — v0.6.40 run 9: TWO DECISIVE RESULTS.
  1. **W20 ISLAND CHAIN GREEN**: "island assert: home 27 px (visible),
     files 0 px (should be hidden)" — the KWin script -> DBus -> Util ->
     QML dissolve chain is proven END TO END on the runner. Seven
     shipped-green-class breaks were found and killed on the way (key
     shape, path, layer-surface counting, double-vs-int marshalling,
     activeDesktop, plus the two harness blind spots). The dock running
     dots now track real windows for foreign-launched apps too.
  2. The launch logs delivered the W25 diagnosis EXACTLY as designed:
     aegis-browser-stable.log carries
     "FATAL:sandbox/linux/services/credentials.cc:131 Check failed:
     Permission denied (13)" + Trace/breakpoint trap — the Chromium
     SUID helper fails EVEN after the 4755 chmod (the guest root is
     mounted nosuid; user namespaces unavailable). The review's
     "--no-sandbox only if the SUID check fails" cannot detect a nosuid
     mount, so aegis-electron-launch now passes --disable-gpu
     --no-sandbox unconditionally in VM mode (the wrapper only engages
     in a VM — the metal path keeps the real sandbox). Also visible:
     the launch-log FILE NAMES pick up serial-console escape junk for
     harness-typed launches (the known ANSI artifact — the dock's own
     launches name them cleanly); cosmetic, documented.
  v0.6.41 = the wrapper fix (ISO change, new tag). Batch 2 (W30-W37)
  queued after the Tier B gate goes green.
- D8 — v0.6.42-44 runs: THE WRAPPER NEVER ENGAGED, THREE LAYERS DEEP:
  1. v0.6.42: the browser log still showed the RAW Exec — the dock's
     chrome-sandbox detection checked next to the /usr/bin WRAPPER
     SCRIPT (the sandbox lives in the /opt app dir) so no launch ever
     got wrapped. FIX: ALL Tier B resolved Execs ride
     aegis-electron-launch (a transparent exec outside VM mode).
  2. v0.6.43: "/bin/sh: 1: aegis-electron-launch: Permission denied" —
     the wrapper shipped mode 100644 (git does not preserve the +x
     from the filesystem; the D5d hook-bit class). FIX: git
     update-index --chmod=+x.
  3. v0.6.44: the wrapper RAN (its log exists) but the flags did not
     reach the app — os-private-chat still FATAL'd at credentials.cc.
     ROOT CAUSE: the VM detection grepped only product_name, and the
     QEMU guest's product_name is "Standard PC (Q35 + ICH9, 2009)" —
     QEMU identifies via sys_vendor. FIX: grep both files.
  ALSO SHIPPED: the Store capture (04k-store, diff 15.9 — the store
  opens with the catalog rendered), the Trash-slot capture with the
  aegis-files --path launch logged, the island chain green on every
  run since v0.6.40.
  v0.6.45 = the sys_vendor fix (ISO change, new tag). If the Tier B
  gate stays red after this, the next lever is AEGIS_VM_MODE=1 on the
  runner's kernel command line (a build-iso/boot-test pairing) — the
  detection is then guaranteed, no DMI dependency.
- D9 — v0.6.45 run: **THE SYS_VENDOR FIX WORKED FOR TWO OF THREE**:
  browser diff 59.7 (window rendered, was 3.2), os-private-chat diff
  32.5 (the app RUNS — its log's only complaint is
  ERR_INTERNET_DISCONNECTED for its remote page, honest in the offline
  runner VM). The island chain green again, all probes CLEAN, the
  Store capture green. ONE HOLDOUT: corex diff 3.8 — its launch log
  tail was cut by the diag's tail -5 (the wrapped launches all land in
  aegis-electron-launch.log; corex's entry is beyond the 40-line cap).
  NEXT SESSION: raise the LAUNCH-LOGS diag cap (head -40 -> head -80 or
  tail the corex launches only), read corex's own error, fix — likely
  a missing dependency (CoreX Terminal may not be chromium-family: the
  --no-sandbox/--disable-gpu flags are ignored by a non-chromium binary
  and its real failure is something else entirely — check
  dpkg -L corex-terminal for the real binary shape first).
  CURRENT GATE: 10 of 11 apps open; corex is the last red.
- D10 — v0.6.46: LOCAL FORENSICS KILLED THE D9 SPECULATION, THE HARNESS
  DIAG CHANNEL IS THE FIRST FIX. Downloaded both debs in the sandbox
  (app-deb-urls.txt URLs) and inspected them directly:
  1. CoreX IS chromium-family — Electron 45.2.3 / Chrome 156.0.8078.80
     (OS messenger is Electron 45.2.2, same Chrome). The binary RUNS in
     this sandbox with exactly the VM wrapper flags
     (--no-sandbox --disable-gpu): no credentials.cc FATAL, ldd clean,
     app.asar loads. The "non-chromium binary" theory is dead.
  2. THE v0.6.45 RUN'S EXEC RESOLUTION WAS GARBAGE: the CI log printed
     `resolved Exec from the desktop entry: ]3008;end=...;exit=success`
     — Serial.run's splitlines()[-1] picked the serial console's
     shell-integration OSC markers, not the Exec line. So EVERY Tier B
     attempt-0 dbus launch sent an OSC-contaminated string to
     Util.launch (proof: a launch log named with embedded escape bytes
     and prompt fragments exists in the LAUNCH-LOGS dump). The small
     diffs (3.3/3.4) were the dock running-dot for garbage commands.
     Browser/os never opened on attempt 0 either — only attempt 1 (the
     dock click) ever launched a real process on any run.
  3. Desktop-file diff, OS (works) vs CoreX (fails):
     OS Exec=/opt/OSPrivateChat/os-private-chat (plain, no quotes);
     CoreX Exec="/opt/CoreX Terminal/corex-terminal" %U (quoted + field
     code). Both valid desktop files; sh handles both. CoreX also ships
     an AppArmor profile (unconfined, userns) — not the blocker (the
     userns path is unused with --no-sandbox; a failed profile load
     leaves the binary unconfined). CoreX's postinst installs
     /usr/bin/corex-terminal via update-alternatives — the bare head IS
     on PATH for all three debs (browser and os too).
  FIX PACKAGE (v0.6.46):
  a. Harness: Serial.run ANSI/OSC-sanitizes its decoded output; the
     Exec resolution is marker-bounded (EXEC-RES-START/END, first
     non-empty line, refuse anything still containing escapes);
     attempt 0 launches aegis-electron-launch + the resolved line (the
     dock's actual launch line — honest end-to-end); after each failed
     attempt a pgrep liveness line separates crash vs slow-paint vs
     never-launched; the LAUNCH-LOGS diag walks the glob with a
     per-file header instead of tail|head caps; corex wait 30 -> 45 s.
  b. findInstalledEntry (util.cpp): when QStandardPaths finds the bare
     head on PATH, launch THAT (clean, quote-free, matches the tile
     tracking head); the entry Exec stays the fallback when nothing is
     on PATH (W24 honesty preserved).
- D11 — BATCH 2 OPENED (v0.6.47): W30.2 (Sound honest empty states —
  SoundBackend.state is now "nowpctl" / "nodevice" / "pipewire" and the
  pane says WHICH one) + W30.3/W32.2 (Network pane wired section —
  NetworkBackend.wired [{iface, plugged, active}] from DeviceType 1 +
  Carrier + State, green/accent/dot and Connected / Cable connected /
  Cable unplugged; NetworkBackend.hasWifi so a radio-less VM reads
  "No Wi-Fi device" instead of "scanning...") + W31 (the §6 sidebar
  glyphs — panes carry glyph keys, paintPaneGlyph paints outline glyphs
  in the tint circles: mountain · palette · sparkles · chip · monitor ·
  speaker · wifi · person, the CC stroke family, arcTo-based rrect
  because Context2D has no roundRect). REMAINING batch 2: W30.1
  (kscreen package + per-output rows), W32.1/32.3 (WPA join sheet +
  bluetooth), W33 (drivers pane), W34 (Aegis ID errors + profile),
  W35 (XKB), W36 (desktop context menu), W37 (dead-control sweep).
- D13 — W34.1 DONE (v0.6.47): the Aegis ID form now says WHY it failed
  and whether the backend is even connected. AegisId.classifyError:
  status 0 (DNS/no-route/timeout/TLS) = "Can't reach the Aegis sync
  service — check the network, then retry" (on the VM round this read
  as "Account not found" — the user's exact complaint); 401/403 =
  "Wrong email or password"; 5xx = "Service error... try again later";
  else the server's message or the caller fallback. New backendState
  ("reachable"/"unreachable"/"unknown") + lastAttempt (HH:mm) update on
  EVERY reply and render as the state line under the form. Wired into
  kdf-params, register and login/refresh error paths.
- D14 — W30.1 package half + W33.2 package + W36.1 DONE (v0.6.47):
  kscreen added to aegis-desktop.list.chroot (the Displays pane no
  longer degrades to not-available on a fresh ISO); cups-pdf (the
  review's Print-to-PDF ask); the desktop right-click menu in
  Desktop.qml — New Folder in ~/Desktop (numbered fallback),
  Change Wallpaper -> aegis-settings 0, Display Settings ->
  aegis-settings 4, Open Terminal; Clean Up waits for M2 desktop icons.
  All of D11-D14 are LOCAL commits while Boot Test 43275799810 flies —
  push only after it lands.
- D15 — v0.6.46 BOOT RUN + ARTIFACT FORENSICS = **COREX ROOT CAUSE,
  NINE RUNS AFTER W24 OPENED**. The D10 diagnostics paid for themselves:
  1. The resolved Execs are clean now (`/opt/OSPrivateChat/
     os-private-chat`, `"/opt/CoreX Terminal/corex-terminal" %U`) and
     the liveness probes answer the crash-vs-slow question: corex is
     DEAD on both launch paths within the window.
  2. The artifact's serial-diag.txt carried the FULL per-file launch
     dump (the typed-channel drain still cut the CI log at the first
     file — the artifact is the reliable channel now). corex-terminal.log:
     the dock click launched the BARE head and FATALed at
     credentials.cc:131 — the electron wrapper NEVER ENGAGED for corex.
  3. WHY: CoreX's desktop Exec is quoted — Exec="/opt/CoreX Terminal/
     corex-terminal" %U. findInstalledEntry's basename match takes
     section(' ',0,0) of the raw Exec = `"/opt/CoreX`, basename `"CoreX`
     != corex-terminal — THE ENTRY NEVER MATCHED. The tile survived the
     W8 PATH fallback (update-alternatives symlink) but lost the W24
     launch field, so Dock launched tile.cmd = the bare head. Every run
     since v0.6.39. The PATH-first change in v0.6.46 sat INSIDE the
     match branch it could never reach.
  FIX (v0.6.47): findInstalledEntry strips the quoting from the first
  Exec token (quoted form "..."; backslash escapes) before the basename
  match. CoreX now matches (and gets the entry's real icon/name), the
  PATH-first exec applies, dockApps wraps, the VM flags reach electron —
  the os-private-chat path that already works end to end. Harness side:
  the Exec resolution walks ALL /usr/share/applications entries the way
  the W8 entryhit rule does (the browser's entry is aegis-browser.desktop
  / org.aegisbrowser.Aegis, not aegis-browser-stable.desktop — its
  attempt-0 fallback launched the bare head and FATALed identically,
  proving the mechanism from a second angle). ALSO NOTED (cosmetic):
  konsole.log shows kwinrc line 8 "Invalid escape sequence «\"»" twice
  at session start — the W21 TileMap JSON quotes are written unescaped;
  harmless, queued for a later hygiene pass.
- D16 — v0.6.47 release run RED: the ISO build died on
  "E: Package 'cups-pdf' has no installation candidate" — the W33.2
  package ask churned out of the resolute archive (rolling release;
  kscreen stayed in). cups-pdf reverted on main, recorded here as the
  review's honest answer (the Print-to-PDF ask waits for an archive
  reintroduction or a locally built deb). v0.6.48 = the same tree with
  the line gone; the D15 corex fix and D11-D14 ride it.
- D17 — v0.6.48 BOOT RUN RED, A NEW CLASS: THE SESSION NEVER CAME UP.
  sddm-helper exited 134 (SIGABRT) right after "aegis-session start ...
  vt=2", sddm retried on vt3, wait_desktop timed out, the harness went
  to the serial-recovery path. ROOT CAUSE: MY OWN D11-D14 — Desktop.qml
  (a SHELL QML file) now imports Aegis.Files for the New Folder action,
  but the shell's engine registers ONLY Util/Activity/Governor
  (Aegis.Files is an apps-main registration); the import failed, the
  Desktop component died, the session aborted. The audit says Desktop.qml
  is the ONLY shell-loaded file using an app-only module. FIX: register
  Aegis.Files in main.cpp (static FileManager files) and add
  apps/filemanager.h to the aegis-shell CMake target. The boot gate did
  exactly its job — a shipped-green-class regression went red on the
  runner instead of on the reviewer's VM. v0.6.49 = the fix + everything
  from D15 (the corex quoted-Exec fix is STILL UNVERIFIED — both the
  v0.6.47 ISO build red and the v0.6.48 session abort blocked it).
- D18 — v0.6.49 BOOT RUN: THE D17 FIX WORKED (session up, the whole
  choreography ran, browser opened on ATTEMPT 0 with the wrapped
  resolved Exec — the walk found /usr/bin/aegis-browser-stable %U), os
  opens, everything else green. COREX STILL RED, and the artifact nails
  it: corex-terminal.log shows TWO bare-head FATALs,
  aegis-electron-launch.log has NO corex entry — the D15 strip was
  ITSELF broken. section(' ',0,0) splits INSIDE the quoted path (the
  first token is `"/opt/CoreX`), the closing quote lies beyond the
  token, the basename read `"CoreX`, the entry stayed unmatched, and
  the dock launched the bare head twice more. THE SAME BUG lived in the
  harness: both the entryhit prelude and the resolution walk used awk
  $1 after tr -d quote — the walk never matched corex either (the tile
  map only ever matched via command -v on the update-alternatives
  symlink). FIX (v0.6.50): the quoted parse runs on the FULL Exec value
  — from the opening quote to the closing quote, spaces inside included
  — in findInstalledEntry; the harness gets a quote-aware execbase()
  helper (leading-quote then cut -d quote -f1, else awk $1) shared by
  entryhit and the walk. BOTH verified locally against the actual
  desktop files: entryhit hits all four heads, the walk resolves the
  full quoted Exec, the DBus launch line becomes aegis-electron-launch
  "/opt/CoreX Terminal/corex-terminal" %U.

---

## T11 — v0.6.28-v0.6.34: M3 apps on the dock + in the boot captures (SHIPPED)

Opened 2026-11-12. User report on the shipped v0.6.27: "the boot [captures]
do not contain the screenshots of new apps like music calculator etc and
they are also not in the dock". Root cause is bookkeeping, not code: the
four M3 apps ship as .desktop entries (the Launcher lists them through
Util.allApps) but the dock config never received Tier A slots and
boot-capture.py never learned their choreography — so no dock tile, no
capture, no proof the apps open on the runner.

### Subtasks (work in this order)

- D1 — dock slots: add four Tier A slots (Music, Calculator, Editor,
  Monitor — icons aegis-music/aegis-calculator/aegis-editor/aegis-monitor,
  cmds aegis-music/aegis-calculator/aegis-editor/aegis-monitor) to
  shell/packaging/config.json between the separator and Settings; mirror
  the same list in shell/src/util.cpp defaultConfig() (the packaged file
  wins at runtime, the C++ default is the offline mirror). Everything
  downstream is config-driven and auto-updates: expected_tiles() counts 11,
  dock_geometry()/find_tiles() lay the click map out arithmetically. New
  geometric order: Files 0, Terminal 1, Browser 2, OS 3, CoreX 4, Music 5,
  Calculator 6, Editor 7, Monitor 8, Settings 9, Trash 10. Tray width
  11x58 + 10x2 + 2x6 = 670 px on the 1280 canvas — fits.
- D2 — boot captures: in scripts/boot-capture.py, change the Settings
  click_idx 5 -> 9 (comment updated too), and after the 04b-aegis-id pane
  shot add open_app for the four apps: 04c-music (aegis-music, click_idx
  5), 04d-calculator (aegis-calculator, 6), 04e-editor (aegis-editor, 7),
  04f-monitor (aegis-monitor, 8), alt+F4 between each. The diff-vs-home
  check inside open_app is the per-app assert; record the four in the
  opens dict and extend the release gate loop
  ("files", "terminal", "settings") with them.
- D3 — QML probes: app_diag grows four foreground probes in the same
  split-token pattern (aegis-apps music/calculator/editor/monitor with
  timeout -k 2 6, verdict tokens PROBE-M/C/E/N-DIRTY/CLEAN). The music
  probe additionally excludes audio-subsystem noise from the DIRTY
  verdict (pipewire/pulse/gstreamer/alsa lines) — MusicApp constructs
  MediaPlayer at startup and a headless VM may emit benign audio chatter,
  while a real QML load failure still says error/Cannot and stays DIRTY.
  The probe verdicts join the release gate automatically through the
  probes dict loop.
- D5 — boot-test failure investigation (v0.6.28 Boot Test run 43064774243,
  FAILED after 13 min) and fix batch. The dock itself SHIPPED CORRECT: the
  home capture shows all four M3 squircles. Four independent defects made
  the choreography red:
  1. AEGIS Browser deb 404 (the pinned r31 release asset was removed
     upstream; r45 is current) — the ISO staged only OS + CoreX, the dock
     dropped the Browser slot per W8 and showed 10 tiles while the
     geometric click map assumed the config's 11 — every click after the
     separator landed half a pitch off (usually dead centre of the 2 px
     gap between tiles). The tooltips in the four app captures prove the
     pointer sat one tile right of the intent (Calculator/Editor/Monitor/
     Settings). Fix: app-deb-urls.txt r31 -> r45 AND the harness now asks
     the guest for its REAL tile list (resolved_tile_cmds: Tier A always
     present, Tier B iff command -v finds the binary — the W8 rule) and
     rebuilds the click map from that answer (open_app picks the click
     index from tile_index; hardcoded indices are only the fallback).
  2. EVERY busctl call in the run failed with "No such interface
     'org.aegis.Shell'" — a REAL product bug: Util never declared
     Q_CLASSINFO("D-Bus Interface", "org.aegis.Shell"), so Qt exported
     the invokables under the generated local.aegis.Util interface. The
     DBus launch path never worked since v0.6.19; the click fallback
     silently did the work (the old config count matched the dock, so
     nothing bit until the four M3 clicks). Fix: Q_CLASSINFO added to
     Util (util.h). forwardToShell was never affected (it passes an
     empty interface, which DBus resolves against any export). The
     launch ladder is now busctl -> nohup (the proven 04b mechanism,
     independent of bus and geometry) -> geometric click.
  3. Two probe verdicts (music, monitor) were lost to serial-buffer
     desync ("VERDICT MISSING" = harness failure). Fix: probes now write
     their verdict to /tmp/pv-<s|f|m|c|e|n> guest-side and ONE short
     read command returns all six; parsing is regex on that reply.
     Honest failure preserved: a missing verdict file still fails.
  4. The four M3 wrappers were never guest-verified. The diag now dumps
     ls -la of all six /usr/bin/aegis-* wrappers (===WRAPPERS===).
  Simulated the guest-side parsing offline (10-tile, 11-tile, garbled,
  verdict regex — all pass). Files: shell/src/util.h,
  debian-live/app-deb-urls.txt, scripts/boot-capture.py.
- D5b — v0.6.29 Boot Test (run 43074736973, FAILED) postmortem. HUGE
  progress first: NO "window never opened" failures — the launch ladder
  (busctl via the Q_CLASSINFO fix) worked and the four M3 app captures
  04c..04f show Music/Calculator/Editor/Monitor fully rendered (Music
  with the seeded fixture track, Calculator with tape header). The dock
  shipped correct. The run went red on harness losses only:
  1. _drain reset its deadline to now+0.5 s on EVERY received chunk, so
     a command whose output trails (the QML probes run a silent ~8 s
     timeout chain) drained ~0.6 s in and the runner typed the next
     commands while the guest's foreground was still busy — the queued
     lines were never echoed or executed. v0.6.29 lost VERDICTS,
     WRAPPERS and the five JRN/KWINRC diagnostics between the monitor
     probe and KWIN-PLUGINS (the buffer jumps straight from ===QPN=== to
     ===KWIN-PLUGINS===); all six probes then read VERDICT MISSING and
     the honest gate correctly failed the release. Fix: the settle is a
     HARD MINIMUM — the drain never shortens below the requested wait.
  2. resolved_tile_cmds used command -v as the Tier B presence check —
     NOT the W8 rule. The Aegis Browser deb ships a desktop entry whose
     Exec points into /opt (no PATH binary), so the v0.6.29 harness read
     10 tiles while the dock showed 11. Fix: the harness now runs the
     faithful W8 probe guest-side (entryhit(): /usr/share/applications
     *.desktop, Exec basename with quotes stripped or TryExec matches,
     command -v as the fallback) — verified offline against all three
     real entry shapes. The r45 Browser deb itself staged fine (115.9 MB
     in the v0.6.29 ISO build log).
- D5c — v0.6.30 Boot Test (FAILED) postmortem: the harness losses are gone
  (VERDICTS read works, settings/files/calculator/editor CLEAN, the
  WRAPPERS dump proves all six /usr/bin/aegis-* wrappers are -rwxr-xr-x).
  Three remaining defects, two of them REAL product bugs:
  1. MonitorApp.qml threw "ReferenceError: Monitor is not defined" at load
     (lines 65/148-150/157 — the MonitorBackend singleton is registered as
     Aegis.Monitor/Monitor in apps-main.cpp but the QML never imported it).
     Fix: import Aegis.Monitor added. EditorApp.qml had the same latent
     defect with TextFile (Aegis.TextFile/TextFile; masked at startup by
     the empty-doc ternary that never calls TextFile.prettyPath, but load/
     save would throw). Fix: import Aegis.TextFile added.
  2. Music probe DIRTY on a BENIGN line: "qt.multimedia.ffmpeg: Using Qt
     multimedia with FFmpeg version 8.0.1-3ubuntu2..." — the audio-chatter
     filter missed it. Fix: the filter grew qt.multimedia and ffmpeg (both
     in the guest verdict chain and the DIRTY fetch).
  3. The AegisBrowser r45 deb staged into config/packages.chroot (115.9 MB
     in the build log) but live-build NEVER unpacked it — the log has
     Preparing-to-unpack lines for aegis-shell (0245-), corex (0494-),
     os-private-chat (1106-) and NOTHING for the browser; the local apt
     repo (file:/root/packages) additionally logged "Permission denied" on
     its Packages index in five passes. The guest (entryhit + command -v
     both negative) confirms the browser is not installed, so the dock
     dropped the slot correctly. Fix: hook 0900-app-debs-fallback.hook
     .chroot — after the chroot package pass, any of OUR debs apt missed
     (aegis-shell/aegis-browser-stable/corex-terminal/os-private-chat/
     kwin4-effect-shapecorners) is dpkg -i'd from /root/packages (and
     /root/packages.chroot), followed by apt-get -f; already-installed
     packages are untouched so a re-run is a no-op. The browser entry
     itself is healthy: Exec=/usr/bin/aegis-browser-stable (verified by
     extracting the r45 deb) — once installed, entryhit and command -v
     both match and the dock keeps the slot.
- D5d — v0.6.31 Boot Test: SUCCESS. All six probes CLEAN (the Monitor/
  Editor import fixes and the multimedia filter landed), the four M3 app
  captures carry healthy diff-vs-home deltas (music 15.6, calculator 6.7,
  editor 15.2, monitor 14.1), header geometry PASS, capture complete with
  zero assert failures. ONE residual: the guest still reports 10 dock
  tiles (no Aegis Browser) — the 0900 fallback hook shipped with mode
  100644 (all other hooks are 100755) and live-build skips non-executable
  hooks silently; also the numbered unpack lines (0245-shell, 0494-corex,
  0902-shapecorners, 1106-os) prove live-build's local repo again skipped
  the browser deb itself. Fix: git update-index --chmod=+x on the hook.
- D5e — v0.6.32 Boot Test: SUCCESS again (all six probes CLEAN, the four
  app captures green, header assert PASS) but the browser is STILL absent
  (10 tiles) and the 0900 hook printed nothing even with the executable
  bit fixed. Build-log archaeology found the real mechanism: live-build
  rescans its local apt repo's Packages index between passes — the index
  grows 2868 B (4 debs) -> 5782 B (5 debs) and the INSTALL pass always
  ran against the 4-deb index (the browser's entry is ~2 KB of Depends),
  so the browser NEVER unpacked in v0.6.29-v0.6.32; the numbered unpack
  lines (0245-shell, 0494-corex, 0902-shapecorners, 1106-os) repeat
  without the browser every time. Fix: bypass the local repo for the app
  debs entirely — build-iso.sh now copies every staged deb into
  config/includes.chroot/opt/aegis-debs (lands in the chroot), the
  rewritten 0900 hook dpkg -i's any of OUR five packages apt missed from
  there (/opt/aegis-debs, /root/packages, /root/packages.chroot —
  idempotent, already-installed skipped), runs apt-get -f for deps, and
  rm -rf's /opt/aegis-debs so the squashfs carries no payload (zero ISO
  bloat). The includes dir is build-time only and gitignored. Release as
  v0.6.33.
- D6 — v0.6.33 Boot Test (run 43134801060, FAILED) postmortem: the D5e
  deb path WORKS — the click map was rebuilt from the guest with 11
  tiles and aegis-browser-stable restored in slot 2, header assert PASS,
  all seven app opens green, screenshots artifact uploaded. Two defects
  failed the run, both in the tooling:
  1. THE MONITOR PROBE VERDICT WAS NEVER READ — harness bug found by
     postmortem, not by the gate: the verdict parse used PV-<name[0]>,
     and music/monitor share the first letter m, so "probe monitor"
     parsed music's PV-m=CLEAN and logged "probe monitor: CLEAN" while
     the guest verdict file said PV-n=DIRTY. The monitor probe has been
     unverified since the file-based verdicts landed (D5) — every
     earlier "all six probes CLEAN" read music twice and monitor never.
     The gate's own probe_failed() never saw the content, so whether
     the monitor stderr is benign or a real load error is UNKNOWN and
     must be settled by the re-run. Fix: explicit name-to-token map
     (settings s / files f / music m / calculator c / editor e /
     monitor n) in boot-capture.py. On the re-run a DIRTY monitor is
     fetched and logged verbatim, and probe_failed() arbitrates
     honestly: benign chatter passes, a real error/Cannot line fails
     the release and becomes a MonitorApp fix (which would need a new
     ISO + tag v0.6.34).
  2. THE CAPTURE PUSH RACED MY OWN DOCS PUSH — I pushed the TASKS.md
     anchor (b1b5e77) 3 minutes after the runner checked out main at
     b66a018; the runner's screenshot push was rejected "fetch first"
     and the job exited 1 with the captures safe in the artifact.
     Fix: the Commit screenshots step now runs git pull --rebase
     origin main before git push. NEW PITFALL for every session: do
     NOT push anything to main while a boot test is in flight —
     update TASKS.md before dispatching or after the run lands.
  Fix batch (harness only, the ISO is untouched): boot-capture.py
  token map + boot-test.yml pull-rebase. Then re-dispatch Boot Test
  inputs.tag v0.6.33 on the updated main — same v0.6.33 ISO, honest
  probe evaluation, screenshots committed by the runner.
- D6 verdict — re-run 43136845770 (same v0.6.33 ISO, fixed harness):
  the honest gate WORKED. "probe monitor: DIRTY" was read, fetched and
  arbitrated: MonitorApp.qml:150 TypeError "Cannot call method 'toFixed'"
  — a REAL product bug that shipped in the v0.6.31/v0.6.32 ISOs behind
  the parse collision. Root cause: MonitorBackend's QVariantMap
  m_summary starts EMPTY and MonitorApp.qml binds summary.load1.toFixed
  at component creation, before the first /proc walk populates the map
  (first data lands on the 2 s timer) — undefined.toFixed throws.
  Fix: m_summary now carries the full zeroed key set (cpu / memUsedMb /
  memTotalMb / memPercent / uptimeSec / load1 / netUpKbps /
  netDownKbps / processCount) from construction, so every summary
  binding sees a number from the first evaluation. Audit: no unguarded
  numeric calls in Music/Calculator/Editor QML. Same run also proved
  again: 11 tiles browser-restored, header PASS, s/f/m/c/e CLEAN, and
  the push race did not reproduce. NEXT: commit the backend fix, tag
  v0.6.34, Release CI, Boot Test inputs.tag v0.6.34 — on green, v0.6.34
  closes T11 (browser restored + monitor verdict honest + all six
  probes real) and carries the four M3 app captures in
  docs/screenshots/v0.6.34/.
- D4 — release: qml-guard -> commit -> pull --rebase -> push -> tag
  (v0.6.28 burned by D5, v0.6.29 by D5b, v0.6.30 by D5c; re-releases as
  v0.6.31) -> Release CI builds the ISO -> Boot Test (workflow_dispatch,
  inputs.tag v0.6.31) -> verify 04c..04f captures exist and the asserts
  stay green -> mark T11 SHIPPED here with the run numbers.

### Status

- SHIPPED — v0.6.31 (commit 6ca1c85, Boot Test run 43089802794 green):
  the four M3 apps are ON THE DOCK (config slots + util.cpp mirror) and
  IN THE CAPTURES (04c-music / 04d-calculator / 04e-editor / 04f-monitor
  committed to docs/screenshots/v0.6.31/ by the boot test), the release
  gate covers all seven first-party apps, all six QML probes CLEAN.
  Side fixes shipped with it: the org.aegis.Shell DBus interface
  (Q_CLASSINFO), MonitorApp/EditorApp singleton imports, the guest-
  resolved dock click map, hard-minimum serial drain, file-based probe
  verdicts, the Browser deb URL r31 -> r45. v0.6.32 follows with the
  0900 hook executable bit (browser slot regression vs v0.6.27).

- CLOSED — v0.6.34 (commit afb1ad6, Boot Test run 43140958250 GREEN):
  the guest reported PV-n=CLEAN — the monitor's OWN verdict token, read
  by the fixed parser, backed by the zero-initialized summary map; all
  six probes honestly CLEAN, header assert PASS, 11 dock tiles with the
  browser restored in slot 2, and the runner committed 30 captures to
  docs/screenshots/v0.6.34/ — 01-home shows the four M3 squircles on
  the dock between CoreX and Settings, 04c-music / 04d-calculator /
  04e-editor / 04f-monitor show the apps fully rendered — and attached
  AegisOS-v0.6.34-screenshots.zip to the release. v0.6.33 is a BROKEN
  release (monitor TypeError shipped behind the parse collision; ISO
  also fine for everything else but do not distribute) — v0.6.34
  supersedes it.

- v0.6.33 (commit b66a018, D5e): Release CI green (run 43105308237,
  ISO parts published on the release page), Boot Test dispatched
  (run 43134801060, inputs.tag v0.6.33, ref main). Verify on green:
  the guest dock reports 11 tiles (the Aegis Browser slot restored by
  the includes-chroot deb path), 04c..04f captures green, screenshots
  committed to docs/screenshots/v0.6.33/, then T11 closes for good.

- D1-D3 detail: four Tier A slots in config.json +
  the util.cpp mirror; boot-capture.py grew the four open_app captures
  (04c-music / 04d-calculator / 04e-editor / 04f-monitor, click_idx 5-8),
  Settings click_idx moved to 9, the opens release gate covers all seven
  first-party apps, app_diag grew PROBE-M/C/E/N foreground probes (music
  filters pipewire/pulse/gstreamer/alsa chatter out of its DIRTY verdict
  and its fetch). qml-guard PASS (21), py_compile PASS, config parses
  11 tiles. (Tag plan moved through v0.6.28-v0.6.32, see SHIPPED above.)
- D4 — release: DONE for v0.6.31/v0.6.32 (green boot tests); v0.6.33
  release + boot test in flight, see the status entry above.

---

## T10 — v0.6.27: one window anatomy, glass controls, Aegis ID session, M3 Depth (SHIPPED)

Opened 2026-11-11. User reports (with screenshots) plus the milestone plan
from docs/MILESTONES.md.

### DONE (in tree, committed with this file)

- W11 — one window anatomy; "the header is smaller than the body" (fig 1,
  terminal). Root cause found: the Plasma 6.6 aurorae v2 engine CLAMPS the
  theme's Border* to the session border size — BorderSize=Normal clamps
  12 -> 6, so the client sat inside a body-coloured strip 6 px wider than
  the glass band and the band arc floated inset. Fix: kwinrc
  BorderSize=None (borders 0/44/0/0, client flush with the window edge
  below the 44 px band), AegisLightsrc BorderLeft/Right/Bottom = 0, frame
  SVG regenerated with radius-18 top corners matching the ShapeCorners
  effect (Radius=18). ShapeCorners rounds every window, so Corex and
  installed apps get the same curved corners as Settings/Files.
  Files: etc/xdg/kwinrc, AegisLightsrc, decoration.svgz,
  decoration-inactive.svgz, scripts/gen-aurorae-frame.py (PARTW=18).
- W12 — glass switches + wallpaper picker row (fig 2). GlassSwitch
  component (accent track when on, 20 px white knob, OutCubic 160 ms)
  replaces every stock Switch in SettingsApp.qml. The Choose image… tile
  is rebuilt as the same ColumnLayout anatomy as the four wallpaper tiles
  (118 px thumbnail band + Custom + Your pictures rows) so it sits ON the
  thumbnail line; 118 px also keeps five tiles inside the 658 px pane
  (the 132 px row overflowed and clipped at the window edge).
- W13 — panel status icons on one line ("wifi logo not in line"). Wi-Fi
  fan: ink spans [cy - rout, cy] so its ink center is cy - rout/2 =
  cy - 3.85; centering THAT on the glyph midline (canvas y 8) gives
  cy = h/2 + 4 (v0.6.26 shipped h/2 + 2 and still read ~3 px high).
  Battery ink center 8.9 -> translate(0, -0.9) to sit on y 8.
  Files: shell/src/qml/Panel.qml.

### TODO (work in this order)

- W14 — DONE (commit 5f26549): Aegis ID session redesign (fig 3). Hero
  card (mark + pitch), glass form wells via the IdField component with
  accent focus border, 34 px fields, Enter-signs-in, 34 px actions
  (disabled + dimmed while working, error line in danger), three
  what-syncs tiles in the sidebar dot language (Accent #3E8BFF / Wallpaper
  #8B5CF6 / Files #34C77B), zero-knowledge note. Signed-in: account card
  (avatar with initial, live dot, zero-knowledge chip), sync card (Sync
  now / Sign out, encrypted note, sync status), devices card with
  separators, empty state, THIS DEVICE chip, Remove. qml-guard PASS.
- M3 — Depth: DONE in tree (commit after this edit) —
  - [x] workspaces seed: kwinrc [Desktops] Number=4 Rows=1
  - [x] Overview / Mission Control: [Plugins] overviewEnabled=true declared
        in kwinrc (Meta+W); gesture + shortcut dictionary added to
        docs/DESIGN-TOKENS.md as Table 10 (swipes, Meta+Ctrl arrows,
        Meta+T tiling, Calm tile)
  - [x] tiling: stock KWin tiling editor on Meta+T, documented in Table 10
  - [x] four apps on the aegis-apps host: MusicApp.qml (Qt Multimedia over
        PipeWire, FolderListModel library of ~/Music, transport + seek +
        volume + shuffle/repeat), CalculatorApp.qml (tape history, keyboard,
        repeated-equals contract), EditorApp.qml (TextFile backend load/save
        with 4 MB cap, FileDialog open/save, wrap toggle, dirty-dot title,
        Ctrl+N/O/S), MonitorApp.qml (MonitorBackend /proc walk every 2 s:
        cpu %, per-core strip, memory, uptime, net rates, top-40 processes
        with top-style normalization). Backends in
        shell/src/apps/monitorbackend.h (MonitorBackend + TextFileBackend),
        registered as Aegis.Monitor/Monitor + Aegis.TextFile/TextFile.
        Wrappers aegis-music/calculator/editor/monitor installed via
        CMake install(PROGRAMS); desktop entries in
        includes.chroot/usr/share/applications (Launcher picks them up
        through Util.allApps); qmldir-independent QML added to the
        apps-qml resource; qml6-module-qtmultimedia + libqt6multimedia6 +
        gst base/good/pipewire added to aegis-shell.list.chroot; the four
        squircle icons already exist in the Aegis theme. qml-guard PASS
        (guard FILES extended with the four apps).
  - [x] Calm Mode: ActivityService grew Activity.calm (setCalm turns dnd on
        with it); the Control Center tile now drives the full contract —
        Tier C via Governor.setTier, dnd + panel collapse via calm; off
        restores Governor.setAutoMode. Panel.qml collapses its chrome to
        clear glass while calm (180 ms), the exclusive zone stays 28 px, a
        NoButton hover probe peeks the panel back (1.5 s re-collapse).
  - [x] gestures: Table 10 in docs/DESIGN-TOKENS.md (see above)
- M4 — Parity: DONE in tree (commit 02b9ac7) —
  - [x] GTK interop: hook 0810-gtk-interop.hook.chroot installs
        adw-gtk3-theme, seeds /etc/skel gtk-3.0/gtk-4.0 settings.ini
        (dark default, Aegis icons with breeze fallback, Breeze cursor,
        Montserrat), seeds the accent gtk.css for both toolkits, ships
        /usr/bin/aegis-gtk-sync + an autostart entry so the session
        applies prefs.json darkMode + tokens.conf accent on every boot.
        Honest caveat: mid-session accent changes reach shell + Aegis apps
        over DBus immediately, GTK apps on next launch.
  - [x] light theme parity: Util.setDarkMode now also writes
        ~/.config/kdeglobals [General] ColorScheme = AegisDark /
        AegisLight (both schemes ship in /usr/share/color-schemes), so
        Konsole and the installer widgets follow the rung swap; the QML
        glass surfaces already flip through Util.darkMode.
  - [x] i18n groundwork: scripts/gen-shell-i18n.py inventories 37
        user-facing literals across the shell QML and emits
        docs/SHELL-I18N.md with zh_CN translations for the core surfaces
        (27 ready). Applying them at runtime needs the qsTr + QTranslator
        refactor — the remaining M4 slice, tracked here for the next
        window; Konsole zh_CN .mo already ships (scripts/gen-konsole-mo.py).
  - [x] LLVMpipe: covered by mesa (libgl1-mesa-dri via the KDE stack);
        the boot test runs QEMU/virtio-gpu green since v0.6.9.
  - [x] OTA: aegis-updates (Software Update) already shipped beyond spec.
- Release: qml-guard -> commit -> pull --rebase -> push -> tag v0.6.27 ->
  Release CI builds ISO -> Boot Test (workflow_dispatch, inputs.tag
  v0.6.27) -> verify captures in docs/screenshots/v0.6.27/.
- Release status: first tag push (0abd799) failed twice on runner-side DNS
  (docker bridge lost archive.ubuntu.com — "Could not resolve", exit 100
  in the aegis-shell deb step; Shell CI itself passed, the code compiles).
  Fix shipped 24866bd (--network host) + dc25c23 (pinned 1.1.1.1/8.8.8.8
  into the container resolv.conf + index-verified apt retries in
  build-shell.sh/build-iso.sh — apt-get update exits 0 on W-only fetch
  failures, the verdict comes from apt-cache show). LESSON: when a CI step
  dies on resolve failures for ALL hosts in one pass, it is the runner/
  container resolver, not the code. Then dc25c23 hit a REAL hook bug:
  adw-gtk3-theme is not in the resolute index (universe is in the chroot —
  the multimedia packages installed fine) and the hook's nested heredocs
  shared the EOF delimiter so the inner settings.ini writer terminated the
  outer aegis-gtk-sync writer. Fix 2f7dbf1: tolerant best-effort install
  (Adwaita fallback, accent gtk.css still applies) + distinct heredoc
  delimiters (SYNC_EOF/SETTINGS_EOF/CSS_EOF) + a sh -n sweep of every
  hook. RELEASE SHIPPED: v0.6.27 tag 2f7dbf1, Release success, ISO parts
  published on the release page. The first Boot Test died on the runner
  resolver (45 min inside apt — boot-test.yml got the same DNS guard +
  index-verified retry, fc950f6); the re-dispatch then FAILED ON THE T7
  ASSERT — a real detector bug: band_left_edge anchored at dot_x-2 (inside
  the close dot's own AA span) with a GLOBAL band ref, while the W11
  flush-client band drifts over the wallpaper gradient — the walk stopped
  2 px after the dot ("terminal dot inset 2 outside 14±5"). Fix 512447a:
  anchor at the measured red-span left edge - 2, walk with a LOCAL
  gradient criterion (|Δ| <= 6 per pixel), stop at the frame step.
  Verified against the v0.6.27 artifacts (files 13 / terminal 17 — PASS)
  AND the v0.6.26 captures (13 / 14 — PASS, backward compatible).
  Final Boot Test: SUCCESS — boot-00..17, home/files/terminal/settings/
  aegis-id/control-center/dnd captures committed to docs/screenshots/
  v0.6.27/ (25584f6), zip attached to the release, asserts green. The
  captures visually confirm W11 (band and body share the left edge),
  W12 (Choose image… on the thumbnail line), W14 (hero card + glass
  wells). T10 IS SHIPPED.

### RESUME NOTES (for any fresh session)

- Read this file first, then git log --oneline -5 and git status to see
  how far T10 got. Uncommitted edits mean a step was mid-flight.
- Verification tools that already exist: scripts/analyze-term-window.py
  and scripts/analyze-term-fine.py (pixel anatomy of the terminal window
  capture), scripts/boot-capture.py (runner capture suite),
  scripts/qml-guard.py (syntax guard).
- W11 pixel checks live in the boot capture 03-terminal.png: the band and
  the body must share the same left edge (no body strip wider than the
  band), top corners r18.
- Known pitfalls: repository-wide rg can hang (use per-file rg or glob
  white-lists); WebFetch of github.com trees fails (use
  invent.kde.org GitLab API); ANSI-strip can fake QML corruption in CI
  logs (verify against the file, not the log).
