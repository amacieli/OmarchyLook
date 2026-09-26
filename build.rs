fn main() {
    // CXX-Qt build configuration for Qt 6
    // For now, we'll skip the cxx-qt-build and defer Qt bridging
    // until we have actual QML/Rust integration code
    
    println!("cargo:rerun-if-changed=src/qt_bridge/mod.rs");
}
