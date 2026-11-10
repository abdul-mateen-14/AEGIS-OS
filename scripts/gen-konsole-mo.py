#!/usr/bin/env python3
"""W11 — the Terminal caption, fixed at the source.

Qt's Wayland QPA composes window titles as
    title + " — " + QGuiApplication::applicationDisplayName
unless the title already ENDS with the display name
(qtbase qplatformwindow.cpp: QPlatformWindow::formatWindowTitle).
Konsole's display name comes from KAboutData::setApplicationData, i.e. from
i18nc("@title", "Konsole") — a translatable string in the "konsole" catalog.

So we ship a konsole.mo that translates exactly that one string to
"Aegis Terminal": the profile's tab title ("Aegis Terminal") then ENDS WITH
the display name, the suffix is never composed, and the window title reads
plainly "Aegis Terminal". The About dialog and other self-references also
read the rebranded name.

KCatalog lookup paths (KF6): $XDG_DATA_DIRS/locale/<lang>/LC_MESSAGES/
konsole.mo with <lang> from kdeglobals [Locale] Language, falling back to
the session locale. We install en_US, en and en_GB so any English rung
resolves, and set the session LANGUAGE explicitly (see aegis-session).
"""
import os
import polib

ROOT = os.path.join(os.path.dirname(__file__), "..")

PO = polib.POFile()
PO.metadata = {
    "Project-Id-Version": "konsole (Aegis OS caption override)",
    "Content-Type": "text/plain; charset=UTF-8",
    "Content-Transfer-Encoding": "8bit",
}
PO.append(polib.POEntry(
    msgctxt="@title", msgid="Konsole", msgstr="Aegis Terminal"))
PO.append(polib.POEntry(
    msgctxt="@title", msgid="Terminal emulator", msgstr="Aegis OS Terminal"))

LOCALES = ("en_US", "en", "en_GB")
for lang in LOCALES:
    d = os.path.join(ROOT, "debian-live/config/includes.chroot/usr/share/"
                          f"locale/{lang}/LC_MESSAGES")
    os.makedirs(d, exist_ok=True)
    PO.save(os.path.join(d, "konsole.mo"))
    print("wrote", lang, "konsole.mo")
