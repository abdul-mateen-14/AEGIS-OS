# AEGIS OS — the complete Rust migration

Status: **new system started** (W102). Decision record: the previous QML
shell (100 rounds, now `old/`) never reached the completeness of a mature
desktop and its apps' backends kept regressing. The new system adopts the
cutefishos DESIGN and ISO MODEL as the base and rebuilds the ENTIRE desktop
stack in Rust. The user's direction: *"create everything from scratch and
use rust completely… pick the cutefish iso source files, edit the brand
details, the icons I said to maintain, and the whole c++ code with rust —
I need complete migration."*

## Why Rust (the honest engineering answer)

Rust does not automatically run faster or use less RAM than C++ — both are
native, GC-free languages with comparable steady-state performance. The
real wins for AEGIS:

1. **Memory safety in the compositor** — the process that touches the GPU,
   every window's buffers and untrusted Wayland clients. C++ compositors
   die by use-after-free and data races; Smithay-based Rust compositors
   cannot have those classes of bugs.
2. **No Qt runtime weight** — the old stack's RAM was never the language,
   it was Qt/QML's scene graph and runtime. The Rust stack (Smithay +
   iced-class UIs) drops that layer entirely.
3. **Fearless refactoring** — the compiler carries the migration; a 400k
   line port is possible precisely because behavior contracts are pinned
   by tests (island-core's 10 tests are the pattern).

The reference that this is viable in production: System76's COSMIC — a
full Rust desktop (compositor, panel, launcher, apps) shipping on
Pop!_OS.

## Attribution and licenses

- **Smithay** (compositor framework, MIT) — `aegis-compositor` is adapted
  from Smithay's `minimal` example, MIT notice retained in the source.
- **cutefish plymouth theme** (GPL-2.0+) — `iso/plymouth/aegis-logo/`
  derives from cutefish-logo; GPL header + author credits retained, colors
  and logo rebranded.
- **cutefishos** — surveyed as the design/ISO model. Its C++ code is NOT
  vendored: the migration is a Rust re-implementation of the same role
  each cutefish component plays, not a line-by-line translation (a Qt/C++
  → Rust translation cannot be literal — the toolkits don't map).
- AEGIS-original code: MIT.

## The round map (each round = one session, CI-green at the end)

| Round | Delivers | Replaces (cutefish role) |
| --- | --- | --- |
| 2 (done) | `aegis-rs/` workspace: `island-core` (island brain, 10 tests) + `aegis-compositor` (Smithay, nested winit, xdg-shell, stack layout seed); `iso/` packaging + plymouth; `old/` quarantine; branding rescued | — |
| 3 | DRM/udev backend + libinput seats (real hardware sessions); `zwlr_layer_shell_v1` in the compositor; `aegis-shell` v0: the island renderer (island-core drives the springs) + the dock as layer surfaces | compositor shell/, kwin effects |
| 4 | `aegis-terminal` (Rust, vte-class backend), the launcher (type-to-filter on the layer-shell surface) | terminal, launcher |
| 5 | `aegis-files` (the backend that plagued the old OS, rebuilt on Rust fs primitives + inotify), Control Center | filemanager, settings |
| 6 | `aegis-music`, `aegis-store` (flatpak/apt plumbing in Rust), CoreX browser shell integration | apps |
| 7 | `iso/live/` live-build config assembles the ISO: kernel+firmware+NetworkManager vehicle, aegis-desktop metapackage, plymouth, the installer (adopt cutefish-installer's flow, port to Rust) | ISO/installer |
| 8 | The boot matrix on real hardware; effects pass (blur as a render element — the QML war becomes a shader); `old/` sources deleted once the new system passes every assert the old one passed | — |

## What is preserved from the old system

- `branding/icons/` — the 29-icon squircle theme (settings, store, music,
  terminal, files, corex …) — the user's designs, verbatim.
- `branding/theme/` — wallpapers, sddm, colors, desktop entries.
- `branding/logos/` — the Aegis mark.
- `docs/DESIGN-TOKENS.md`, `docs/LIVE-ACTIVITY-API.md` — the island's
  behavior contract the Rust port must satisfy (island-core already does).
- `old/` — everything else, quarantined read-only until round 8.
