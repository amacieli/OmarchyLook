import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#0d0d0d"

    required property var mailListBridge
    required property var settingsManager
    required property int selectedIndex
    
    signal backToList()
    
    // UI settings from SettingsManager
    property string monoFont: settingsManager ? settingsManager.get_font_family() : "monospace"
    property int baseSize: settingsManager ? settingsManager.get_base_size() : 10
    property int titleSize: settingsManager ? settingsManager.get_title_size() : 12
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 0
        spacing: 0
        
        // Header with back button and actions
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: "#1a1a1a"
            border.bottom.color: "#333333"
            border.bottom.width: 1
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12
                
                // Back button
                Rectangle {
                    Layout.preferredWidth: 60
                    Layout.preferredHeight: 32
                    color: "#0d0d0d"
                    border.color: backMouse.containsMouse ? "#9f8fff" : "#7c6af7"
                    border.width: 1
                    
                    Text {
                        anchors.centerIn: parent
                        text: "← Back"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: backMouse.containsMouse ? "#9f8fff" : "#7c6af7"
                    }
                    
                    MouseArea {
                        id: backMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.backToList()
                        }
                    }
                }
                
                // Subject (expandable on long text)
                Text {
                    text: mailListBridge.get_email(root.selectedIndex).subject
                    font.family: root.monoFont
                    font.pixelSize: root.titleSize
                    font.bold: true
                    color: "#7c6af7"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                
                Item { Layout.fillWidth: true }
                
                // Mark unread button
                Rectangle {
                    Layout.preferredWidth: 90
                    Layout.preferredHeight: 32
                    color: "#0d0d0d"
                    border.color: unreadBtnMouse.containsMouse ? "#9f8fff" : "#7c6af7"
                    border.width: 1
                    visible: mailListBridge.get_email(root.selectedIndex).is_read
                    
                    Text {
                        anchors.centerIn: parent
                        text: "Mark unread"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize - 2
                        color: unreadBtnMouse.containsMouse ? "#9f8fff" : "#7c6af7"
                    }
                    
                    MouseArea {
                        id: unreadBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            mailListBridge.mark_as_unread(root.selectedIndex)
                        }
                    }
                }
                
                // Delete button
                Rectangle {
                    Layout.preferredWidth: 60
                    Layout.preferredHeight: 32
                    color: "#0d0d0d"
                    border.color: deleteMouse.containsMouse ? "#f87171" : "#dc2626"
                    border.width: 1
                    
                    Text {
                        anchors.centerIn: parent
                        text: "Delete"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize - 2
                        color: deleteMouse.containsMouse ? "#f87171" : "#dc2626"
                    }
                    
                    MouseArea {
                        id: deleteMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            mailListBridge.delete_email(root.selectedIndex)
                            root.backToList()
                        }
                    }
                }
            }
        }
        
        // Email metadata
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            color: "#1a1a1a"
            border.bottom.color: "#333333"
            border.bottom.width: 1
            
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6
                
                // From
                RowLayout {
                    spacing: 12
                    
                    Text {
                        text: "From:"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        font.bold: true
                        color: "#7c6af7"
                        Layout.preferredWidth: 60
                    }
                    
                    Text {
                        text: mailListBridge.get_email(root.selectedIndex).from
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: "#e8e8e8"
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
                
                // Date
                RowLayout {
                    spacing: 12
                    
                    Text {
                        text: "Date:"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        font.bold: true
                        color: "#7c6af7"
                        Layout.preferredWidth: 60
                    }
                    
                    Text {
                        text: mailListBridge.get_email(root.selectedIndex).received_at
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: "#888888"
                        Layout.fillWidth: true
                    }
                }
                
                // Read status
                RowLayout {
                    spacing: 12
                    
                    Text {
                        text: "Status:"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        font.bold: true
                        color: "#7c6af7"
                        Layout.preferredWidth: 60
                    }
                    
                    Rectangle {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        radius: 10
                        color: mailListBridge.get_email(root.selectedIndex).is_read ? "#888888" : "#4ade80"
                        border.color: mailListBridge.get_email(root.selectedIndex).is_read ? "#666666" : "#22c55e"
                        border.width: 1
                        
                        Text {
                            anchors.centerIn: parent
                            text: mailListBridge.get_email(root.selectedIndex).is_read ? "✓" : "●"
                            font.pixelSize: 12
                            color: mailListBridge.get_email(root.selectedIndex).is_read ? "#0d0d0d" : "#0d0d0d"
                        }
                    }
                    
                    Text {
                        text: mailListBridge.get_email(root.selectedIndex).is_read ? "Read" : "Unread"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: mailListBridge.get_email(root.selectedIndex).is_read ? "#888888" : "#4ade80"
                    }
                }
            }
        }
        
        // Email body
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            Text {
                width: parent.width - 16
                text: mailListBridge.get_email_body(root.selectedIndex) || "No content"
                font.family: root.monoFont
                font.pixelSize: root.baseSize
                color: "#e8e8e8"
                wrapMode: Text.Wrap
                padding: 12
                textFormat: Text.PlainText
            }
        }
    }
}
