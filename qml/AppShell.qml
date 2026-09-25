import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#0d0d0d"

    required property var authBridge

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
                    font.family: "JetBrains Mono"
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    color: "#7c6af7"
                    Layout.fillWidth: true
                }

                Text {
                    text: "📧 [m]ail  📅 [c]alendar  👥 [c]ontacts  ✓ [t]asks  |  [?] help  [q] quit"
                    font.family: "JetBrains Mono"
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
                            font.family: "JetBrains Mono"
                            font.pixelSize: 10
                            font.bold: true
                            color: "#7c6af7"
                        }
                    }

                    // Nav items
                    NavItem {
                        navText: "  [M] Mail"
                        isActive: true
                    }

                    NavItem {
                        navText: "  [C] Calendar"
                        isActive: false
                    }

                    NavItem {
                        navText: "  [P] Contacts"
                        isActive: false
                    }

                    NavItem {
                        navText: "  [T] Tasks"
                        isActive: false
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
                            font.family: "JetBrains Mono"
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
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        color: "#7c6af7"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "Navigation modules loading...\nKeyboard shortcuts: [M]ail, [C]alendar, [P]hotos, [T]asks"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 10
                        color: "#cccccc"
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Item { Layout.fillHeight: true }

                    Text {
                        text: "┌──────────────────────────────┐"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        color: "#7c6af7"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "Phase 3 coming soon: Email list, message view, calendar, contacts, task management"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 9
                        color: "#888888"
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "└──────────────────────────────┘"
                        font.family: "JetBrains Mono"
                        font.pixelSize: 11
                        color: "#7c6af7"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }
    }
}

// Reusable navigation item component
Component {
    id: navItemComponent
    Rectangle {
        property string navText: ""
        property bool isActive: false

        Layout.fillWidth: true
        Layout.preferredHeight: 32
        Layout.margins: 0
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.topMargin: 4

        color: "#0d0d0d"
        border.color: isActive ? "#7c6af7" : "#333333"
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: navText
            font.family: "JetBrains Mono"
            font.pixelSize: 10
            color: isActive ? "#7c6af7" : "#666666"
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: parent.border.color = "#9f8fff"
            onExited: parent.border.color = parent.isActive ? "#7c6af7" : "#333333"
            onClicked: {
                console.log("Nav item clicked:", navText)
                parent.isActive = true
            }
        }
    }
}

// Define NavItem as a simple placeholder rectangle
Rectangle {
    id: navItemPlaceholder
    property string navText: ""
    property bool isActive: false
    visible: false
}

// Inline nav item for now
Component {
    id: navItem
    Rectangle {
        property alias navText: navLabel.text
        property bool isActive: false

        Layout.fillWidth: true
        Layout.preferredHeight: 32
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.topMargin: 4

        color: "#0d0d0d"
        border.color: isActive ? "#7c6af7" : "#333333"
        border.width: 1

        Text {
            id: navLabel
            anchors.centerIn: parent
            font.family: "JetBrains Mono"
            font.pixelSize: 10
            color: isActive ? "#7c6af7" : "#666666"
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: parent.border.color = "#9f8fff"
            onExited: parent.border.color = parent.isActive ? "#7c6af7" : "#333333"
        }
    }
}
