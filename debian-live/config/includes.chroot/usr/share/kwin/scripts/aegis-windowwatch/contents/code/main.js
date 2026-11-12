// aegis-windowwatch — T12 W20: real window tracking for the Aegis shell.
//
// Connects the three Workspace window signals, counts the trackable
// normal windows on the ACTIVE workspace, and pushes
//   windowListChanged(count, anyFull, idsJoined)
// to org.aegis.Shell (Util's DBus surface). idsJoined is the
// space-joined resourceClass list — callDBus marshals JS arrays as a
// VARIANT list (DBus "av") which will NOT demarshal into a QStringList
// slot, so the ids travel as one string.
//
// Trackable: normalWindow, not minimized, not hidden. The shell's own
// surfaces (panel/dock/island/desktop) are layer windows and never
// normalWindow, so they never count.
// anyFull: fullscreen OR maximized. window.maximized exists on KWin
// 6.1+; it is read behind a guard so a missing property degrades to
// fullscreen-only instead of throwing.

function onDesktop(w, desk) {
    return w.onAllDesktops || !w.desktops || w.desktops.length === 0
        || w.desktops.indexOf(desk) >= 0
}

function isTrackable(w) {
    // The shell's OWN layer surfaces (desktop, panel, island, dock) pass
    // normalWindow in KWin 6.6 scripting — the v0.6.36 boot run proved
    // it: with the script loaded the island hid at the IDLE home because
    // the count never dropped below the four shell surfaces. The shell
    // binary is never an app: exclude its resourceClass outright.
    return w.normalWindow && !w.minimized && !w.hidden
        && String(w.resourceClass || "") !== "aegis-shell"
}

function isFull(w) {
    if (w.fullScreen)
        return true
    try {
        if (w.maximized)
            return true
    } catch (e) {}
    return false
}

function recount() {
    // T13 — workspace.activeDesktop is NOT guaranteed to exist in the 6.6
    // scripting API: when it is undefined, onDesktop() fails every window
    // that sits on a specific desktop (indexOf(undefined) = -1) and the
    // count stayed 0 FOREVER — the v0.6.39 boot run shipped exactly that
    // (the payload arrived, the count never moved off 0). When the
    // active desktop is unknowable, count ALL trackable windows — the
    // honest approximation of the ruling's predicate.
    var desk = null
    try { desk = workspace.activeDesktop } catch (e) {}
    var deskOk = (desk !== null && desk !== undefined)
    var count = 0
    var anyFull = false
    var ids = []
    var wins = workspace.stackingOrder
    for (var i = 0; i < wins.length; ++i) {
        var w = wins[i]
        if (dying.indexOf(w) >= 0)
            continue
        if (!isTrackable(w))
            continue
        if (deskOk && !onDesktop(w, desk))
            continue
        ++count
        ids.push(String(w.resourceClass || ""))
        if (isFull(w))
            anyFull = true
    }
    callDBus("org.aegis.Shell", "/org/aegis/Shell", "org.aegis.Shell",
             "windowListChanged",
             JSON.stringify({count: count, anyFull: anyFull, ids: ids}))
}

// windowRemoved fires while the window can still sit in stackingOrder —
// remember it for the synchronous recount that follows, then clear.
// boot marker — the boot gate's journal grep asserts this line exists
// (isScriptLoaded proves the registration, this proves the code ran)
print("aegis-windowwatch: loaded")

var dying = []
workspace.windowRemoved.connect(function (w) {
    dying.push(w)
    recount()
    dying.splice(0, dying.length)
})
workspace.windowAdded.connect(recount)
workspace.windowActivated.connect(recount)

// boot-time snapshot: pushes zero on an empty session; if the shell is
// not on the bus yet the call fails silently and the next window event
// re-pushes (the shell reads the count lazily otherwise).
recount()
