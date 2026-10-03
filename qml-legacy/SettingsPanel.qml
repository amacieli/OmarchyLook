import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#0d0d0d"

    required property var settingsManager
    required property var authBridge
    required property bool isAuthenticated

    property string monoFont: settingsManager.get_font_family()
    property int baseSize: settingsManager.get_base_size()
    property int titleSize: settingsManager.get_title_size()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // Title bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            color: "#1a1a1a"
            border.color: "#333333"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "Settings"
                font.family: root.monoFont
                font.pixelSize: root.titleSize
                font.bold: true
                color: "#7c6af7"
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                width: root.width - 24
                spacing: 16

                // Font Settings Section
                Text {
                    text: "Font Settings"
                    font.family: root.monoFont
                    font.pixelSize: root.baseSize
                    font.bold: true
                    color: "#7c6af7"
                    Layout.fillWidth: true
                }

                // Font Family
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "Font Family:"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: "#cccccc"
                        Layout.preferredWidth: 120
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        color: "#1a1a1a"
                        border.color: fontFamilyMouse.containsMouse ? "#7c6af7" : "#333333"
                        border.width: 1

                        TextInput {
                            id: fontFamilyInput
                            anchors.fill: parent
                            anchors.margins: 6
                            font.family: "monospace"
                            font.pixelSize: root.baseSize
                            color: "#e8e8e8"
                            text: root.monoFont
                            selectByMouse: true
                        }

                        MouseArea {
                            id: fontFamilyMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onPressed: {
                                mouse.accepted = false
                                fontFamilyInput.forceActiveFocus()
                            }
                        }
                    }

                    Button {
                        text: "Save"
                        Layout.preferredWidth: 60
                        onClicked: {
                            settingsManager.set_font_family(fontFamilyInput.text)
                            root.monoFont = fontFamilyInput.text
                        }
                    }
                }

                // Font Size
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "Font Size:"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: "#cccccc"
                        Layout.preferredWidth: 120
                    }

                    SpinBox {
                        from: 8
                        to: 24
                        value: root.baseSize
                        Layout.preferredWidth: 80
                        onValueChanged: {
                            settingsManager.set_font_size(value)
                            root.baseSize = value
                            root.titleSize = Math.round(value * 1.2)
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // UI Settings Section
                Text {
                    text: "UI Settings"
                    font.family: root.monoFont
                    font.pixelSize: root.baseSize
                    font.bold: true
                    color: "#7c6af7"
                    Layout.fillWidth: true
                }

                // TUI Style toggle
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "Terminal UI Style:"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: "#cccccc"
                    }

                    CheckBox {
                        checked: true
                        Layout.fillWidth: true
                    }
                }

                // Animation toggle
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "Enable Animations:"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: "#cccccc"
                    }

                    CheckBox {
                        checked: true
                        Layout.fillWidth: true
                    }
                }

                // Sync Settings Section
                Text {
                    text: "Sync Settings"
                    font.family: root.monoFont
                    font.pixelSize: root.baseSize
                    font.bold: true
                    color: "#7c6af7"
                    Layout.fillWidth: true
                }

                // Poll Interval
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "Poll Interval (sec):"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: "#cccccc"
                        Layout.preferredWidth: 140
                    }

                    SpinBox {
                        from: 10
                        to: 300
                        value: 60
                        stepSize: 10
                        Layout.preferredWidth: 80
                    }

                    Item { Layout.fillWidth: true }
                }

                // Cache Retention
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "Cache Retention (days):"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: "#cccccc"
                        Layout.preferredWidth: 140
                    }

                    SpinBox {
                        from: 0
                        to: 365
                        value: 30
                        Layout.preferredWidth: 80
                    }

                    Item { Layout.fillWidth: true }
                }

                // Account Settings Section
                Text {
                    text: "Account Settings"
                    font.family: root.monoFont
                    font.pixelSize: root.baseSize
                    font.bold: true
                    color: "#7c6af7"
                    Layout.fillWidth: true
                }

                // Graph API Authentication button
                // Shows different button based on authentication state
                Rectangle {
                    id: authButton
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    color: root.isAuthenticated ? "#1a3a1a" : "#1a1a1a"
                    border.color: root.isAuthenticated ? "#51cf66" : "#333333"
                    border.width: 1
                    
                    // Hover effect
                    MouseArea {
                        id: authButtonMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        
                        onEntered: {
                            if (root.isAuthenticated) {
                                parent.border.color = "#ff6b6b"
                            } else {
                                parent.border.color = "#7c6af7"
                            }
                        }
                        
                        onExited: {
                            parent.border.color = root.isAuthenticated ? "#51cf66" : "#333333"
                        }
                        
                        onClicked: {
                            if (root.isAuthenticated) {
                                // Logout
                                console.log("[Settings] Logout button clicked")
                                var result = authBridge.logout()
                                if (result) {
                                    console.log("[Settings] Logout successful")
                                    // The parent window will detect auth state change
                                    // and reload the UI
                                } else {
                                    console.error("[Settings] Logout failed")
                                }
                            } else {
                                // Login
                                console.log("[Settings] Authenticate button clicked")
                                var result = authBridge.login()
                                if (result) {
                                    console.log("[Settings] Device Flow initiated")
                                } else {
                                    console.error("[Settings] Failed to start Device Flow")
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.isAuthenticated ? "  ✓ Logged in with Microsoft  " : "  🔐 Click to authenticate with Microsoft Graph  "
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: root.isAuthenticated ? "#51cf66" : "#7c6af7"
                    }
                }

                    }
                }

                Item { Layout.fillHeight: true }

                // Footer
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: "#333333"
                }

                Text {
                    text: "Settings are saved automatically."
                    font.family: root.monoFont
                    font.pixelSize: root.baseSize
                    color: "#888888"
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }
}
