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
python3 scripts/qml-guard.py                     # the three boot-test killers:
                                                 # grouped `;`, font.color, Component
                                                 # scope property — plus braces/ids
grep -n dolphin shell/src/util.cpp               # check 7
bash scripts/ci/run-in-container.sh bash scripts/build-shell.sh
# if qmllint 6.x is installed, also:
qmllint shell/src/qml/*.qml 2>&1 \
  | grep -Ei "no property|non-existent|cannot assign|Syntax|duplicate|not a type|cannot declare|is not defined"
# (expected empty — "unqualified access" noise from Aegis.* singletons is fine)
```

## v0.6.13 additions (W8–W15)

13. **Dock icons, two tiers (W8)** — dock close-up: Files/Terminal/
    Settings/Trash keep the squircles; AEGIS Browser / messenger / CoreX
    wear their own marks resolved from the installed .desktop entries
    (`Util.dockApps`), and the alt-tab icon matches the dock tile (same
    entry). No globe, no cloud, no hexagon.
14. **Dock = installed apps only (W9)** — the six web tiles are gone; the
    shelf reads Files · Terminal · AEGIS Browser · Messenger · CoreX · |
    · Settings · Trash; magnification + running dots still work (the
    boot-capture readiness threshold scales with the config now).
15. **One traffic-light geometry (W10)** — Konsole and Files side by side:
    12 px circles, 8 px gap, same inset. (KWin buttons: AegisLightsrc
    ButtonWidth=12 + the 12x12 SVGs; shell inset x:14 → ButtonMarginLeft=14.)
16. **Terminal chrome (W11)** — no toolbar, no scrollbar, JetBrains Mono 11,
    ink background, accent prompt; the window title reads "Aegis Terminal"
    with NO " — Konsole" suffix. Two mechanisms carry this: the kxmlgui5
    overrides (/usr/share/kxmlgui5/konsole/{konsoleui,sessionui}.rc with
    hidden="true" — since Konsole 25.12 the built-in XML is compiled into
    the binary, so a DEPLOYED file under kxmlgui5/ is the only hook that
    reaches KToolBar::loadState), and the konsole.mo display-name override
    (must be a REAL MO — PO text loads as "Bad magic number" and gettext
    silently skips it, which is how the suffix survived v0.6.13; the
    generator asserts pgettext("@title","Konsole") resolves). If the
    suffix returns, check LANGUAGE=en_US reached the session and the .mo
    passes `msgfmt -o /dev/null` as a catalog.
17. **Top-bar glyphs (W12)** — Wi-Fi arc, volume, clock, CC glyph: same
    optical size, same 2 px weight, fg at 90%; muted/off states dim the
    glyph live (the Canvas repaints on tint changes now).
18. **Control Center spacing (W13)** — DND wide tile is a real wide-toggle
    (bell + label left, switch right, on AND off captures); both sliders
    end at the same right margin; 36 px power row; the footer echo shows
    the live accent hex, not "KWin Wayland".
19. **Boot splash (W14)** — boot-00/01 show the mark centered over ink with
    the accent progress line ("splash: centre bright pixels" in the log).
    The hard assert lands the tag AFTER a capture proves the theme; if the
    centre is black, the 0200 hook fell back to ubuntu-text — check
    script.so and the aegis-mark assets first.
20. **Files grid metrics (W15)** — 84 px cards, 16 px gutters, 12 px Medium
    labels 6 px below the card, 20 px margins, one row rhythm; capture
    shows folders AND mixed files; the status footer stays the bottom rail.
