# AEGIS-OS — Build Instructions v0.6.35
**Reviewer:** Aegis-OS UI v1.3 author review of **v0.6.34** (screenshots `docs/screenshots/v0.6.34/`, repo @ cf5a98e)
**Scope:** verdict on v0.6.34, five defects to fix, three new feature rulings (W20–W22), two test gaps (W23). Numbering continues after W15 (Files grid metrics).

---

## §0 Verdict in one line

v0.6.34 is the closest build yet to the v1.3 design — the boot mark is back, the terminal is ONE anatomy, the battery exists, the DND row is fixed, and every dock slot carries its real icon. What remains: **4 rendering/config defects, the three new rulings below, and 2 boot-test blind spots.**

---

## §1 Confirmed fixed in v0.6.34 (evidence-checked, do not regress)

| # | Ruling | Evidence |
|---|--------|----------|
| 1 | **Boot: mark back, no lines** | `boot-04.png`: centered Aegis mark on ink `#08090C`, single 240×2 accent progress line, no text noise, no stray lines. `0200-plymouth.hook.chroot` two-step ladder is sound (W14). |
| 2 | **Terminal: ONE traffic-light anatomy** | `03-terminal.png`: single 44 px band, dots 12 px, red edge at x≈14, gap 8, caption centered ("Aegis Terminal", no " — Konsole" suffix via the `kdeglobals [Locale]` konsole.mo override), no menu row. `AegisLightsrc` now mirrors `TrafficLights.qml` (ButtonWidth 12 / spacing 8 / TitleEdgeLeft 18 → dot edge 14) and `kwinrc BorderSize=None` gives the 0/44/0/0 anatomy. The W10/W11 geometry ruling is executed, and `boot-capture.py::header_geometry_assert` locks it. |
| 3 | **Top bar right cluster** | `01-home.png`: Wi-Fi + volume + **battery** + date + control-center icon, one consistent outline weight. Battery absence complaint closed. |
| 4 | **DND row** | `05/05b-control-center*.png`: clean outline bell, full-width row, correct padding; ON state is accent-filled toggle. Complaint closed. |
| 5 | **W8 real icons + M3 pins** | `01b-dock-magnify.png`: Files, Terminal, Aegis Browser mark, OS Private Chat, **CoreX CX logo**, Music, Calculator, Editor, Monitor, Settings, Trash — all real artwork, magnification + label working, four M3 apps pinned with captures. |
| 6 | **W9 no web tiles** | Dock carries zero web shortcuts. Keep it that way (see W22 — opt-in only). |
| 7 | **T11 deterministic deb install** | `0900-app-debs-fallback.hook.chroot` + includes-chroot path; browser slot restored in the dock. |

---

## §2 Defects — fix in v0.6.35

### W16 (fix) — Files kind tints do not render as ruled (§8.1)
`02-files.png` measured against the ruling (PDF `#FA2D48` · archive `#FF9F0A` · image `#8B5CF6` · audio `#FF6B84` · text blue `#3E8BFF`):

| File | Model says (`filemanager.h::metaFor`) | Actually renders |
|------|------|------|
| `report.pdf` | tint `#FA2D48` red | **blue** folder-documents glyph (stroke sampled `74,155,255`) |
| `archive.zip` | tint `#FF9F0A` amber | **gray** generic text glyph (fallback `#8A909C`) |
| `notes.txt` | tint `#3E8BFF` blue | **gray** generic text glyph |
| `photo.png` / `track.mp3` | `#8B5CF6` / `#FF6B84` | correct ✔ (because those theme SVGs are pre-colored) |

Root cause: `FilesApp.qml` grid delegate renders `image://icons/<name>` and `IconProvider` (main.cpp / apps-main.cpp) returns the **pre-colored theme SVG by icon name** — the sniffed `tint` role never reaches the stroke. Archives additionally have no dedicated glyph (fall back to `text-x-generic`).

Fix (single source of truth, not per-icon patches):
1. Extend the provider: `image://icons/<name>?tint=%23FA2D48` — recolor the SVG stroke at request time (template recolor, keep the glyph).
2. Map document kinds to **document** glyphs, not folders: PDF → doc-page glyph tinted `#FA2D48`; archive → box/zip glyph tinted `#FF9F0A`; text → doc-line glyph tinted `#3E8BFF`; keep folder/image/audio/video as is.
3. Assert it: `boot-capture.py` samples the `report.pdf` icon stroke in the Files capture and fails the release if it is not ≈ `#FA2D48` (tolerance ΔE you already use for the traffic lights).

