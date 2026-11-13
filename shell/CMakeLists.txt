cmake_minimum_required(VERSION 3.22)
project(aegis-shell VERSION 1.4.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS
    Core Gui Qml Quick QuickControls2 DBus Network Concurrent)
find_package(LayerShellQt REQUIRED)
find_package(OpenSSL REQUIRED)
find_library(PAM_LIBRARY pam)

if(TARGET LayerShellQt::Interface)
    set(AEGIS_LAYERSHELL_TARGET LayerShellQt::Interface)
else()
    set(AEGIS_LAYERSHELL_TARGET ${LayerShellQt_LIBRARIES})
endif()

# layer-shell-qt gained Window::setDesiredSize in 6.4 — probe the linked
# header so older distro builds (Debian trixie) still compile.
include(CheckCXXSourceCompiles)
set(CMAKE_REQUIRED_LIBRARIES ${AEGIS_LAYERSHELL_TARGET})
check_cxx_source_compiles(
    "#include <LayerShellQt/Window>
    #include <QSize>
    int main(){ auto *w = (LayerShellQt::Window*)nullptr; w->setDesiredSize(QSize()); return 0; }"
    AEGIS_HAS_DESIRED_SIZE)
unset(CMAKE_REQUIRED_LIBRARIES)

qt_add_executable(aegis-shell
    src/main.cpp
    src/util.h
    src/util.cpp
    src/governor/Governor.h
    src/governor/Governor.cpp
    src/activity/ActivityService.h
    src/activity/ActivityService.cpp
    # Desktop.qml (W36.1) calls Files.makeDir for New Folder — the shell's
    # engine must resolve Aegis.Files, not just the apps binary
    src/apps/filemanager.h
)

qt_add_resources(aegis-shell "shell"
    PREFIX "/qml"
    BASE_DIR src/qml
    FILES
        src/qml/qmldir
        src/qml/Tokens.qml
        src/qml/Spring.qml
        src/qml/GlassPanel.qml
        src/qml/Main.qml
        src/qml/Desktop.qml
        src/qml/Panel.qml
        src/qml/Dock.qml
        src/qml/Island.qml
        src/qml/ControlCenter.qml
        src/qml/CalendarPopover.qml
        src/qml/Launcher.qml
        src/qml/Notifications.qml
        src/qml/Lock.qml
        src/qml/AppWindow.qml
        src/qml/TrafficLights.qml
        src/qml/FilesApp.qml
        src/qml/SettingsApp.qml
        src/qml/aegis-mark.png
)

# The installed QML tree is the primary load path (see main.cpp) — the
# embedded resource is only the fallback.
install(DIRECTORY src/qml/
        DESTINATION share/aegis/shell/qml
        FILES_MATCHING
        PATTERN "*.qml"
        PATTERN "qmldir"
        PATTERN "*.png")

target_link_libraries(aegis-shell PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::DBus
    Qt6::Network   # W22 — the web-shortcut fetch pipeline lives in Util
    ${AEGIS_LAYERSHELL_TARGET}
)

# ── First-party apps (proposal §8) ─────────────────────────────────────
# One host binary, two wrappers: /usr/bin/aegis-files, /usr/bin/aegis-settings.
# Regular Wayland windows — no layer shell. The app QML ships in the same
# installed tree (share/aegis/shell/qml) so Tokens/GlassPanel stay shared.
# Compiles Util + Governor here too — the app QML binds Util.darkMode/
# setDarkMode/launch and Governor.tier/setTier/setAutoMode; Qt6::DBus covers
# the QDBusConnection calls in both translation units.
qt_add_executable(aegis-apps
    src/apps/apps-main.cpp
    src/apps/filemanager.h
    src/apps/systembackends.h
    src/apps/aegisid.h
    src/apps/aegisid.cpp
    src/apps/monitorbackend.h
    src/util.h
    src/util.cpp
    src/governor/Governor.h
    src/governor/Governor.cpp
)

qt_add_resources(aegis-apps "apps-qml"
    PREFIX "/qml"
    BASE_DIR src/qml
    FILES
        src/qml/qmldir
        src/qml/Tokens.qml
        src/qml/Spring.qml
        src/qml/GlassPanel.qml
        src/qml/AppWindow.qml
        src/qml/TrafficLights.qml
        src/qml/FilesApp.qml
        src/qml/SettingsApp.qml
        src/qml/MusicApp.qml
        src/qml/CalculatorApp.qml
        src/qml/EditorApp.qml
        src/qml/MonitorApp.qml
)

target_link_libraries(aegis-apps PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::DBus
    Qt6::Network
    Qt6::Concurrent
    OpenSSL::Crypto
)

install(TARGETS aegis-apps RUNTIME DESTINATION bin)
install(PROGRAMS src/apps/aegis-files src/apps/aegis-settings
                 src/apps/aegis-music src/apps/aegis-calculator
                 src/apps/aegis-editor src/apps/aegis-monitor
                 src/apps/aegis-store
        DESTINATION bin)

if(AEGIS_HAS_DESIRED_SIZE)
    target_compile_definitions(aegis-shell PRIVATE AEGIS_HAS_DESIRED_SIZE)
endif()

# ── aegis-updates: Software Update ─────────────────────────────────────
# The consumer update face: apt via pkexec behind a glass window — the
# GUI answer to "download process and patch updates". Plain (non-
# layer-shell) app, launched like any other app.
qt_add_executable(aegis-updates
    src/updates/main.cpp
    src/updates/updatemanager.h
    src/updates/updatemanager.cpp
)

qt_add_resources(aegis-updates "updates"
    PREFIX "/updates"
    BASE_DIR src/updates
    FILES
        src/updates/Updates.qml
        src/qml/aegis-mark.png
)

target_link_libraries(aegis-updates PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
)

install(TARGETS aegis-updates RUNTIME DESTINATION bin)

# ── aegis-auth: setuid PAM verifier for the lock screen ────────────────
# Plain C, no Qt: reads the password on stdin, answers through
# pam_unix (service "aegis-auth"). Swaylock's model, minimum size.
add_executable(aegis-auth src/auth/aegis-auth.c)
target_link_libraries(aegis-auth PRIVATE ${PAM_LIBRARY})

install(TARGETS aegis-shell RUNTIME DESTINATION bin)
install(TARGETS aegis-auth RUNTIME DESTINATION bin
        PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                    GROUP_READ GROUP_EXECUTE
                    WORLD_READ WORLD_EXECUTE
                    SETUID)
install(FILES src/auth/aegis-auth.pam DESTINATION /etc/pam.d
        RENAME aegis-auth)

install(FILES src/session/aegis-session DESTINATION bin
        PERMISSIONS OWNER_READ OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
install(FILES packaging/aegis.desktop DESTINATION share/wayland-sessions)
install(FILES packaging/config.json DESTINATION share/aegis/shell)

# ── session CLIs ────────────────────────────────────────────────────────
# aegis-lock     — lock the session (dbus call → org.aegis.Shell.lock)
# aegis-activity — publish/end island activities (the Live Activity API demo client)
install(FILES packaging/aegis-lock DESTINATION bin
        PERMISSIONS OWNER_READ OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
install(FILES packaging/aegis-activity DESTINATION bin
        PERMISSIONS OWNER_READ OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
