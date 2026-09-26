import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#0d0d0d"

    required property var mailListBridge
    required property var settingsManager
    
    // UI settings from SettingsManager
    property string monoFont: settingsManager ? settingsManager.get_font_family() : "monospace"
    property int baseSize: settingsManager ? settingsManager.get_base_size() : 10
    property int titleSize: settingsManager ? settingsManager.get_title_size() : 12
    
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 0
        spacing: 0
        
        // Top bar with title and controls
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            color: "#1a1a1a"
            border.bottom.color: "#333333"
            border.bottom.width: 1
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8
                
                Text {
                    text: "Inbox"
                    font.family: root.monoFont
                    font.pixelSize: root.titleSize
                    font.bold: true
                    color: "#7c6af7"
                }
                
                Item { Layout.fillWidth: true }
                
                // Refresh button
                Rectangle {
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 28
                    color: "#0d0d0d"
                    border.color: refreshMouse.containsMouse ? "#9f8fff" : "#7c6af7"
                    border.width: 1
                    
                    Text {
                        anchors.centerIn: parent
                        text: "⟲ Refresh"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: refreshMouse.containsMouse ? "#9f8fff" : "#7c6af7"
                    }
                    
                    MouseArea {
                        id: refreshMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            mailListBridge.fetch_emails()
                        }
                    }
                }
            }
        }
        
        // Mail list (scrollable)
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            
            Column {
                width: root.width - 16
                spacing: 1
                
                Repeater {
                    model: mailListBridge.email_count()
                    
                    Rectangle {
                        width: parent.width
                        height: 60
                        color: listItemMouse.containsMouse ? "#242424" : "#0d0d0d"
                        border.color: "#333333"
                        border.width: 1
                        
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 2
                            
                            // From and subject in one row
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                
                                Text {
                                    text: mailListBridge.get_email(index).from
                                    font.family: root.monoFont
                                    font.pixelSize: root.baseSize
                                    font.bold: true
                                    color: "#e8e8e8"
                                    elide: Text.ElideRight
                                    Layout.preferredWidth: 150
                                }
                                
                                Text {
                                    text: mailListBridge.get_email(index).subject
                                    font.family: root.monoFont
                                    font.pixelSize: root.baseSize
                                    color: mailListBridge.get_email(index).is_read ? "#888888" : "#e8e8e8"
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                
                                Text {
                                    text: mailListBridge.get_email(index).received_at
                                    font.family: root.monoFont
                                    font.pixelSize: root.baseSize
                                    color: "#888888"
                                    Layout.preferredWidth: 120
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                            
                            // Preview text
                            Text {
                                text: mailListBridge.get_email(index).preview
                                font.family: root.monoFont
                                font.pixelSize: root.baseSize
                                color: "#888888"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                        
                        MouseArea {
                            id: listItemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                console.log("Clicked email at index", index)
                                mailListBridge.mark_as_read(index)
                            }
                        }
                    }
                }
                
                // Empty state
                Text {
                    visible: mailListBridge.email_count() === 0
                    text: "No emails. Try refreshing."
                    font.family: root.monoFont
                    font.pixelSize: root.baseSize
                    color: "#888888"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height / 2
                }
            }
        }
    }
}
