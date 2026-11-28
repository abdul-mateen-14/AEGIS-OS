# Aegis OS

> Private. Secure. Beautiful. Fast.

**The Rust system.** AEGIS OS is being rebuilt from scratch as a fully
Rust desktop — compositor, shell (Dynamic Island + dock), launcher and
apps — on the cutefishos design and packaging model, shipping as a Debian
live ISO. The previous Qt/QML system (100 rounds of iterations) is
quarantined under [`old/`](old/) and will be deleted once the new stack
passes its boot matrix.

- The honest Rust answer: it is not automatically faster or leaner than
  C++ — the wins are memory safety in the compositor, dropping Qt's
  runtime weight, and a migration the compiler can carry. See
  [`docs/MIGRATION.md`](docs/MIGRATION.md).
- Provenance and third-party licenses: [`docs/NOTICE.md`](docs/NOTICE.md).
- Preserved designs: [`branding/`](branding/) — the user's icon theme
  (settings, store, music, terminal, files, corex …), wallpapers, logos,
  sddm theme — and the island's behavior contract
  ([`docs/DESIGN-TOKENS.md`](docs/DESIGN-TOKENS.md),
  [`docs/LIVE-ACTIVITY-API.md`](docs/LIVE-ACTIVITY-API.md)).

## What exists today (W102)

| Piece | State |
| --- | --- |
| `aegis-rs/island-core` | the Dynamic Island's brain in Rust — priority stack, geometry records, spring solver; 10 unit tests pinning the contract |
| `aegis-rs/compositor` (`aegis-compositor`) | the Wayland compositor on Smithay — nested winit backend, xdg-shell window mapping, stack-layout seed; the DRM/udev + layer-shell rounds follow |
| `iso/packaging/` | per-component `debian/` dirs + `build.sh` (the cutefish packaging model), `aegis-desktop` metapackage |
| `iso/plymouth/aegis-logo/` | boot splash — abyss background, Aegis mark |
| `old/` | the complete previous OS, read-only, until round 8 |

## The migration rounds

Full map in [`docs/MIGRATION.md`](docs/MIGRATION.md). Short form:
compositor on real hardware + the island renderer (r3) → terminal +
launcher (r4) → files + control center (r5) → music, store, CoreX (r6) →
the ISO assembles itself in live-build (r7) → boot matrix, effects,
`old/` deleted (r8).

## CI

`Rust CI` runs on every push: `cargo test --workspace` + clippy (strict)
over `aegis-rs/`, plus a packaging-structure check over `iso/`.

## Attribution

The compositor is built on [Smithay](https://github.com/Smithay/smithay)
(MIT); the boot splash derives from the cutefish-logo plymouth theme
(GPL-2.0+); the packaging model follows
[cutefishos](https://github.com/cutefishos). Details and license rows:
[`docs/NOTICE.md`](docs/NOTICE.md).