### W17 (fix) — Monitor renders empty data as honest-looking lies
`04f-monitor.png`: the **Cores card is completely empty** (label only, no bars) and Memory reads **"0.0 GB of 0.0 GB"** while the process table shows real RSS numbers. afb1ad6 fixed the `toFixed` crash but the underlying `memTotal`/per-core reads are still zero in the capture environment.
Fix: read `MemTotal` from `/proc/meminfo` (KiB→GB) and per-core occupancy from `/proc/stat`; when a source is unavailable, **hide the card or show an explicit "unavailable" placeholder** — never a blank card. Add both to the QML probe verdicts (a blank Cores card must go red in boot-test).

### W18 (fix) — Pin the type: `[WM] activeFont` and `[General] font` are missing
`etc/xdg/kdeglobals` carries no `[WM] activeFont` and no `[General] font`, so window captions (AegisLights renders captions — `TitleAlignment=Center`, `ActiveTextColor` set) and every Qt widget app fall back to the session default font, not **Montserrat 13 DemiBold / Montserrat 10**. GTK already gets `Montserrat 10` via the 0810 hook; the Qt/KWin side is unpinned.
Fix: add to the kdeglobals template
- `[WM] activeFont=` Montserrat 13 DemiBold — set it once in a live session through the Fonts KCM and copy the exact KConfig-serialized value (do not hand-roll the CSV),
- `[General] font=` Montserrat 10 (same method).

Then re-check the terminal caption crop in the next boot-test: same glyphs as `TrafficLights`' hover font family.

### W19 (fix) — GTK CSD windows still put the close button on the right
The M4 GTK interop (0810) is good work — theme, accent, cursor, font, live sync. But `settings.ini` has no `gtk-decoration-layout`, so GTK3/GTK4 headerbar apps (and libadwaita) keep **close/maximize on the right**, breaking the one-anatomy rule the aurorae side just achieved.
Fix: add to both `gtk-3.0` and `gtk-4.0` `settings.ini` (skel **and** `aegis-gtk-sync` writer):
```ini
gtk-decoration-layout=close,minimize,maximize:
```
(everything left of the colon sits on the left; apps that hardcode their layout will stay wrong — acceptable, documented.)

### V1 (verify, no code yet) — Dock magnification clips the end tiles
`01b-dock-magnify.png`: while Music is magnified, the leftmost tile (Files) is cut by the dock pill's left edge. The pill's horizontal padding must grow by the same delta the magnified icons add. One-line layout check; add a magnified-state capture to the probe set so this stays asserted.

### Carry-over pending confirm (from the v0.6.10 round)
- **Control Center / Settings logo**: still no Aegis mark in the CC panel header (top-right) nor in Settings. If the v1.3 ruling stands, add the 18 px mark to both; if it was dropped intentionally, say so and I close the item.

---

## §3 New rulings — feature work for v0.6.35

### W20 (feature) — Dynamic Island auto-hide
Ruling from the user, verbatim intent: *when an app/window is open full, the island hides itself — invisible — with a fast dissolve that shrinks toward its center point; it only shows up when an island task happens (a notification came) or when its content keeps working continuously (like music).*

Behavior contract:
1. **Trigger:** the idle island hides whenever the active workspace has an open app window (maximized, fullscreen, or simply any normal window — predicate exposed as one property so it can be tuned later).
2. **Hide animation:** from the idle state only — scale **1 → 0** with `transformOrigin: Item.Center` + opacity fade, ~200 ms, ease-in (InCubic). It visibly "dissolves into its own center point". No slide, no fly-up.
3. **Show again (any of):** a notification/call/charging/timer/Aegis-ID activity arrives (any non-idle state overrides the hidden idle); continuous content is active — `nowPlaying` (music) **stays visible** while playing; the workspace becomes empty again (windows closed → idle island returns with a reverse grow-from-center, ~320 ms OutBack for a subtle spring).
4. **Never** interrupt or hide a non-idle state; activity states always win over the window predicate.

Prerequisite — real window tracking (this also fixes a known gap you already documented in `util.h:100-103`): replace the launch-recorded `runningCmds` backing store with a shipped **KWin script**: connect `workspace.windowAdded/windowRemoved/activeWindowChanged`, count normal windows on the active workspace + any maximized/fullscreen flag, and push over DBus into the existing `org.aegis.Shell` surface (`WindowListChanged(count, anyFull)`). Keep the QML contract (`isRunning` / `runningCmdsChanged`) unchanged — the dock running dots start working for foreign-launched apps (e.g. CoreX opened from Files) as a free side effect.

