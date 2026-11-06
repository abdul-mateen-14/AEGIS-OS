cmake_minimum_required(VERSION 3.22)
project(aegis-shell VERSION 1.4.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)
find_package(LayerShellQt REQUIRED)

if(TARGET LayerShellQt::Interface)
    set(AEGIS_LAYERSHELL_TARGET LayerShellQt::Interface)
else()
    set(AEGIS_LAYERSHELL_TARGET ${LayerShellQt_LIBRARIES})
endif()

qt_add_executable(aegis-shell
    src/main.cpp
    src/util.h
    src/util.cpp
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
        src/qml/aegis-mark.png
)

target_link_libraries(aegis-shell PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    ${AEGIS_LAYERSHELL_TARGET}
)

install(TARGETS aegis-shell RUNTIME DESTINATION bin)
install(FILES src/session/aegis-session DESTINATION bin
        PERMISSIONS OWNER_READ OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
install(FILES packaging/aegis.desktop DESTINATION share/wayland-sessions)
install(FILES packaging/config.json DESTINATION share/aegis/shell)
