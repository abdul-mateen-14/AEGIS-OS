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
    return w.normalWindow && !w.minimized && !w.hidden
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
    var desk = workspace.activeDesktop
    var count = 0
    var anyFull = false
    var ids = []
    var wins = workspace.stackingOrder
    for (var i = 0; i < wins.length; ++i) {
        var w = wins[i]
        if (dying.indexOf(w) >= 0)
            continue
        if (!isTrackable(w) || !onDesktop(w, desk))
            continue
        ++count
        ids.push(String(w.resourceClass || ""))
        if (isFull(w))
            anyFull = true
    }
    callDBus("org.aegis.Shell", "/", "org.aegis.Shell",
             "windowListChanged", count, anyFull, ids.join(" "))
}

// windowRemoved fires while the window can still sit in stackingOrder —
// remember it for the synchronous recount that follows, then clear.
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
