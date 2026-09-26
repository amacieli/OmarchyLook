fn main() {
    // CXX-Qt build configuration for Qt 6
    // Currently disabled: qmlscene runs in separate process
    // TODO: Enable when switching to embedded QML engine
    // cxx_qt_build::CxxQtBuild::new()
    //     .with_qt_module_names(&["Core", "Gui", "Qml"])
    //     .build();
    
    println!("cargo:rerun-if-changed=src/qt_bridge/mod.rs");
}
