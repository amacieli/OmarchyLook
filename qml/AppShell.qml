import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#0d0d0d"

    required property var authBridge
    property var settingsManagerRef: typeof settingsManager !== 'undefined' ? settingsManager : null

    // Use system monospace font (respects terminal font settings)
    readonly property string monoFont: settingsManagerRef ? settingsManagerRef.get_font_family() : "monospace"
    readonly property int baseSize: settingsManagerRef ? settingsManagerRef.get_font_base_size() : 10
    readonly property int titleSize: settingsManagerRef ? settingsManagerRef.get_title_size() : 12
    readonly property int hintSize: settingsManagerRef ? settingsManagerRef.get_hint_size() : 8

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 0
        spacing: 0

        // Listen for settings changes
        Connections {
            target: root.settingsManagerRef
            function onFontSettingsChanged() {
                console.log("AppShell.qml: Font settings changed")
                // Font properties update via binding automatically
            }
        }

        // Top bar with TUI style
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.round(baseSize * 3.2)
            color: "#0d0d0d"
            border.color: "#7c6af7"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 16

                Text {
                    text: "OmarchyLook"
                    font.family: root.monoFont
                    font.pixelSize: root.titleSize
                    font.weight: Font.Bold
                    color: "#7c6af7"
                    Layout.fillWidth: true
                }

                Text {
                    text: "📧 [m]ail  📅 [c]alendar  👥 [p]hotos  ✓ [t]asks  |  [?] help  [q] quit"
                    font.family: root.monoFont
                    font.pixelSize: root.baseSize
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
                        Layout.preferredHeight: root.titleSize
                        color: "#1a1a1a"
                        border.color: "#7c6af7"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "NAVIGATION"
                            font.family: root.monoFont
                            font.pixelSize: root.baseSize
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
                            font.pixelSize: root.baseSize
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
                            font.pixelSize: root.baseSize
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
                            font.pixelSize: root.baseSize
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
                            font.pixelSize: root.baseSize
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
                            font.pixelSize: root.baseSize
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
                        font.pixelSize: root.baseSize
                        color: "#7c6af7"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "Navigation modules loading...\nKeyboard shortcuts: [M]ail, [C]alendar, [P]hotos, [T]asks"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: "#cccccc"
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    Item { Layout.fillHeight: true }

                    Text {
                        text: "┌──────────────────────────────┐"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: "#7c6af7"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        text: "Phase 3 coming soon: Email list, message view, calendar, contacts, task management"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: "#888888"
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "└──────────────────────────────┘"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: "#7c6af7"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }
    }
}
