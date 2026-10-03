import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#0d0d0d"

    required property var authBridge
    required property bool isAuthenticated
    property var settingsManagerRef: typeof settingsManager !== 'undefined' ? settingsManager : null
    property var composeBridgeRef: typeof composeBridge !== 'undefined' ? composeBridge : null

    // Use system monospace font (respects terminal font settings)
    property string monoFont: settingsManagerRef ? settingsManagerRef.get_font_family() : "monospace"
    property int baseSize: settingsManagerRef ? settingsManagerRef.get_base_size() : 10
    property int titleSize: settingsManagerRef ? settingsManagerRef.get_title_size() : 12
    property int hintSize: settingsManagerRef ? settingsManagerRef.get_hint_size() : 8
    
    // Track current view state
    property string currentView: "mail"  // "mail", "compose", or "settings"
    property string mailView: "list"  // "list" or "detail" (sub-views for mail)
    property int selectedEmailIndex: -1  // Track which email is selected

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 0
        spacing: 0

        // Listen for settings changes
        Connections {
            target: root.settingsManagerRef
            function onFontSettingsChanged() {
                console.log("AppShell.qml: Font settings changed, updating properties")
                root.monoFont = settingsManagerRef ? settingsManagerRef.get_font_family() : "monospace"
                root.baseSize = settingsManagerRef ? settingsManagerRef.get_base_size() : 10
                root.titleSize = settingsManagerRef ? settingsManagerRef.get_title_size() : 12
                root.hintSize = settingsManagerRef ? settingsManagerRef.get_hint_size() : 8
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
                
                // Compose button
                Rectangle {
                    Layout.preferredWidth: 120
                    Layout.preferredHeight: 28
                    color: "#0d0d0d"
                    border.color: composeBtnMouse.containsMouse ? "#51cf66" : "#7c6af7"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "✎ Compose"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: composeBtnMouse.containsMouse ? "#51cf66" : "#7c6af7"
                    }

                    MouseArea {
                        id: composeBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.currentView = (root.currentView === "mail") ? "compose" : "mail"
                            console.log("Switching to: " + root.currentView)
                        }
                    }
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
                            text: "[M] Mail"
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
                            text: "[C] Calendar"
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
                            text: "[P] Contacts"
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
                            text: "[T] Tasks"
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

                    // Settings nav menu
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        Layout.topMargin: 4

                        color: root.currentView === "settings" ? "#7c6af7" : "#0d0d0d"
                        border.color: root.currentView === "settings" ? "#7c6af7" : "#333333"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "[S] Settings"
                            font.family: root.monoFont
                            font.pixelSize: root.baseSize
                            color: root.currentView === "settings" ? "#0d0d0d" : "#666666"
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.border.color = "#9f8fff"
                            onExited: parent.border.color = root.currentView === "settings" ? "#7c6af7" : "#333333"
                            onClicked: {
                                root.currentView = "settings"
                                console.log("Switching to Settings")
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // Main content area (TUI style) - switches between views
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#0d0d0d"
                border.color: "#7c6af7"
                border.width: 1

                // Content loader - switches between mail, compose, and settings views
                Loader {
                    id: contentLoader
                    anchors.fill: parent
                    sourceComponent: {
                        if (root.currentView === "compose") {
                            return composeViewComponent
                        } else if (root.currentView === "settings") {
                            return settingsViewComponent
                        } else {
                            return mailViewComponent
                        }
                    }
                }

                Component {
                    id: composeViewComponent
                    ComposeMail {
                        composeBridge: root.composeBridgeRef
                        settingsManager: root.settingsManagerRef
                    }
                }

                Component {
                    id: settingsViewComponent
                    SettingsPanel {
                        authBridge: root.authBridge
                        settingsManager: root.settingsManagerRef
                        isAuthenticated: root.isAuthenticated
                    }
                }

                Component {
                    id: mailViewComponent
                    Loader {
                        anchors.fill: parent
                        sourceComponent: root.mailView === "detail" ? messageDetailComponent : mailListComponent
                    }
                }

                Component {
                    id: mailListComponent
                    MailListView {
                        mailListBridge: typeof mailListBridge !== 'undefined' ? mailListBridge : null
                        settingsManager: root.settingsManagerRef
                        onShowDetailView: {
                            root.selectedEmailIndex = index
                            root.mailView = "detail"
                        }
                    }
                }

                Component {
                    id: messageDetailComponent
                    MessageDetail {
                        mailListBridge: typeof mailListBridge !== 'undefined' ? mailListBridge : null
                        settingsManager: root.settingsManagerRef
                        selectedIndex: root.selectedEmailIndex
                        onBackToList: {
                            root.mailView = "list"
                        }
                    }
                }
            }
        }
    }
}
