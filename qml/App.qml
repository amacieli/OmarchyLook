import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root
    visible: true
    width: 1280
    height: 800
    title: "omarchy-look"

    // Omarchy color palette
    readonly property color bgDark: "#1a1a1a"
    readonly property color bgSurface: "#242424"
    readonly property color colorBorder: "#333333"
    readonly property color textPrimary: "#e8e8e8"
    readonly property color textSecondary: "#888888"
    readonly property color accentPurple: "#7c6af7"
    readonly property color dangerRed: "#e05c5c"
    readonly property color successGreen: "#5cc85c"

    color: bgDark

    // Shared font families
    readonly property string fontUI: "Inter"
    readonly property string fontMono: "JetBrains Mono"

    // Defer sourceComponent until authBridge is available (loaded from context)
    Loader {
        id: contentLoader
        anchors.fill: parent
        sourceComponent: loginScreenComponent
    }

    Component {
        id: loginScreenComponent
        LoginScreen {
            authBridge: typeof authBridge !== 'undefined' ? authBridge : null
        }
    }

    Component {
        id: appShellComponent
        AppShell {
            authBridge: typeof authBridge !== 'undefined' ? authBridge : null
        }
    }
}
