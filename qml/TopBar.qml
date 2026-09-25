import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#1a1a1a"
    height: 48

    required property var authBridge

    RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 12

        // App title
        Text {
            text: "omarchy-look"
            font.family: "Inter"
            font.pixelSize: 14
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
                font.pixelSize: 12
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
                font.pixelSize: 14
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
                        font.pixelSize: 11
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
                        font.pixelSize: 12
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
                        font.pixelSize: 12
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
