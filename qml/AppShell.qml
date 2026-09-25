import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#0d0d0d"

    required property var authBridge

    // Use system monospace font (respects terminal font settings)
    readonly property string monoFont: "Courier"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 0
        spacing: 0

        // Top bar with TUI style
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            color: "#0d0d0d"
            border.color: "#7c6af7"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 16

                Text {
                    text: "  ◆ OmarchyLook"
                    font.family: root.monoFont
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    color: "#7c6af7"
                    Layout.fillWidth: true
                }

                Text {
                    text: "📧 [m]ail  📅 [c]alendar  👥 [p]hotos  ✓ [t]asks  |  [?] help  [q] quit"
                    font.family: root.monoFont
                    font.pixelSize: 9
                    color: "#888888"
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Navigation panel (TUI style)
            Rectangle {
                width: 240
                color: "#0d0d0d"
                border.color: "#7c6af7"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 0
                    spacing: 0

                    // Nav header
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        color: "#1a1a1a"
                        border.color: "#7c6af7"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "  ◆ NAVIGATION"
                            font.family: root.monoFont
                            font.pixelSize: 10
                            font.bold: true
                            color: "#7c6af7"
                        }
                    }

                    // Mail nav item
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        Layout.topMargin: 4

                        color: "#0d0d0d"
                        border.color: "#7c6af7"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "  [M] Mail"
                            font.family: root.monoFont
                            font.pixelSize: 10
                            color: "#7c6af7"
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.border.color = "#9f8fff"
                            onExited: parent.border.color = "#7c6af7"
                        }
                    }

                    // Calendar nav item
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        Layout.topMargin: 4

                        color: "#0d0d0d"
                        border.color: "#333333"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "  [C] Calendar"
                            font.family: root.monoFont
                            font.pixelSize: 10
                            color: "#666666"
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.border.color = "#9f8fff"
                            onExited: parent.border.color = "#333333"
                        }
                    }

                    // Contacts nav item
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        Layout.topMargin: 4

                        color: "#0d0d0d"
                        border.color: "#333333"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "  [P] Contacts"
                            font.family: root.monoFont
                            font.pixelSize: 10
                            color: "#666666"
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.border.color = "#9f8fff"
                            onExited: parent.border.color = "#333333"
                        }
                    }

                    // Tasks nav item
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        Layout.topMargin: 4

                        color: "#0d0d0d"
                        border.color: "#333333"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "  [T] Tasks"
                            font.family: root.monoFont
                            font.pixelSize: 10
                            color: "#666666"
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.border.color = "#9f8fff"
                            onExited: parent.border.color = "#333333"
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Logout button (TUI style)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        Layout.margins: 8

                        color: "#0d0d0d"
                        border.color: logoutMouse.containsMouse ? "#ff8787" : "#7c6af7"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "  ✕ Logout  "
                            font.family: root.monoFont
                            font.pixelSize: 10
                            color: logoutMouse.containsMouse ? "#ff8787" : "#7c6af7"
                        }

                        MouseArea {
                            id: logoutMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                // TODO: emit logout signal via authBridge
                                console.log("Logout clicked")
                            }
                        }
                    }
                }
            }

            // Main content area (TUI style)
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#0d0d0d"
                border.color: "#7c6af7"
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // Content header
                    Text {
                        text: "┌─ Mail (Phase 2 Placeholder) ─┐"
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: "#7c6af7"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "Navigation modules loading...\nKeyboard shortcuts: [M]ail, [C]alendar, [P]hotos, [T]asks"
                        font.family: root.monoFont
                        font.pixelSize: 10
                        color: "#cccccc"
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Item { Layout.fillHeight: true }

                    Text {
                        text: "┌──────────────────────────────┐"
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: "#7c6af7"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "Phase 3 coming soon: Email list, message view, calendar, contacts, task management"
                        font.family: root.monoFont
                        font.pixelSize: 9
                        color: "#888888"
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "└──────────────────────────────┘"
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: "#7c6af7"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }
    }
}
