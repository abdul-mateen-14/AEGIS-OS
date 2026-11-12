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

## T12 — v0.6.35: reviewer round 5 — W16-W23 (TODO)

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

- TODO — all of D1-D11. Session log: none yet.

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
