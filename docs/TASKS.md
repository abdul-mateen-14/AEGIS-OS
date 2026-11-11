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

## T11 — v0.6.28: M3 apps on the dock + in the boot captures (CURRENT)

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
- D4 — release: qml-guard -> commit -> pull --rebase -> push -> tag
  (v0.6.28 was burned by the D5 defects; the fix batch re-releases as
  v0.6.29) -> Release CI builds the ISO -> Boot Test (workflow_dispatch,
  inputs.tag v0.6.29) -> verify 04c..04f captures exist and the asserts
  stay green -> mark T11 SHIPPED here with the run numbers.

### Status

- D1-D3 DONE in tree (commit 22fda7c); D5 fixes DONE in tree (this
  commit); D4 release pending on the tag.

- D1-D3 detail: four Tier A slots in config.json +
  the util.cpp mirror; boot-capture.py grew the four open_app captures
  (04c-music / 04d-calculator / 04e-editor / 04f-monitor, click_idx 5-8),
  Settings click_idx moved to 9, the opens release gate covers all seven
  first-party apps, app_diag grew PROBE-M/C/E/N foreground probes (music
  filters pipewire/pulse/gstreamer/alsa chatter out of its DIRTY verdict
  and its fetch). qml-guard PASS (21), py_compile PASS, config parses
  11 tiles. Shell CI compiles this push; tag v0.6.28 after green.
- D4 — release: pending (tag v0.6.28 once Shell CI is green on 22fda7c).

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
