# AEGIS OS — the hybrid architecture (final)

Status: **adopted** (W103). Decision record, in the user's own words:
*"use rust where it is better and c++ where it is better — like if we use
c++ we can simply copy most of the content from cutefishos … what i want
is the smooth system for icons and ui use cutefish os but for certain
icons and default apps go with aegis icons i gave you and the default
apps i told and remove all the other default apps cutefish and ubuntu etc
uses."*

That is the architecture:

```
┌───────────────────────────────────────────────────────────────┐
│ Aegis app set (desktop/DEFAULT-APPS.md): Files, Terminal,     │
│ Settings, Calculator (adopted, rebranded) + CoreX, Music,     │
│ Store, Editor, Monitor (Aegis-original, rebuilt)              │
├───────────────────────────────────────────────────────────────┤
│ Aegis squircle icon theme (the user's designs) as DEFAULT;    │
│ cutefish icons as system fallback; adwaita last resort        │
├───────────────────────────────────────────────────────────────┤
│ cutefish C++ UI stack, adopted WHOLESALE as submodules:       │
│ compositor (WM + desktop shell + launchpad + lock), fishui,   │
│ qt-plugins, core services, toolkit + framework                │
│ → the "smooth system" — never fork-patched, rebrand lives in  │
│   iso/packaging (desktop-entry renames, icon defaults)        │
├───────────────────────────────────────────────────────────────┤
│ Rust where it is better (aegis-rs/): island-core (the island  │
│ brain, AEGIS-original), the Smithay compositor lab, Store     │
│ and CoreX backend plumbing                                    │
├───────────────────────────────────────────────────────────────┤
│ Debian live ISO vehicle + Aegis plymouth + packaging (the     │
│ cutefish packaging model, per-component debian dirs)          │
└───────────────────────────────────────────────────────────────┘
```

## Why this shape

- **The smooth UI comes ready-made.** cutefish's Qt stack is complete and
  actively developed (the compositor had commits the same day we
  surveyed). Rebuilding that smoothness in Rust from zero is the
  multi-year road; adopting it under our branding is the short one —
  and it is exactly what the user chose.
- **Rust stays where it wins.** The Dynamic Island does not exist in
  cutefish — its brain is Aegis-original Rust with 10 pinning tests. The
  Smithay compositor crate remains the research track (a Rust compositor
  is the round-8+ option once the system ships). Store/apt/CoreX
  plumbing lands in Rust.
- **Provenance stays pristine.** The adopted stack lives as git
  submodules pinned to upstream SHAs — LICENSE files and copyright
  headers untouched, updates are a rebase-free `submodule update`.
  BSD-3 (9 repos) + MIT (terminal) make this clean; their icon theme is
  GPL and keeps its license. Attribution lives in NOTICE.md.

## Rounds (adjusted)

| Round | Delivers |
| --- | --- |
| 2–3 (done) | `old/` quarantine, branding rescued, island-core, aegis-compositor (Smithay), iso/ packaging skeleton, plymouth rebrand |
| 3.5 (this commit) | the adopted stack as submodules, DEFAULT-APPS manifest, aegis-icons package, the hybrid docs |
| 4 | per-component packaging STARTED: aegis-files debian dir + rebrand-at-package-time rules (deb build gated on aegis-framework, the cutefish toolkit package — next); aegis-icons + aegis-id .debs BUILD and INSTALL in CI (the pipeline proof) |
| 5 | the compositor session boots in CI (nested, headless): smoke test + screenshot; desktop-entry rebrand verified |
| 6 | CoreX/Music/Store rebuilt (Video/Editor/Monitor are adopted cutefish bases per the user's W104 decision); Store + CoreX backends in Rust; aegis-sync-os LIVE (Workers/D1, identity reused read-only, docs/SYNC-OS.md); aegis-id.pages.dev LIVE — the central identity portal: create account, Google/passkey/password sign-in, connections/passwords/settings (docs/IDENTITY-PORTAL.md) |
| 7 | iso/live/ assembles the ISO with the package exclusions from DEFAULT-APPS; installer |
| 8 | boot matrix on real hardware; then judge the Rust-compositor question on evidence |

## What was preserved and where

- `branding/` — icons (29 squircle app icons + places + devices), theme
  (wallpapers, sddm, colors), logos, the icon generator.
- `docs/DESIGN-TOKENS.md`, `docs/LIVE-ACTIVITY-API.md` — the island
  contract.
- `aegis-rs/` — island-core + the Smithay compositor (the Rust track).
- `old/` — the previous OS, read-only, until the new system passes its
  boot matrix.
