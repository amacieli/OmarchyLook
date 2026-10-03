import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root
    visible: true
    width: settingsManager.get_ui_window_width()
    height: settingsManager.get_ui_window_height()
    title: "OmarchyLook"

    // Settings reference
    property var settingsManagerRef: typeof settingsManager !== 'undefined' ? settingsManager : null

    // TUI color palette (from settings)
    readonly property color bgDark: settingsManagerRef ? settingsManagerRef.get_color_bg_dark() : "#0d0d0d"
    readonly property color bgSurface: settingsManagerRef ? settingsManagerRef.get_color_bg_surface() : "#242424"
    readonly property color colorBorder: settingsManagerRef ? settingsManagerRef.get_color_border() : "#333333"
    readonly property color textPrimary: settingsManagerRef ? settingsManagerRef.get_color_text_primary() : "#e8e8e8"
    readonly property color textSecondary: settingsManagerRef ? settingsManagerRef.get_color_text_secondary() : "#888888"
    readonly property color accentPurple: settingsManagerRef ? settingsManagerRef.get_color_accent_purple() : "#7c6af7"
    readonly property color dangerRed: settingsManagerRef ? settingsManagerRef.get_color_danger_red() : "#ff6b6b"
    readonly property color successGreen: settingsManagerRef ? settingsManagerRef.get_color_success_green() : "#51cf66"

    color: bgDark

    // Store authBridge reference for Components to access
    property var authBridgeRef: typeof authBridge !== 'undefined' ? authBridge : null
    
    // Track auth state to switch between login and app shell
    // Initialize from authBridge when it becomes available
    property bool isAuthenticated: false
    
    // Initialize auth state when component is ready
    Component.onCompleted: {
        if (authBridgeRef) {
            isAuthenticated = authBridgeRef.is_authenticated()
            console.log("App.qml: Initialized isAuthenticated =", isAuthenticated)
        } else {
            console.warn("App.qml: authBridge not available on startup")
        }
    }

    // Defer sourceComponent until authBridge is available (loaded from context)
    Loader {
        id: contentLoader
        anchors.fill: parent
        sourceComponent: isAuthenticated ? appShellComponent : loginScreenComponent
    }

    // Listen for auth state changes
    Connections {
        target: authBridgeRef
        enabled: authBridgeRef !== null
        function onLoginSucceeded() {
            console.log("App.qml: Auth succeeded, switching to AppShell")
            isAuthenticated = true
        }
        function onLogoutSucceeded() {
            console.log("App.qml: Logout succeeded, switching to LoginScreen")
            isAuthenticated = false
        }
    }

    // Listen for settings changes to reload UI
    Connections {
        target: settingsManagerRef
        function onSettingsChanged() {
            console.log("App.qml: Settings changed, refreshing UI")
            // Force repaint by toggling visibility
            root.update()
        }
    }

    Component {
        id: loginScreenComponent
        LoginScreen {
            authBridge: root.authBridgeRef
        }
    }

    Component {
        id: appShellComponent
        AppShell {
            authBridge: root.authBridgeRef
            isAuthenticated: root.isAuthenticated
        }
    }
}
