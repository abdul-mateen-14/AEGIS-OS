# AEGIS OS — the default app set

The user's rule: *"for certain icons and default apps go with aegis icons I
gave you and the default apps I told — and remove all the other default
apps cutefish and ubuntu etc uses."*

## What ships (the Aegis set)

| Aegis app | Working base | Notes |
| --- | --- | --- |
| Aegis Files | `desktop/apps/filemanager` | the smooth cutefish file manager, rebranded |
| Aegis Terminal | `desktop/apps/terminal` | rebranded |
| Aegis Settings | `desktop/apps/settings` | rebranded |
| Aegis Calculator | `desktop/apps/calculator` | rebranded |
| CoreX (browser) | Aegis-original | the browser is ours; its shell integrates the fishui look; engine plumbing rebuilt on the Rust track |
| Aegis Music | Aegis-original | rebuilt on fishui, backend from the old system's design |
| Aegis Store | Aegis-original | apt/flatpak plumbing in Rust (r6) |
| Aegis Monitor | adopt `cutefishos/system-monitor` as base | replaces the old buggy backend |
| Aegis Editor | adopt `cutefishos/text-editor` as base | replaces the old buggy backend |
| Dynamic Island + dock + launchpad | `desktop/compositor` | the monolithic compositor's shell — the "smooth" layer the user wants |

Every adopted app keeps the **Aegis icon** from `branding/icons/` (the
squircle theme) and a `Name=Aegis …` desktop entry applied at package
time — the upstream source trees are never patched, the rebrand lives in
`iso/packaging/`.

## What is REMOVED (never ships)

- cutefish extras: calendar, clock, text-editor (superseded by Aegis
  Editor), video-player, disk-utility, preview, computer-use, screen
  recorder.
- Ubuntu/GNOME stock: nautilus, gnome-terminal, gnome-text-editor,
  gnome-software, snapd, firefox/chromium as default browser (CoreX is
  the browser), libreoffice, gnome-core/minimal bloat, ubuntu-report,
  pop-up survey and telemetry packages.

The ISO package lists (`iso/live/`, r7) encode this list as exclusions;
the `aegis-desktop` metapackage depends only on the Aegis set above, so
installing nothing else is enough.

## Icon layering

1. **Aegis** (`branding/icons` → `/usr/share/icons/Aegis`, the
   `aegis-icons` package) — every app icon, places, devices. Default
   theme, set by `aegis-icons` postinst.
2. **cutefish icons** (`desktop/icons`, GPL) — system fallback for
   generic glyphs (mime types, hardware) the squircle set does not cover.
3. **adwaita-icon-theme** — last-resort fallback (the compositor's
   runtime requirement).
