import QtQuick

// Shell root — eight surfaces, no visual content of its own.
// main.cpp finds each window by objectName, attaches it to the layer-shell
// protocol with its surface configuration, and shows the four persistent
// ones. The M2 overlays (Control Center, Launcher, Notifications, Lock)
// keep visible: false here and drive their own visibility off Util state —
// their layer surface is created on first show with the attached config.
// Windows must be visible: false initially so the attach happens before
// the platform surface exists.
QtObject {
    objectName: "aegisMain"

    property Desktop desktopSurface: Desktop { }
    property Panel panelSurface: Panel { }
    property Island islandSurface: Island { }
    property Dock dockSurface: Dock { }

    // M2 · Surfaces
    property ControlCenter controlCenterSurface: ControlCenter { }
    property CalendarPopover calendarSurface: CalendarPopover { }
    property Launcher launcherSurface: Launcher { }
    property Notifications notificationsSurface: Notifications { }
    property Lock lockSurface: Lock { }
}
