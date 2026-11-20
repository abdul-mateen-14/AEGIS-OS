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
| 1 | **Replace the Electron apps** — ✅ DONE as of v0.6.79, with the honest twist below: both "apps" turned out to be ~40-line Electron *webview shells* around hosted PWAs, not port-able clients | 560 MB disk off the ISO, one Chromium runtime instead of three, in-use RAM bounded by the shared browser | low (no product logic changed) |
| 2 | **Consolidate the per-app QML engines** into one app-host process | ~100-200 MB | medium |
| 3 | **Port leaf daemons to Rust** (session/governor/activity/updates — small, interface-clean, individually testable) | ~10-30 MB, faster startup | low |
| 4 | **Only if 0-3's numbers say so**: a Rust shell (Slint) behind the same token system, surface by surface, behind a feature flag | ~50-100 MB | high, last |

Stage 4 is deliberately conditional: after stages 1-3 the shell is a
minority of the stack's memory, and the rewrite cost is fixed while
the shell's feature velocity is not.

## Stage 1 — what the packages actually were (v0.6.79 forensics)

The stage-1 row originally said "replace with native Rust (chat client,
terminal via portable-pty)". Downloading and unpacking both debs
killed that idea with evidence, and replaced it with something better:

- **os-private-chat 2.8.33** (280 MB installed): the app.asar holds
  FOUR files — main.js is 3.9 KB and does nothing but open
  `https://os-cloudflare.pages.dev/app` in a sandboxed BrowserWindow
  (plus a permission allowlist, a Save-As download hook, and
  external-link routing). Its own header says it: "this package only
  provides a dedicated window around the live PWA … All chat logic,
  crypto and UI stay server/PWA-side — no duplication."
- **corex-terminal 1.1.0** (280 MB installed): the app.asar holds
  THREE files — main.js is 7 KB loading `https://corex-2hl.pages.dev`
  (charts/order flow/alerts/cloud sync = the hosted site), plus window-
  state persistence and splash suppression in injected CSS.

There is no client protocol to port — the products ARE web pages. A
"native Rust chat client" or "Rust terminal" would not be a
replacement, it would be a different product. The measurable waste was
never the glue (4-11 KB); it was **two private 280 MB Chromium bundles
riding next to the image's existing Chromium rebrand**.

**Shipped instead (v0.6.79):** `/usr/bin/aegis-webshell <app> <url>` —
the shipped aegis-browser-stable in `--app` mode with a per-app
`--user-data-dir` profile (logins, permission grants, window geometry
persist per PWA), through the same W25 guard every Chromium launch
uses. Both Electron debs left the ISO (app-deb-urls.txt, URLs kept for
revert); the dock slots keep their names, icons and positions so the
geometric click map is untouched. Ledger: 560 MB disk off the squashfs,
the patch surface drops from three Chromium forks to one, and a
session running both PWAs costs one browser process tree + two
renderers instead of two full Electron trees. What the stage did NOT
buy: idle RAM (the apps never ran at idle — bt91's ===PROCS=== baseline
already showed zero Electron processes; the real idle fish are
aegis-shell 460 MB + kwin 333 MB + aegis-apps 224 MB, which is exactly
stage 2's target).

## Decision rule

Proceed in stage order, stopping when the measured marginal win drops
below the maintenance cost. Every stage ships behind the existing
boot-test suite; nothing lands that the captures cannot see.
