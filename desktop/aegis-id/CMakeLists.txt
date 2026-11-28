cmake_minimum_required(VERSION 3.16)
project(aegis-id VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick)

qt_add_executable(aegis-id
    src/main.cpp
)

qt_add_resources(aegis-id "qml"
    PREFIX "/qml"
    FILES src/qml/Main.qml
)

target_link_libraries(aegis-id PRIVATE Qt6::Quick)

install(TARGETS aegis-id RUNTIME DESTINATION bin)
install(FILES data/aegis-id.desktop DESTINATION share/applications)
