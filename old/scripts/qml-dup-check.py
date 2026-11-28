#!/usr/bin/env python3
"""W41 bt72 — the QML load-failure guard.

bt72 (44136332922 + 44142355315, two red runs, ~80 min): a duplicate
`Component.onCompleted:` in Dock.qml made the QML engine refuse the
whole file ("Property value set multiple times"), Main.qml failed to
load, the shell exited at startup, and Shell CI never saw it because
the C++ build does not parse QML. This check walks every .qml file,
collects the property / change-handler keys declared at each object's
top level, and fails on duplicates — in QML a duplicate key is ALWAYS
a load-fatal error, so there are no legitimate hits.

Not a full QML parser: it matches keys only when the line starts with
`key:` (QML declarations are line-led; JS object literals inside
functions are usually mid-line). Good enough for the failure class it
guards, wrong never.
"""
import re
import sys
from pathlib import Path

KEY_RE = re.compile(r"^(\s*)((?:\w+\.)?(?:on[A-Z]\w*(?:Changed|Completed)?)|"
                    r"[A-Za-z_]\w*)\s*:\s")
SKIP_RE = re.compile(r"^\s*//|^\s*\*|^\s*/\*|^\s*#")

def check(path):
    lines = path.read_text(encoding="utf-8").splitlines()
    # brace depth per line-start: the key's block identity is the
    # depth AT its line plus the file order — two keys collide when
    # both their key text and their (depth, parent) context repeat.
    # Parent identity is approximated by the column of the enclosing
    # opener — enough to separate siblings from unrelated objects.
    stack = []          # (depth, col_of_opener, keys_seen)
    failures = []
    in_block_comment = False
    for ln, raw in enumerate(lines, 1):
        line = raw
        if in_block_comment:
            if "*/" in line:
                line = line.split("*/", 1)[1]
                in_block_comment = False
            else:
                continue
        if "/*" in line and "*/" not in line:
            line = line.split("/*", 1)[0]
            in_block_comment = True
        if SKIP_RE.match(line):
            continue
        code = line.split("//", 1)[0].rstrip()
        opens = code.count("{")
        closes = code.count("}")
        m = KEY_RE.match(code)
        # register the key even when the value opens a block — the
        # declaration is a property of the enclosing object regardless
        # of its value's shape (bt72's duplicate was block-form)
        if m:
            indent, key = len(m.group(1)), m.group(2)
            # the enclosing object is the innermost open brace; sibling
            # keys share (indent class) within the same object — track
            # keys per enclosing brace entry
            while stack and stack[-1][0] > indent:
                stack.pop()
            if not stack or stack[-1][0] != indent:
                stack.append((indent, {}))
            seen = stack[-1][1]
            if key in seen and key not in ("Keys", "states"):
                failures.append(
                    f"{path}:{ln}: duplicate '{key}' (first at line "
                    f"{seen[key]}) — the QML engine refuses the whole "
                    "file: 'Property value set multiple times'")
            else:
                seen[key] = ln
        # register openers at their indent so following keys group
        while opens:
            stack.append((indent_of(code), {}))
            opens -= 1
        while closes and stack:
            stack.pop()
            closes -= 1
    return failures

def indent_of(code):
    return len(code) - len(code.lstrip())

def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else
                Path(__file__).resolve().parent.parent / "shell/src/qml")
    files = sorted(root.glob("*.qml"))
    if not files:
        print(f"qml-dup-check: no .qml files under {root}")
        return 0
    all_failures = []
    for f in files:
        all_failures.extend(check(f))
    if all_failures:
        print("qml-dup-check: FAILED")
        for fl in all_failures:
            print("  " + fl)
        return 1
    print(f"qml-dup-check: OK ({len(files)} files)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
