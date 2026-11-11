# Design tokens — proposal → code map

Every numeric value in the shell traces to a table of the **Aegis OS UI Design
Proposal v1.3** (29-page implementation-grade spec) with one deliberate v1.4
product override. The single source of truth is
[`shell/src/qml/Tokens.qml`](../shell/src/qml/Tokens.qml).

| Token group | Proposal source | Code |
| --- | --- | --- |
| Panel height 28 px, square, hairline bottom | §2.1 Table 3 | `panelHeight` |
| Tile 56×64, r15, gap 2; tray r22 pad 14; 549×80 expanded; 10 px margin | §2.2 Table 4 | `tile*`, `tray*`, `dockMargin` |
| Magnification 1.85× peak, ±2.4-tile linear falloff, 0.85 strength | §2.2 recipe (1)(2) | `magPeak`, `magFalloff`, `magStrength`, `Dock.targetFor()` |
| Spring mass 0.1 · stiffness 170 · damping 13, two Euler substeps | §2.2 recipe (3) | `dockSpring*`, `Spring.step()` |
| Running dot 4 px, 4 px clear | §2.2 | `dotSize`, `dotGap` |
| Label 8 px above magnifying icon top | §2.2 recipe (4) | `Dock.updateLabel()` |
| Launch bounce y [0, −0.32B, 0, −0.12B, 0] @ 0.65 s | §2.2 recipe (5) | `bounce*`, `bounceAnim` |
| Sliver 120×4, probe 8 px/150 ms, spring 350 ms; auto-hide 4 s | §2.2 Table 4 | `sliver*`, `idleHideMs` |
| Glass tint ink 52% · border white 14% · highlight white 10% · blur 28/sat 1.6/bri 1.06 | §3 Table 7 | `glass*` (blur executed by KWin rules, `kwinrulesrc`) |
| Motion: 80/120/180/240/350/420 ms | §4 Table 9 | `dur*` |
| Island spring mass 1 · stiffness 420 · damping 28; crossfade 140 ms @ 90 ms | §2.4 Table 5b | `islandSpring*`, `islandCrossfade*` |
| Island states (Now Playing 356×96 r32, Split 132+8+108, Call 300×64, Charging 216, Aegis ID 200×56) | §2.4 Table 5b | `islandStates` |
| Radius tracks height, cap 32 | §2.4 | `islandRadius()` |
| Ink capsule #101216 → #08090C, hairline white 14% | §2.4 | `ink`, `inkDeep`, capsule gradient |
| Accent #3E8BFF | §3 Listing 1 | `accent` |
| Wallpapers (Aurora Ink · Graphite Dune · Neon Coast · Emerald Ridge) | Table 15 | `theme/wallpapers/` |
| Boot splash: mark on true black, hairline progress | chapter 07 | `theme/plymouth/` |

## Table 10 — gesture & shortcut dictionary (M3 · Depth)

The M3 depth surfaces are KWin stock effects pointed at the Aegis anatomy.
They are declared (not assumed) in `etc/xdg/kwinrc` — `[Desktops] Number=4`,
`[Plugins] overviewEnabled=true` — and the dictionary lives here:

| Action | Input | Source |
| --- | --- | --- |
| Mission Control — all windows, workspaces as pages | `Meta+W` | KWin Overview (`overviewEnabled`) |
| Switch workspace | `Meta+Ctrl+←` / `Meta+Ctrl+→` | KWin default |
| Move window to workspace | `Meta+Shift+←` / `Meta+Shift+→` | KWin default |
| Workspace switch, wrap around | 3- or 4-finger horizontal swipe | KWin Wayland touchpad defaults |
| Mission Control | 4-finger swipe up | KWin Wayland touchpad defaults |
| Tiling editor (drag windows onto zones) | `Meta+T`, hold `Shift` while dragging to snap | KWin built-in tiling |
| Calm Mode (DND + Tier C + panel collapse) | Control Center tile | `ControlCenter.qml` → `Activity.calm` |

Shell-side global shortcuts (launcher, control center, lock) keep the M2
contract: they answer while a shell surface holds focus, and via
`org.aegis.Shell` on the session bus for everything else.

## Changelog

### v1.4 (this repo, product decision)
- **Island idle 148×30 → 104×32 px.** The idle capsule now matches the
  iPhone Pro-class footprint (~1.5 cm wide at 1× density). Split and Charging
  track the idle height; radius continues to track height. Tunables:
  `Tokens.islandIdleWidth` / `islandIdleHeight`.

### v1.3 (proposal baseline)
- Everything else unchanged from the 29-page spec.
