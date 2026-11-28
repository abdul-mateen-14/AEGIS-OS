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
// T13 D20 (W27) — the payload grew: {count, anyFull, ids, allIds,
// active} as ONE JSON string. allIds carries EVERY managed window's
// resourceClass including MINIMIZED ones (the dock's running dots and
// activateOrLaunch must see minimized apps); ids stays the visible-only
// list; active is the resourceClass of workspace.activeWindow (the
// harness's restore assert reads it). The count/anyFull island
// predicate is untouched.
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

function isShellClass(w) {
    // The shell's OWN layer surfaces (desktop, panel, island, dock) pass
    // normalWindow in KWin 6.6 scripting — the v0.6.36 boot run proved
    // it: with the script loaded the island hid at the IDLE home because
    // the count never dropped below the four shell surfaces. The shell
    // binary is never an app: exclude its resourceClass outright.
    return String(w.resourceClass || "") === "aegis-shell"
}

function isTrackable(w) {
    return w.normalWindow && !w.minimized && !w.hidden
        && !isShellClass(w)
}

// D20 — the activation matcher: everything isTrackable accepts, plus
// minimized windows (a dock click must be able to restore them).
function isMatchable(w) {
    return w.normalWindow && !isShellClass(w)
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
    var allIds = []
    var wins = workspace.stackingOrder
    for (var i = 0; i < wins.length; ++i) {
        var w = wins[i]
        if (dying.indexOf(w) >= 0)
            continue
        if (!isMatchable(w))
            continue
        allIds.push(String(w.resourceClass || ""))
        if (!isTrackable(w))
            continue
        if (deskOk && !onDesktop(w, desk))
            continue
        ++count
        ids.push(String(w.resourceClass || ""))
        if (isFull(w))
            anyFull = true
    }
    var active = ""
    try {
        if (workspace.activeWindow && workspace.activeWindow.normalWindow
                && !isShellClass(workspace.activeWindow))
            active = String(workspace.activeWindow.resourceClass || "")
    } catch (e) {}
    callDBus("org.aegis.Shell", "/org/aegis/Shell", "org.aegis.Shell",
             "windowListChanged",
             JSON.stringify({count: count, anyFull: anyFull, ids: ids,
                             allIds: allIds, active: active}))
}

// D20 (W27) — activateOrLaunch's executor. The kwinrc transport is
// GONE: KConfigWatcher only fires on the org.kde.kconfig.notify DBus
// signal that KConfig-based writers emit (kconfigwatcher.cpp verified),
// QSettings never sends it, and even the shell's reloadConfig reparse
// left this poll reading the load-time ActivateSeq (the v0.6.54 run).
// D30b — the request now rides the PROVEN channel in reverse: the
// script CALLS the shell (callDBus pendingActivate — the exact reverse
// of the windowListChanged push, same service, same bus, string
// marshalling proven by every recount) and the shell holds the request
// for 4 s; the script confirms with activateDone.
//
// D28 — the v0.6.51 boot run caught the activation RACE: the dock click
// itself clears the active window (the payload read active:"" right
// after the click), so a one-shot activation could be undone by the
// click's own focus processing. The request is therefore kept PENDING
// for ~1.2 s and re-applied on every tick while the active window's
// class does not match — self-healing, and a foreign focus change AFTER
// the window settles is respected (the deadline ends the re-apply).
var pendingClass = ""
var pendingDeadline = 0

function activateByClass(resourceClass) {
    if (!resourceClass)
        return false
    var wins = workspace.stackingOrder
    for (var i = 0; i < wins.length; ++i) {
        var w = wins[i]
        if (String(w.resourceClass || "") !== resourceClass)
            continue
        if (!isMatchable(w))
            continue
        // window.h:397 — minimized is READ/WRITE on the script wrapper;
        // workspace.activeWindow is WRITE (workspace_wrapper.h:34).
        try { w.minimized = false } catch (e) {}
        try { workspace.activeWindow = w } catch (e) {}
        return true
    }
    return false
}

function currentActiveClass() {
    try {
        if (workspace.activeWindow && workspace.activeWindow.normalWindow
                && !isShellClass(workspace.activeWindow))
            return String(workspace.activeWindow.resourceClass || "")
    } catch (e) {}
    return ""
}

var activateTimer = new QTimer()
activateTimer.interval = 150
activateTimer.singleShot = false
activateTimer.timeout.connect(function () {
    if (pendingClass) {
        if (currentActiveClass() === pendingClass) {
            // active — either our activation landed or the user beat us
            // to it; confirm either way so the shell clears the request
            print("aegis-windowwatch: activation done: " + pendingClass)
            callDBus("org.aegis.Shell", "/org/aegis/Shell",
                     "org.aegis.Shell", "activateDone", pendingClass)
            pendingClass = ""
            return
        }
        if (Date.now() < pendingDeadline) {
            // D28 self-heal — re-apply every tick; a foreign focus change
            // AFTER the settle wins (the deadline ends the re-apply)
            var ok = activateByClass(pendingClass)
            if (!ok)
                print("aegis-windowwatch: no matchable window for "
                      + pendingClass)
            recount()
            return
        }
        print("aegis-windowwatch: activation deadline passed: "
              + pendingClass)
        pendingClass = ""
        return
    }
    // no pending request — pull the shell for one (the callback is the
    // ONLY way callDBus returns a value; a failed call leaves the
    // callback uncalled and the poll just continues)
    callDBus("org.aegis.Shell", "/org/aegis/Shell",
             "org.aegis.Shell", "pendingActivate", function (cls) {
        var c = String(cls || "")
        if (c) {
            print("aegis-windowwatch: activation requested: " + c)
            pendingClass = c
            pendingDeadline = Date.now() + 1200
        }
    })
})
activateTimer.start()
print("aegis-windowwatch: activate poll armed")

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
