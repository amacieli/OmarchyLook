import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#0d0d0d"

    required property var mailListBridge
    required property var settingsManager
    
    signal showDetailView(int index)
    
    // UI settings from SettingsManager
    property string monoFont: settingsManager ? settingsManager.get_font_family() : "monospace"
    property int baseSize: settingsManager ? settingsManager.get_base_size() : 10
    property int titleSize: settingsManager ? settingsManager.get_title_size() : 12
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 0
        spacing: 0
        
        // Search bar + filter controls
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: "#1a1a1a"
            border.bottom.color: "#333333"
            border.bottom.width: 1
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                
                // Search input
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    color: "#0d0d0d"
                    border.color: "#7c6af7"
                    border.width: 1
                    
                    TextInput {
                        id: searchInput
                        anchors.fill: parent
                        anchors.margins: 8
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: "#e8e8e8"
                        cursorVisible: true
                        selectionColor: "#7c6af7"
                        placeholderText: "Search..."
                        
                        onTextChanged: {
                            // Live search: debounced via Timer
                            searchTimer.restart()
                        }
                    }
                    
                    Timer {
                        id: searchTimer
                        interval: 300
                        onTriggered: {
                            if (mailListBridge && searchInput.text !== undefined) {
                                mailListBridge.search(searchInput.text)
                            }
                        }
                    }
                }
                
                // Filter buttons
                Rectangle {
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 36
                    color: "#0d0d0d"
                    border.color: filterUnreadMouse.containsMouse ? "#9f8fff" : "#7c6af7"
                    border.width: 1
                    
                    Text {
                        anchors.centerIn: parent
                        text: "Unread"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize - 2
                        color: filterUnreadMouse.containsMouse ? "#9f8fff" : "#7c6af7"
                    }
                    
                    MouseArea {
                        id: filterUnreadMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (mailListBridge) {
                                mailListBridge.filter_unread()
                            }
                        }
                    }
                }
                
                // Clear filters
                Rectangle {
                    Layout.preferredWidth: 60
                    Layout.preferredHeight: 36
                    color: "#0d0d0d"
                    border.color: clearMouse.containsMouse ? "#9f8fff" : "#7c6af7"
                    border.width: 1
                    
                    Text {
                        anchors.centerIn: parent
                        text: "Clear"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize - 2
                        color: clearMouse.containsMouse ? "#9f8fff" : "#7c6af7"
                    }
                    
                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (mailListBridge) {
                                mailListBridge.clear_filters()
                                searchInput.text = ""
                            }
                        }
                    }
                }
            }
        }
        
        // Email count
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            color: "#1a1a1a"
            border.bottom.color: "#333333"
            border.bottom.width: 1
            
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "Inbox (" + (mailListBridge ? mailListBridge.email_count() : 0) + ") — Unread: " + (mailListBridge ? mailListBridge.get_unread_count() : 0)
                font.family: root.monoFont
                font.pixelSize: root.baseSize
                color: "#888888"
            }
        }
        
        // Email list
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            model: mailListBridge ? mailListBridge.email_count() : 0
            delegate: Rectangle {
                width: parent.width
                height: 60
                color: delegateMouse.containsMouse ? "#1a1a1a" : "#0d0d0d"
                border.bottom.color: "#333333"
                border.bottom.width: 1
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4
                    
                    // Subject + unread indicator
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        
                        // Unread dot
                        Rectangle {
                            Layout.preferredWidth: 8
                            Layout.preferredHeight: 8
                            radius: 4
                            visible: mailListBridge && !mailListBridge.get_email(index).is_read
                            color: "#4ade80"
                        }
                        
                        Text {
                            text: mailListBridge ? mailListBridge.get_email(index).subject : "Loading..."
                            font.family: root.monoFont
                            font.pixelSize: root.titleSize
                            font.bold: mailListBridge && !mailListBridge.get_email(index).is_read
                            color: "#7c6af7"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    
                    // From + date
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        
                        Text {
                            text: mailListBridge ? mailListBridge.get_email(index).from_email : "..."
                            font.family: root.monoFont
                            font.pixelSize: root.baseSize
                            color: "#888888"
                            Layout.preferredWidth: 200
                            elide: Text.ElideRight
                        }
                        
                        Item { Layout.fillWidth: true }
                        
                        Text {
                            text: mailListBridge ? mailListBridge.get_email(index).received_at : ""
                            font.family: root.monoFont
                            font.pixelSize: root.baseSize - 2
                            color: "#666666"
                        }
                    }
                    
                    // Preview
                    Text {
                        text: mailListBridge ? mailListBridge.get_email(index).preview : ""
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: "#cccccc"
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
                
                MouseArea {
                    id: delegateMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.showDetailView(index)
                    }
                }
            }
            
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                palette.mid: "#555555"
                palette.base: "#0d0d0d"
            }
        }
    }
    
    // Initialization: Load emails on creation
    Component.onCompleted: {
        if (mailListBridge) {
            mailListBridge.fetch_emails()
        }
    }
}
