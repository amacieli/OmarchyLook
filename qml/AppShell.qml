import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#1a1a1a"

    required property var authBridge

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 0
        spacing: 0

        // Top bar
        TopBar {
            authBridge: authBridge
            Layout.fillWidth: true
            Layout.preferredHeight: 48
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Placeholder: NavRail will go here (Phase 2)
            Rectangle {
                width: 220
                color: "#1a1a1a"
                border.color: "#333333"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    Text {
                        text: "✉ Mail"
                        font.family: "Inter"
                        font.pixelSize: 14
                        color: "#e8e8e8"
                    }

                    Text {
                        text: "📅 Calendar"
                        font.family: "Inter"
                        font.pixelSize: 14
                        color: "#888888"
                    }

                    Text {
                        text: "👥 Contacts"
                        font.family: "Inter"
                        font.pixelSize: 14
                        color: "#888888"
                    }

                    Text {
                        text: "✓ Tasks"
                        font.family: "Inter"
                        font.pixelSize: 14
                        color: "#888888"
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // Main content area
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#242424"

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 16
                    width: 400

                    Text {
                        text: "Phase 2: App Shell & Navigation"
                        font.family: "Inter"
                        font.pixelSize: 20
                        font.weight: Font.Bold
                        color: "#7c6af7"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "Navigation modules loading..."
                        font.family: "Inter"
                        font.pixelSize: 14
                        color: "#888888"
                        Layout.alignment: Qt.AlignHCenter
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "Press ? for keyboard shortcuts"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        color: "#888888"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }
    }
}
