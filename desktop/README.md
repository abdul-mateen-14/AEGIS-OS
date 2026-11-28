# desktop/ — the adopted C++ UI stack

The user's architecture decision (W103): *"use rust where it is better and
c++ where it is better … copy most of the content from cutefishos … what I
want is the smooth system for icons and ui use cutefish os."*

So the smooth, working UI layer is adopted **wholesale as upstream code**
— as git submodules, never fork-patched:

| Submodule | Upstream | License | Role |
| --- | --- | --- | --- |
| `toolkit` | cutefishos/cutefish-toolkit | BSD-3 | the base library (base/gpu/ui) |
| `framework` | cutefishos/cutefish-framework | BSD-3 | system API clients, files/pdf libs — the compositor's dependency |
| `fishui` | cutefishos/fishui | BSD-3 | the widget/UI library — the "smooth" look |
| `qt-plugins` | cutefishos/qt-plugins | BSD-3 | Qt platform theme (the styling glue) |
| `core` | cutefishos/cutefish-core | BSD-3 | system services (notifications, power, accounts …) |
| `compositor` | cutefishos/cutefish-compositor | BSD-3 | the monolithic Wayland compositor: window management, desktop shell, launchpad, lock screen, Xwayland |
| `icons` | cutefishos/icons | GPL | system icon fallback under the Aegis theme |
| `apps/filemanager` | cutefishos/filemanager | BSD-3 | → Aegis Files |
| `apps/terminal` | cutefishos/terminal | MIT | → Aegis Terminal |
| `apps/settings` | cutefishos/settings | BSD-3 | → Aegis Settings |
| `apps/calculator` | cutefishos/calculator | BSD-3 | → Aegis Calculator |

Why submodules: provenance stays machine-checkable (upstream URL + pinned
SHA in `.gitmodules`), the LICENSE files and copyright headers survive
untouched, and upstream updates are a `git submodule update --remote` away
instead of a merge nightmare.

## The rebrand rule

**The upstream source trees are never modified.** Everything AEGIS lives
in our layer:

- icons: `aegis-icons` (iso/packaging) ships the user's squircle theme
  (`branding/icons`) as the default; the cutefish theme is the fallback.
- names: each app's debian `rules` sed-renames the desktop entries
  (`Name=Aegis Files`, `Icon=aegis-files`) at install time.
- the default-app manifest: [`DEFAULT-APPS.md`](DEFAULT-APPS.md) — the
  Aegis set, the removal list (cutefish extras + Ubuntu stock).

## Build order (packaging lands r3+)

toolkit → framework → fishui → qt-plugins → icons → core → compositor →
apps. Each component gets an `iso/packaging/aegis-<name>/debian/` dir
whose rules build the submodule with CMake and apply the rebrand; the
first one written will be `aegis-files` and set the pattern for the rest.

## The Rust track (where Rust is better)

`aegis-rs/` continues as the Rust layer: `island-core` (the Dynamic
Island's brain — AEGIS-original, no cutefish counterpart, 10 tests) and
`aegis-compositor` (the Smithay lab — kept as the research track for a
future Rust compositor; the shipped session runs the adopted cutefish
compositor). Store/apt plumbing and CoreX's backend also land in Rust.
