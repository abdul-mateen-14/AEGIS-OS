#!/usr/bin/env python3
"""W62 lint — the bold budget (v0.6.62 instructions §2 W62 probe).

Counts bold usages (`bold: true` and `font.bold:` — both block and dot
form, DemiBold excluded) per shell QML file against the proposal's
allow-list budgets and reds the build on a break:
  SettingsApp.qml <= 8   (the seven 8 px micro-caps badges + slack 1)
  FilesApp.qml    <= 1
  every other shell QML <= 1 (Panel brand / dock tooltip / titles)
"""
import os
import re
import sys

QML_DIR = "/home/z/my-project/work/AEGIS-OS/shell/src/qml"
BUDGETS = {"SettingsApp.qml": 8, "FilesApp.qml": 1}
DEFAULT = 1
BOLD = re.compile(r"(?<!Demi)bold:\s*true|(?<!Demi)font\.bold:")

failed = False
for name in sorted(os.listdir(QML_DIR)):
    if not name.endswith(".qml"):
        continue
    n = 0
    with open(os.path.join(QML_DIR, name)) as f:
        for i, line in enumerate(f, 1):
            if BOLD.search(line):
                n += 1
                print(f"  {name}:{i}: {line.strip()[:80]}")
    budget = BUDGETS.get(name, DEFAULT)
    ok = n <= budget
    failed |= not ok
    print(f"{name}: {n}/{budget} {'OK' if ok else 'OVER BUDGET'}")

# W66 lint — the effects pane's row model is EXACTLY the proposal's six
SIX = ["dockMagnify", "dockBounce", "windowSprings", "liveBlur",
       "wallpaperParallax", "islandMorph"]
settings = open(os.path.join(QML_DIR, "SettingsApp.qml")).read()
row_keys = re.findall(r'key:\s*"([A-Za-z]+)"', settings)
pane_keys = [k for k in row_keys
             if k in SIX or k in ("blurLive", "blurAny", "motionSpring",
                                  "shadowsHalf")]
if pane_keys == SIX:
    print(f"effects row model: exactly the six proposal keys OK")
else:
    print(f"effects row model: {pane_keys} != {SIX} — OVER/UNDER the "
          "proposal's six")
    failed = True

sys.exit(1 if failed else 0)
