# Rust migration — the honest analysis (2026-11-19)

## The ask

"Replace the codebase with Rust so it can be faster and consume less RAM."

## What the evidence says

**The language is not the bottleneck.** The desktop shell is Qt6/QML
(one C++ binary + ~30 QML files). Rendering cost in CI is dominated by
llvmpipe (software rasterization) — the same frames would render an
order of magnitude faster on any real GPU, in any language. A Rust
shell renders with the same compositor (KWin), the same blur protocol
(org_kde_kwin_blur), the same wayland surfaces. The pixel pipeline
does not change.

**Where the RAM actually goes** (to be measured precisely — the
`===PROCS===` diagnostic was fixed in the same commit as this doc
because the old form head-cut the interesting rows; the next boot run
produces the RSS-sorted top-18):

1. **The Electron apps are the big fish.** os-private-chat and CoreX
   Terminal are Electron/Chromium processes: hundreds of MB *each*
   for what they do (a webview shell around hosted web pages, a
   terminal). Any native replacement — Rust or C++ — wins 10-20× on
   those two alone. No change to the shell buys that.
2. **The QML shell is one process** (~100-150 MB class, typical for
   Qt Quick + a compositor-backed scene). A Rust shell (iced/Slint/
   smithay-client-toolkit) lands in the 30-60 MB class — a real win,
   but a small absolute one next to Electron.
3. **Per-app Qt instances** (files, editor, monitor, music…) each
   carry their own QML engine. Consolidation (one app host process)
   saves more than any language swap.

## Why a big-bang rewrite is the wrong move

- **Regression surface.** The W-series history in `docs/TASKS.md` is a
  few hundred fixed, capture-asserted bugs: the blur clip regions, the
  dead-clicks class, the popover self-kill gate, the boot-story chain.
  A rewrite re-rolls every one of them with no harness coverage for
  the new implementation.
- **The UI is declarative QML** — springs, states, the token system.
  Rust GUI (Slint closest to QML) means re-authoring every surface by
  hand, then re-tuning every animation constant in `Tokens.qml`.
- **KWin integration is protocol + scripting.** The windowwatch script
  is KWin JS either way; the blur channel is a wayland protocol either
  way. Rust does not simplify that layer.

## The staged plan (recommended)

| Stage | Scope | Expected win | Risk |
| --- | --- | --- | --- |
| 0 | **Measure** — the fixed `===PROCS===` diagnostic now dumps RSS top-18 + MemAvailable every boot run | the decision baseline | none |
| 1 | **Replace the Electron apps** with native Rust (chat client, terminal via portable-pty) or thin Qt equivalents | ~300-500 MB on a typical session | medium (product UX change) |
| 2 | **Consolidate the per-app QML engines** into one app-host process | ~100-200 MB | medium |
| 3 | **Port leaf daemons to Rust** (session/governor/activity/updates — small, interface-clean, individually testable) | ~10-30 MB, faster startup | low |
| 4 | **Only if 0-3's numbers say so**: a Rust shell (Slint) behind the same token system, surface by surface, behind a feature flag | ~50-100 MB | high, last |

Stage 4 is deliberately conditional: after stages 1-3 the shell is a
minority of the stack's memory, and the rewrite cost is fixed while
the shell's feature velocity is not.

## Decision rule

Proceed in stage order, stopping when the measured marginal win drops
below the maintenance cost. Every stage ships behind the existing
boot-test suite; nothing lands that the captures cannot see.
