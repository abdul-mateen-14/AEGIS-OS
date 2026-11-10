# VERIFY — run before tagging ANY release

The v0.6.3 review caught a regression (window titles) that shipped in two
releases because this list was not re-run. Eight checks, ~10 minutes, every
tag. Evidence = screenshots in `docs/screenshots/<tag>/` (boot-test captures
them; the checklist only interprets them).

## The 8 checks

1. **Corners** — open any first-party window, look at the bottom edge:
   bottom radius equals top radius (18 px, KDE-Rounded-Corners).
2. **Places** — Files sidebar: exactly Home, Documents, Downloads, Music,
   Pictures, Videos, Trash. No Remote, no Recent, no Network, no Floppy.
3. **Glyphs** — sidebar + dock icons are the Aegis tinted set, not Breeze grey.
4. **Apps are real** — dock Files/Settings open the glass windows with
   traffic lights and NO "— Dolphin" / "System Settings" chrome.
5. **Files app** — grid⇄list; search filters live; breadcrumbs jump; New
   Folder; right-click → Cut/Copy/Open With/Rename/Move to Trash/Properties;
   status footer counts items + hidden; sort menu (name/date/kind/size).
6. **Settings app** — sidebar: Aegis ID row first, then Wallpaper →
   Appearance → Desktop Effects → Drivers & Firmware → Displays → Sound →
   Network → Users. Light flip works; tier badge in Control Center follows
   the segmented control; the four M3 panes show real data (kscreen-doctor
   outputs, wpctl sinks, NM networks, AccountsService users).
7. **No stock leakage** — `grep -n dolphin shell/src/util.cpp` is clean;
   window titles never say Dolphin/System Settings.
8. **Accent is one token** — pick a non-default accent in Appearance: the
   Settings window, Files hover hairlines, Control Center highlights and
   the New Folder button all recolor together; it persists across restart
   (`~/.config/aegis/tokens.conf`).

## v0.6.9 additions (W1–W6)

9. **Kind tints** — 02-files shows mixed types: PDF red, archive amber,
   image purple, audio pink, text blue, folders blue (boot-capture seeds
   one file of each kind into $HOME over serial).
10. **Live wallpaper** — Wallpaper pane tile click repaints the desktop
    immediately; "Choose image…" opens the glass picker; a custom pick
    survives a shell restart (session prefs).
11. **Aegis ID pane** — signed-out renders "Local account · sync off";
    sign-in derives keys (status line shows the KDF step); devices list
    shows THIS DEVICE; revoke removes a row; sync now pushes accent/
    wallpaper/files.prefs (check `~/.config/aegis/sync-state.json`).
12. **Recovery key** — create-account shows the one-time key card; "I saved
    it" dismisses it for the session; it never reappears (by design).

## Local pre-push sanity (no ISO needed)

```bash
python3 scripts/check-qml.py                     # brace/id/junk scan
grep -n dolphin shell/src/util.cpp               # check 7
bash scripts/ci/run-in-container.sh bash scripts/build-shell.sh
```
