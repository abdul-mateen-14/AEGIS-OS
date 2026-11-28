# Aegis OS

> Private. Secure. Beautiful. Fast.

**The hybrid system.** The UI layer is the cutefishos desktop — adopted
wholesale as pinned submodules (compositor, fishui, qt-plugins, core
services, apps) — rebranded Aegis, with the user's squircle icon theme as
the default icon set and exactly the Aegis default apps shipped. Rust
stays where it is better: the Dynamic Island (Aegis-original), the
Smithay compositor lab, Store/CoreX plumbing. The previous Qt/QML system
(100 rounds) is quarantined under [`old/`](old/).

- Architecture and why: [`docs/MIGRATION.md`](docs/MIGRATION.md).
- The app manifest — what ships, what is removed:
  [`desktop/DEFAULT-APPS.md`](desktop/DEFAULT-APPS.md).
- Provenance and licenses: [`docs/NOTICE.md`](docs/NOTICE.md).
- Preserved designs: [`branding/`](branding/) — icons, wallpapers, logos,
  sddm theme; the island's contract:
  [`docs/DESIGN-TOKENS.md`](docs/DESIGN-TOKENS.md),
  [`docs/LIVE-ACTIVITY-API.md`](docs/LIVE-ACTIVITY-API.md).

## What exists today (W103)

| Piece | State |
| --- | --- |
| `desktop/` | the adopted cutefish C++ stack — 11 pinned submodules, never fork-patched; rebrand applied at package time |
| `branding/` + `aegis-icons` package | the user's squircle icon theme as the DEFAULT (fallback: cutefish icons → hicolor) |
| `aegis-rs/island-core` | the island's brain in Rust — priority stack, geometry records, spring solver; 10 unit tests |
| `aegis-rs/compositor` | the Smithay compositor (research track) — compiles, tests green |
| `iso/packaging/` | per-component debian dirs + `build.sh`; `aegis-compositor`, `aegis-icons`, `aegis-desktop` |
| `iso/plymouth/aegis-logo/` | boot splash — abyss background, Aegis mark |
| `old/` | the complete previous OS, read-only, until the new system's boot matrix |

## The rounds

Full map in [`docs/MIGRATION.md`](docs/MIGRATION.md). Next up: per-app
packaging (aegis-files sets the cmake+rebrand pattern) → the compositor
session boots headless in CI with a screenshot → CoreX/Music/Store on
fishui → the ISO assembles with the DEFAULT-APPS exclusions → boot matrix.

## CI

`Rust CI` runs on every push: `cargo test --workspace` + clippy (strict)
over `aegis-rs/`, and a structure check over `iso/` + the 11 `desktop/`
submodules.

## Attribution

The desktop UI is [cutefishos](https://github.com/cutefishos) (BSD-3/MIT,
© Reion Wong) adopted as upstream code — submodule provenance in
[`desktop/README.md`](desktop/README.md), license rows in
[`docs/NOTICE.md`](docs/NOTICE.md). The compositor lab is built on
[Smithay](https://github.com/Smithay/smithay) (MIT); the boot splash
derives from the cutefish-logo plymouth theme (GPL-2.0+).
