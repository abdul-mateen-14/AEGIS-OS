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

// ── W82 — the completeness dictionary ───────────────────────────────
// App keys and the capture suite ride the same org.aegis.Shell surface
// as the W35 pair. Every binding below is file-assertable (the shortcut
// lands in the user's kglobalshortcutsrc once kglobalacceld has seen
// it) and probe-able (the boot harness injects the keys).

// Meta+E — Files (the Windows Explorer reflex)
registerShortcut("Aegis Files", "Open Aegis Files",
                 "Meta+E", function () {
    callDBus("org.aegis.Shell", "/org/aegis/Shell", "org.aegis.Shell",
             "launch", "aegis-files")
})

// Ctrl+Alt+T — Terminal (the Ubuntu reflex)
registerShortcut("Aegis Terminal", "Open Terminal",
                 "Ctrl+Alt+T", function () {
    callDBus("org.aegis.Shell", "/org/aegis/Shell", "org.aegis.Shell",
             "launch", "konsole")
})

// Meta+L — lock the session (the macOS reflex)
registerShortcut("Aegis Lock", "Lock the session",
                 "Meta+L", function () {
    callDBus("org.aegis.Shell", "/org/aegis/Shell", "org.aegis.Shell",
             "lock")
})

// Meta+N — the Notification Center (the calendar popover's history)
registerShortcut("Aegis Notification Center", "Toggle the notification center",
                 "Meta+N", function () {
    callDBus("org.aegis.Shell", "/org/aegis/Shell", "org.aegis.Shell",
             "toggleCalendar")
})

// Print — full-screen capture, straight to ~/Pictures/Screenshots
registerShortcut("Aegis Screenshot (Full Screen)",
                 "Capture the full screen to Pictures/Screenshots",
                 "Print", function () {
    callDBus("org.aegis.Shell", "/org/aegis/Shell", "org.aegis.Shell",
             "takeScreenshot", "full")
})

// Shift+Print / Meta+Shift+S — region capture (the Windows snip reflex)
registerShortcut("Aegis Screenshot (Region)",
                 "Capture a region to Pictures/Screenshots",
                 "Shift+Print", function () {
    callDBus("org.aegis.Shell", "/org/aegis/Shell", "org.aegis.Shell",
             "takeScreenshot", "region")
})

registerShortcut("Aegis Screenshot (Snip)",
                 "Capture a region to Pictures/Screenshots",
                 "Meta+Shift+S", function () {
    callDBus("org.aegis.Shell", "/org/aegis/Shell", "org.aegis.Shell",
             "takeScreenshot", "region")
})

// Alt+Print — capture the active window
registerShortcut("Aegis Screenshot (Window)",
                 "Capture the active window to Pictures/Screenshots",
                 "Alt+Print", function () {
    callDBus("org.aegis.Shell", "/org/aegis/Shell", "org.aegis.Shell",
             "takeScreenshot", "window")
})

// W82 quick tiling — Meta+Left / Meta+Right via workspace's own slots.
// The kglobalshortcutsrc pin ("Window Quick Tile Left") was IGNORED by
// kglobalacceld on KWin 6.6 (bt92r2: Alt+Tab pin fired, tile pin didn't,
// both-halves-differ pixels = the window never moved), while every
// registerShortcut key in THIS script demonstrably fires (Print, Meta+N,
// Meta+E — all green in bt92r2). Same proven channel, slot names per
// develop.kde.org/docs/plasma/kwin/api.
registerShortcut("Aegis Quick Tile Left",
                 "Quick Tile the Active Window to the Left",
                 "Meta+Left", function () {
    workspace.slotWindowQuickTileLeft();
})

registerShortcut("Aegis Quick Tile Right",
                 "Quick Tile the Active Window to the Right",
                 "Meta+Right", function () {
    workspace.slotWindowQuickTileRight();
})

print("aegis-shortcuts: W82 keys registered (files/terminal/lock/center/screenshots/tile)")