### W21 (feature) — macOS-style window open/close, anchored at the dock
Ruling: *add the window opening and closing animation like macOS, which comes when we open/close an app from a dock.*

- **Open:** window grows out of its dock tile — scale ≈ 0.3 → 1 with the transform origin at the **tile's center**, opacity 0 → 1, ~280 ms OutCubic.
- **Close:** reverse — shrink into the tile (scale → 0.3, fade out, ~200 ms InCubic).
- **Minimize/restore:** same path as close/open (the honest approximation of genie; do not attempt mesh distortion).
- **Implementation:** a KWin **scripted effect** (`aegis-dockzoom`, enabled via `kwinrc [Plugins] aegisDockzoomEnabled=true`). The shell publishes a tile map (app-id → icon rect in screen coords) via the same DBus surface (or `$XDG_RUNTIME_DIR/aegis/dock-map.json` the effect reads on `windowAdded`). Filter: normal windows only — never layer-shell shell surfaces (panel/dock/island/desktop) or popups/menus.
- **Fallback** if the scripted effect proves unstable on 6.6: enable the stock `kwin4_effect_scale` with ~240 ms duration and center origin — acceptable to ship, but the tile-anchored version is the ruling.
- This builds on W20's window tracking (app-id matching), so land W20 first.

### W22 (feature) — Dock web shortcuts, strictly opt-in
Ruling: *allow browser shortcuts/links (like Gmail) in the dock with their original favicons/logos — but only if the user adds them; by default do not add any.*

- **Default dock contains ZERO web shortcuts** (W9 continues to hold; the capture set must prove the default state).
- User flow: dock right-click / long-press on empty area → **"Add to Dock…"** → user pastes a URL → shell fetches the page title + icon (`<link rel="apple-touch-icon">` → `favicon.ico` → generated letter-tile fallback with the site's theme color).
- Persist as standard entries: icon PNG → `~/.local/share/aegis/webicons/<hash>.png`, launcher → `~/.local/share/applications/aegis-web-<hash>.desktop` (`Exec=xdg-open <url>`). The W8 resolver then displays it automatically with the real favicon — no dock-side special casing.
- Same menu removes the shortcut (deletes both files). Order: user-added entries append after the last first-party slot, before Trash.
- **Dedupe rule (known edge from the browser deb anatomy):** `aegis-browser-stable` ships two identical entries — `aegis-browser.desktop` and `org.aegisbrowser.Aegis.desktop` (same Name/Exec/Icon/StartupWMClass). The resolver must dedupe by `StartupWMClass` or `Exec` basename, or the dock shows the browser twice the moment the deb is installed. This dedupe applies to **all** resolvers that walk `.desktop` files (dock, launcher, Open With).

---

## §4 Test gaps — W23 (boot-capture)

1. **Assert the decoration config, don't just dump it.** The run log prints `===KWINRC===` but nothing fails if `theme=__aurorae__svg__AegisLights` or `ButtonsOnLeft=XIA` regresses. Parse the dump and fail the release on drift (this is the same class of bug as the v0.6.20 boot regression that shipped green).
2. **Capture and assert the SDDM greeter.** In `v0.6.34/boot-14/15` are pure black frames — the greeter (mark + accent progress device + clock, the B3 continuity device) is never verified between splash and session. Add one capture between them + a pixel assert (mark present, progress line present). The greeter is currently one `sync-includes.sh` slip away from regressing invisibly.
3. Add the **tint assert** (W16) and the **Monitor card assert** (W17) to the probe verdicts.
4. Add the **magnified-dock capture** (V1) to the probe set.

---

## §5 Standing hard rules (unchanged)

- Every release is gated by boot-test asserts; a probe that cannot fail is not a probe (v0.6.20 lesson).
- Every app start must leave `errorString` empty — QML grouping properties on the same line as `;`, `showDotAndHidden` vs Qt6 `showHidden` class of bugs.
- v1.3 tokens only: accent six-preset set, glass tokens, 44 px band, 12 px dots at x14/gap 8 — one anatomy for CSD and aurorae, asserted, not assumed.
- No web tiles in the default dock — ever (W22 changes nothing about the default).

*End of instructions — W16–W23 in order, D/V items are one-liners. Ship v0.6.35 with the capture set extended per §4.*
