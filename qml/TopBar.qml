import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#1a1a1a"
    height: 48

    required property var authBridge
    property var settingsManagerRef: typeof settingsManager !== 'undefined' ? settingsManager : null

    readonly property string monoFont: settingsManagerRef ? settingsManagerRef.get_font_family() : "monospace"
    readonly property int baseSize: settingsManagerRef ? settingsManagerRef.get_font_base_size() : 10
    readonly property int titleSize: settingsManagerRef ? settingsManagerRef.get_title_size() : 12
    readonly property int hintSize: settingsManagerRef ? settingsManagerRef.get_hint_size() : 8

    RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 12

        // Listen for settings changes
        Connections {
            target: root.settingsManagerRef
            function onFontSettingsChanged() {
                console.log("TopBar.qml: Font settings changed")
            }
        }

        // App title
        Text {
            text: "OmarchyLook"
            font.family: "Inter"
            font.pixelSize: root.titleSize
            font.weight: Font.Bold
            color: "#e8e8e8"
        }

        Item { Layout.fillWidth: true }

        // Search bar (placeholder for Phase 5)
        Rectangle {
            Layout.preferredWidth: 200
            Layout.preferredHeight: 32
            color: "#242424"
            radius: 4
            border.color: "#333333"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "Search... (Ctrl+K)"
                font.family: "Inter"
                font.pixelSize: root.titleSize
                color: "#888888"
            }
        }

        // Sync status indicator
        Rectangle {
            width: 12
            height: 12
            radius: 6
            color: "#5cc85c"  // Green = idle

            ToolTip.visible: hoverHandler.hovered
            ToolTip.text: "Synced"

            HoverHandler {
                id: hoverHandler
            }
        }

        // Account avatar
        Rectangle {
            width: 32
            height: 32
            radius: 16
            color: "#7c6af7"

            Text {
                anchors.centerIn: parent
                text: authBridge.getFirstLetterAvatar()
                font.family: "Inter"
                font.pixelSize: root.titleSize
                font.weight: Font.Bold
                color: "#ffffff"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: accountMenu.open()

                ToolTip.visible: containsMouse
                ToolTip.text: authBridge.displayName
            }

            Menu {
                id: accountMenu
                y: parent.height + 4
                x: -width + parent.width

                MenuItem {
                    text: `Signed in as ${authBridge.username}`
                    enabled: false

                    background: Rectangle {
                        color: "#242424"
                        implicitHeight: 32
                    }

                    contentItem: Text {
                        text: parent.text
                        font.family: "Inter"
                        font.pixelSize: root.baseSize
                        color: "#888888"
                        leftPadding: 8
                    }
                }

                MenuSeparator {}

                MenuItem {
                    text: "Settings"
                    onClicked: {} // Phase 9

                    background: Rectangle {
                        color: parent.hovered ? "#333333" : "#242424"
                    }

                    contentItem: Text {
                        text: parent.text
                        font.family: "Inter"
                        font.pixelSize: root.baseSize
                        color: "#e8e8e8"
                        leftPadding: 8
                    }
                }

                MenuItem {
                    text: "Sign out"
                    onClicked: authBridge.logout()

                    background: Rectangle {
                        color: parent.hovered ? "#333333" : "#242424"
                    }

                    contentItem: Text {
                        text: parent.text
                        font.family: "Inter"
                        font.pixelSize: root.baseSize
                        color: "#e05c5c"
                        leftPadding: 8
                    }
                }
            }
        }
    }

    border.color: "#333333"
    border.width: 1
}
