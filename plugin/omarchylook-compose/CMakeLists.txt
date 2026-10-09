cmake_minimum_required(VERSION 3.21)
project(omarchylook_compose LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)
qt_policy(SET QTP0001 NEW)
# Output layout: <build>/qml/OmarchyLook/Compose/{qmldir,libomarchylook_compose.so,...};
# point QML_IMPORT_PATH at <build>/qml.
qt_add_qml_module(omarchylook_compose
    URI OmarchyLook.Compose
    VERSION 1.0
    PLUGIN_TARGET omarchylook_compose_plugin
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/OmarchyLook/Compose
    SOURCES documenthandler.h documenthandler.cpp)
target_link_libraries(omarchylook_compose PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick)
