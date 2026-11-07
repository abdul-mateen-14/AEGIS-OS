cmake_minimum_required(VERSION 3.22)
project(aegis-shell VERSION 1.4.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 DBus)
find_package(LayerShellQt REQUIRED)
find_library(PAM_LIBRARY pam)

if(TARGET LayerShellQt::Interface)
    set(AEGIS_LAYERSHELL_TARGET LayerShellQt::Interface)
else()
    set(AEGIS_LAYERSHELL_TARGET ${LayerShellQt_LIBRARIES})
endif()

qt_add_executable(aegis-shell
    src/main.cpp
    src/util.h
    src/util.cpp
    src/governor/Governor.h
    src/governor/Governor.cpp
    src/activity/ActivityService.h
    src/activity/ActivityService.cpp
)

qt_add_resources(aegis-shell "shell"
    PREFIX "/qml"
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
        src/qml/Launcher.qml
        src/qml/Notifications.qml
        src/qml/Lock.qml
        src/qml/aegis-mark.png
)

target_link_libraries(aegis-shell PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::DBus
    ${AEGIS_LAYERSHELL_TARGET}
)

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
