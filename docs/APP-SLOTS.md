# First-party app slots — AEGIS Browser · OS · CoreX

The ISO ships all three first-party `.deb` apps. The links arrived
2026-11-09 and are wired in via `debian-live/app-deb-urls.txt`
(one URL per line, `URL|name` accepted for Google Drive links whose
basename is useless).

## The three slots — wired in

| App | Package | Binary | Dock tile | Default-browser role |
| --- | --- | --- | --- | --- |
| AEGIS Browser | `aegis-browser-stable 156.0.8078.79-1` (r31 prerelease x64 deb, 116 MB — proper rebrand, replaces the 614 MB chromium repack r24) | `/usr/bin/aegis-browser-stable` → `/opt/aegis-browser/browser/aegis-browser` | `web-browser` icon, cmd `aegis-browser-stable` | **Yes** — skel `mimeapps.list` maps http/https/html/xhtml to `aegis-browser.desktop`; Gmail/YouTube/GitHub/X/WhatsApp/ChatGPT web tiles open in it via `xdg-open` |
| OS (private messenger, full E2E) | `os-private-chat 2.8.33` (93 MB) | `/usr/bin/os-private-chat` → `/opt/OSPrivateChat/os-private-chat` | `aegis-cloud` icon, cmd `os-private-chat` | — |
| CoreX trading terminal | `corex-terminal 1.1.0` (102 MB) | `/usr/bin/corex-terminal` → `/opt/CoreX Terminal/corex-terminal` (postinst update-alternatives + symlink) | `aegis-corex` icon, cmd `corex-terminal` | — |

No other browser ships in the image (no firefox / epiphany / distro
chromium in any package list) — AEGIS Browser is the only one.

Dependency note: the ISO base is Ubuntu **resolute**, where GTK/ALSA/CUPS
libraries were renamed for 64-bit time_t (`libgtk-3-0t64`, …). Those
packages carry versioned `Provides:` for the old names
(`libgtk-3-0 (= 3.24.52-0ubuntu1)` etc., verified against the resolute
index), so all three debs install unmodified.

## Wiring a .deb in (three ways, pick any)

1. **Repo variable (CI, no code changes)** — Settings → Secrets and variables
   → Actions → Variables → `AEGIS_APPS_DEB_URLS`, one URL per line. The ISO
   workflow downloads and stages them automatically.
2. **`debian-live/app-deb-urls.txt`** — commit the URLs (one per line,
   `#` comments, `URL|name` optional). Works locally and in CI. ← active
3. **Drop files** — put the `.deb`s directly in
   `debian-live/config/packages.chroot/` (gitignored) for local builds.

live-build installs everything in `packages.chroot/` via apt inside the
image, so archive dependencies resolve normally.

## Alignment checklist — done

- [x] **Dock commands**: `shell/packaging/config.json` and the
      `util.cpp` fallback config use the real binaries
      (`aegis-browser-stable`, `os-private-chat`, `corex-terminal`);
      the "OS Cloud" tile is renamed "OS".
- [x] **Desktop entries**: stopgap `aegis-web-oscloud.desktop` /
      `aegis-web-corex.desktop` deleted; the debs ship their own
      (`os-private-chat`, `corex-terminal`, `aegis-browser`,
      `org.aegisbrowser.Aegis`).
- [x] **Binary names**: confirmed with `dpkg-deb -c` — browser is
      `aegis-browser-stable` (StartupWMClass `aegis-browser`, r31 rebrand;
      the r24 repack used `chromium-browser-stable`),
      messenger `os-private-chat`, terminal `corex-terminal`.
- [x] **Icons**: dock tiles use the Aegis squircle theme
      (`web-browser`, `aegis-cloud`, `aegis-corex`) — consistent with the
      proposal's icon language rather than each vendor's stock icon.
- [x] **Default browser**: `etc/skel/.config/mimeapps.list` sets
      `aegis-browser.desktop` for http/https/html/text-plain/xhtml.
- [x] Smoke-build: v0.5.0 (r24 chromium repack) and v0.5.1 ISOs built
      green; v0.5.2 (r31 rebrand + fixed-shelf tray) pending boot test.

## Upgrading AEGIS Browser later

When the next r-series build ships, replace the URL on the
AEGIS Browser line of `debian-live/app-deb-urls.txt` and cut a new tag —
nothing else needs to change (binary name stays `aegis-browser-stable`
in the r31+ rebranded packages).

The browser's own logos live under `/opt/aegis-browser/browser/`; the
`0700-app-icons` hook links the 256px one into `/usr/share/pixmaps/` so
the stock desktop entries resolve `Icon=aegis-browser`.

## First-party Files & Settings — `aegis-apps` (v0.6.5)

The dock's Files and Settings tiles no longer launch Dolphin / System
Settings. They launch **first-party Qt Quick windows** from the
`aegis-apps` binary, built with the shell:

| Slot | Binary | QML surface | What it replaces |
| --- | --- | --- | --- |
| Files | `/usr/bin/aegis-files` → `aegis-apps files` | `shell/src/qml/FilesApp.qml` | `dolphin` |
| Settings | `/usr/bin/aegis-settings` → `aegis-apps settings` | `shell/src/qml/SettingsApp.qml` | `systemsettings` |

- **Window anatomy** (`AppWindow.qml`, proposal Table 18): 44 px glass
  titlebar with traffic lights (`TrafficLights.qml`, Table 14 hues), 52 px
  opaque toolbar with hairline, opaque radius-18 body, 8 × 6 px resize
  zones via `startSystemResize`, min size 520 × 360.
- **Files**: seven-place sidebar (Home/Documents/Downloads/Music/Pictures/
  Videos/Trash — matches the preseeded `user-places.xbel`), breadcrumbs,
  grid⇄list, live search, New Folder, rename, move-to-trash,
  kind-tinted cards (folders blue · PDFs red · archives amber · images
  purple), Devices section when removable media is present.
- **Settings**: Aegis ID rail (38 px avatar, `Util.userInitials`/`userName`)
  atop the §6 pane order — Wallpaper · Appearance (Dark/Light wired to
  `Util.setDarkMode`) · Desktop Effects (tier control writes
  `Governor.setTier`/`setAutoMode` **live**) · Drivers & Firmware
  (six BUILT-IN domains) · Displays · Sound · Network · Users (M3 stubs).
- **Titles are correct by construction**: `Window.title` is set in the
  app's own QML, so no KWin title rules are needed (KWin `title` is a
  match-only criterion — see commit `8a47eb4`).
- **Folder opening**: `mimeapps.list` maps `inode/directory` to
  `aegis-files.desktop`, so `xdg-open <dir>` never falls through to
  Dolphin (no "— Dolphin" titlebars anywhere).
- **Dolphin is not removed** — it remains available for power users; the
  preseeded `dolphinrc` hides its menubar and opens on Home so even the
  fallback is on-language. The dock Trash tile opens `aegis-files`
  (sidebar → Trash) rather than a Dolphin window.

Regenerating the tinted place/device glyphs: `scripts/gen-places-icons.py`
(writes every `places/scalable` + `devices/scalable` SVG in the Aegis theme).
