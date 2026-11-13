"use strict";

// aegis-shortcuts — T13 D24 (W35): the shell's own global shortcuts.
//
// The KWin stock dictionary (close/minimize/show desktop/overview/tiles/
// desktop switching) is pinned in /etc/xdg/kglobalshortcutsrc with the
// exact action ids taken from the 6.6.0 source. The actions that belong
// to the SHELL (not KWin) cannot ride that file — nothing registers them
// — so this script registers them at session start through the
// registerShortcut global (scripting.cpp:241 injects it into every JS
// script; Script::registerShortcut routes through KGlobalAccel, the same
// daemon every KDE app uses). The bindings therefore land in
// kglobalshortcutsrc (file-assertable) and survive KWin restarts.
//
// The shell actions ride org.aegis.Shell (Util's Q_INVOKABLE DBus
// surface — the same surface the windowwatch script already calls).
//
// Requires kglobalacceld in the session (aegis-session starts it; it
// ships via plasma-workspace Depends: kglobalacceld >= 6.2.90).

registerShortcut("Aegis Launcher", "Toggle the Aegis launcher",
                 "Meta+Space", function () {
    callDBus("org.aegis.Shell", "/org/aegis/Shell", "org.aegis.Shell",
             "toggleLauncher")
})

registerShortcut("Aegis Control Center", "Toggle the Aegis control center",
                 "Meta+S", function () {
    callDBus("org.aegis.Shell", "/org/aegis/Shell", "org.aegis.Shell",
             "toggleControlCenter")
})

// boot marker — the boot gate's journal grep asserts this line exists
print("aegis-shortcuts: loaded")
