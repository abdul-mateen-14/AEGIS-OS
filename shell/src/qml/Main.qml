import QtQuick

// Shell root — four surfaces, no visual content of its own.
// main.cpp finds each window by objectName, attaches it to the layer-shell
// protocol with its surface configuration, and shows it. Windows must be
// visible: false here so the attach happens before the platform surface
// exists.
QtObject {
    objectName: "aegisMain"

    property Desktop desktopSurface: Desktop { }
    property Panel panelSurface: Panel { }
    property Island islandSurface: Island { }
    property Dock dockSurface: Dock { }
}
