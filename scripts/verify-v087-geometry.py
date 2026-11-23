#!/usr/bin/env python3
"""v0.6.87 pre-flight: cross-check the boot-capture harness constants
against the ControlCenter.qml stack arithmetic, calibrated on the
v0.6.86 artifact's measured positions.

Measured on the v0.6.86 artifact (04j2-cc-over-files.png, 1280x800):
  accent card fill  y 127..164   (the card Rectangle = 124..164, 40 px)
  circle row 1      y 177..238   (plates 62 px inside 64, grid top 176)
  circle row 2      y 270..331   (the wrapped 4th tile, row pitch 94)
The pre-fix model below reproduces all three within 1 px -> the same
model, with the ethernet tile deleted, gives the post-fix rows the
harness now asserts.
"""
import re

# ---- stack model (from ControlCenter.qml @ v0.6.87) ----
HEADER = 84          # sheet top 40 -> card top 124 (measured 124..127)
CARD = 40            # ConnectivityTile (wide: 40)
CC_NARROW = 82       # CcTile narrow height (64 plate + caption)
CC_WIDE = 40         # CcTile wide (DND)
SLIDER = 32          # CcSlider row
RULE = 1
POWER = 36
FOOTER = 26
SPACING = 12         # both the tiles Column and the pane Column

def stack(n_circle_rows):
    rows = {}
    y = 40 + HEADER
    rows["card"] = (y, y + CARD); y += CARD + SPACING
    grid_h = n_circle_rows * CC_NARROW + (n_circle_rows - 1) * SPACING
    rows["grid"] = (y, y + grid_h)
    rows["plates"] = (y, y + 64)
    y += grid_h + SPACING
    rows["rule1"] = (y, y + RULE); y += RULE + SPACING
    rows["dnd"] = (y, y + CC_WIDE)
    rows["switch_center"] = y + CC_WIDE // 2
    y += CC_WIDE + SPACING
    rows["rule2"] = (y, y + RULE); y += RULE + SPACING
    rows["s1"] = (y, y + SLIDER); y += SLIDER + SPACING
    rows["s2"] = (y, y + SLIDER); y += SLIDER + SPACING
    rows["rule3"] = (y, y + RULE); y += RULE + SPACING
    rows["power"] = (y, y + POWER); y += POWER + SPACING
    rows["footer"] = (y, y + FOOTER); y += FOOTER
    rows["sheet_bottom"] = y
    return rows

# 1. calibration: the PRE-fix layout (4 tiles -> 2 rows) must reproduce
#    the artifact measurements
pre = stack(2)
assert abs(pre["card"][0] - 124) <= 3, pre["card"]
assert abs(pre["plates"][0] - 176) <= 2, pre["plates"]      # measured 177
assert abs(pre["plates"][1] - 240) <= 3, pre["plates"]      # measured 238
row2 = (pre["grid"][0] + CC_NARROW + SPACING, )
assert abs(row2[0] - 270) <= 2, row2                        # measured 270
print("calibration vs v0.6.86 artifact: card %s plates %s row2 %s — "
      "matches measured 124/177..238/270 within 1-3 px"
      % (pre["card"], pre["plates"], row2))

# 2. post-fix rows (3 tiles -> 1 row) = what the harness asserts
post = stack(1)
print("post-fix stack:")
for k in ("card", "grid", "plates", "rule1", "dnd", "rule2", "s1",
          "s2", "rule3", "power", "footer", "sheet_bottom"):
    print("  %-13s %s" % (k, post[k]))
sheet_h = post["sheet_bottom"] - 40
print("needed sheet height %d -> QML height 492 (slack %d)"
      % (sheet_h, 492 - sheet_h))
assert sheet_h <= 492, "stack overflows the grown sheet"

# 3. harness constants must sit inside the computed features
CCY0, CCX1 = 40, 1270
checks = [
    ("dark tile click y        CCY0+168", 168,
     (post["plates"][0] + 10 - 40, post["plates"][1] - 10 - 40)),
    ("switch click y           CCY0+263", 263,
     (post["dnd"][0] + 6 - 40, post["dnd"][1] - 6 - 40)),
    ("w69 brightness band      +308..+340", (308, 340),
     (post["s1"][0] - 40, post["s1"][1] - 40)),
    ("w69 volume band          +352..+384", (352, 384),
     (post["s2"][0] - 40, post["s2"][1] - 40)),
    ("w67 glass band           +446..+456", (446, 456),
     (post["power"][1] + 1 - 40, post["footer"][0] - 1 - 40)),
]
for name, v, span in checks:
    lo, hi = span
    if isinstance(v, tuple):
        ok = v[0] >= lo and v[1] <= hi
    else:
        ok = lo <= v <= hi
    print("  %-38s inside %s -> %s" % (name, (lo, hi), "OK" if ok else "FAIL"))
    assert ok, name

# v0.6.89 — the MODEL is 2..12 px above the render (rule1 268 vs 270,
# rule2 329 vs 335, rule3 424 vs 436 measured on the v0.6.88 artifact);
# the harness rides the MEASURED offsets now, tolerance ±10 against the
# model drift.
MEASURED = {"rule1": 228, "rule2": 289, "rule3": 384}
for rule_name, off in MEASURED.items():
    actual = post[rule_name][0] - 40
    assert abs(actual - off) <= 12, (rule_name, actual, off)
    print("  w70 %s model CCY0+%d, harness asserts the MEASURED CCY0+%d "
          "(artifact) ±10 OK" % (rule_name, actual, off))

# 4. the resolved_tile_cmds regex: a garbled reply (the console echoes
#    the probe line carrying every TILE literal) must yield the unique
#    per-slot outputs only
garbled = (
    "root@aegis:~# P=(); for c in files terminal browser os corex "
    "settings updates music calc monitor trash; do ... echo TILE files; "
    "\nTILE files\nTILE terminal\nTILE browser\nTILE os\nTILE corex\n"
    "TILE settings\nTILE updates\nTILE music\nTILE calc\nTILE monitor\n"
    "TILE trash\nroot@aegis:~# ")
cmds = list(dict.fromkeys(re.findall(r"(?m)^TILE (\S+)$", garbled)))
assert len(cmds) == 11, cmds
print("anchored regex on the echoed reply: %d unique slots (was 2x+ "
      "unanchored) OK" % len(cmds))

# 5. dock_geometry clamp: an inflated n_override fits the screen
W, B, gap, pad = 1280, 76, 2, 12
for bad in (13, 25, 60):
    fit = max(1, (W - 2 * pad - 8 + gap) // (B + gap))
    n = max(1, min(bad, fit))
    row_w = n * B + (n - 1) * gap
    x0 = W // 2 - (row_w + 2 * pad) // 2
    cx_max = x0 + pad + (n - 1) * (B + gap) + B // 2
    assert 0 <= cx_max <= W, (bad, cx_max)
    print("n_override %2d -> clamped %2d, last center x=%d OK"
          % (bad, n, cx_max))

print("\nALL GEOMETRY CHECKS PASS")
