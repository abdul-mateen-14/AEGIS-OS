#!/usr/bin/env python3
"""Pre-tag QML guard — catches the whole-document compile failures that boot
tests keep finding one CI hour at a time.

Qt 6 compiles the entire QML document, deferred panes included, so a single
unknown property anywhere fails the load and the app exits before any window
maps. The classes that bit us:

  v0.6.9  SettingsApp  grouped `font { ... }` shares a line with `;` bindings
                        ("Unexpected token ';'")
  v0.6.10 SettingsApp  font.color — QFont has no color sub-property
  v0.6.11 SettingsApp  property declared at Component scope
                        ("Component objects cannot declare new properties")

Checks here are pure text/brace analysis — no Qt needed. If the repo is
checked out where qmllint exists, run it too (see VERIFY.md) and filter for
the same fatal classes; the unqualified-access noise from the Aegis.*
singletons is expected there.
"""
import re
import sys
from pathlib import Path

FILES = [
    "shell/src/qml/FilesApp.qml",
    "shell/src/qml/SettingsApp.qml",
    "shell/src/qml/Tokens.qml",
    "shell/src/qml/Desktop.qml",
    "shell/src/qml/AppWindow.qml",
    "shell/src/qml/ControlCenter.qml",
    "shell/src/qml/Dock.qml",
    "shell/src/qml/Panel.qml",
    "shell/src/qml/Launcher.qml",
    "shell/src/qml/Island.qml",
    "shell/src/qml/Lock.qml",
    "shell/src/qml/Main.qml",
    "shell/src/qml/Notifications.qml",
    "shell/src/qml/Spring.qml",
    "shell/src/qml/GlassPanel.qml",
    "theme/sddm/aegis/Main.qml",
    "shell/src/qml/TrafficLights.qml",
]

FONT_SUBPROPS = {
    "bold", "capitalization", "families", "family", "fixedPitch",
    "hintingPreference", "italic", "kerning", "letterSpacing", "overline",
    "pixelSize", "pointSize", "preferShaping", "strikeOut", "styleName",
    "underline", "weight", "wordSpacing",
}


def strip_strings_comments(src: str) -> str:
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                i += 1
            i += 2
            continue
        if c in "\"'":
            quote = c
            out.append(" ")
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == quote:
                    i += 1
                    break
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def check_file(path: Path) -> list:
    errs = []
    src = path.read_text()
    clean = strip_strings_comments(src)

    # 1. bracket balance
    stack, pairs = [], {")": "(", "]": "[", "}": "{"}
    for ch in clean:
        if ch in "([{":
            stack.append(ch)
        elif ch in ")]}":
            if not stack or stack[-1] != pairs[ch]:
                errs.append(f"unbalanced {ch}")
                break
            stack.pop()
    else:
        if stack:
            errs.append(f"unclosed {stack[-10:]}")

    # 2. duplicate object ids
    ids = re.findall(r"^\s*id:\s*([A-Za-z_][A-Za-z0-9_]*)", src, re.M)
    dups = sorted({i for i in ids if ids.count(i) > 1})
    if dups:
        errs.append(f"duplicate ids: {dups}")

    # 3. forbidden tokens — "undefined" allowed only as comparisons
    # (pd.percent !== undefined) and the anchor-clear idiom (: undefined /
    # ternary ? undefined :), never as a stray identifier
    clean2 = clean
    for ok_form in ["!== undefined", "=== undefined", "? undefined :",
                    ": undefined :", '!== "undefined"',
                    '=== "undefined"']:
        clean2 = clean2.replace(ok_form, "OK_FORM")
    for bad in ["TODO", "XXX", "undefined", "fs.existsSync",
                "parent.parent.parent"]:
        if bad in clean2:
            errs.append(f"forbidden token: {bad}")

    # 4. invalid font sub-properties (the v0.6.10 killer)
    for m in re.finditer(r"\bfont\.([A-Za-z_]\w*)", clean):
        if m.group(1) not in FONT_SUBPROPS:
            line = clean[:m.start()].count("\n") + 1
            errs.append(f"invalid grouped property font.{m.group(1)} "
                        f"(line {line})")

    # 5. grouped property sharing a line with ';' bindings (v0.6.9 killer)
    for m in re.finditer(r"\b[a-z]\w*\s*\{[^{}]*\}\s*;", clean):
        line = clean[:m.start()].count("\n") + 1
        errs.append(f"grouped property then ';' on one line (line {line})")

    # 6. property declared directly inside a Component (v0.6.11 killer)
    lines = clean.split("\n")
    comp_stack = []
    for n, line in enumerate(lines, 1):
        s = line.strip()
        is_comp = bool(re.match(r"^Component\s*\{", s))
        if re.match(r"^(default |readonly )?property\b", s):
            if comp_stack and comp_stack[-1]:
                errs.append(f"property at Component scope (line {n})")
        for ch in s:
            if ch == "{":
                comp_stack.append(is_comp)
            elif ch == "}":
                if comp_stack:
                    comp_stack.pop()

    return errs


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    fail = False
    for rel in FILES:
        p = root / rel
        if not p.exists():
            print(f"MISSING: {rel}")
            fail = True
            continue
        errs = check_file(p)
        for e in errs:
            print(f"FAIL {rel}: {e}")
        if not errs:
            print(f"PASS: {rel}")
        fail = fail or bool(errs)
    if fail:
        print("qml-guard: FAILURES — fix before tagging")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
