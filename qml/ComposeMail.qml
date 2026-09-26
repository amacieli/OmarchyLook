import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#0d0d0d"

    required property var composeBridge
    required property var settingsManager

    property string monoFont: settingsManager ? settingsManager.get_font_family() : "monospace"
    property int baseSize: settingsManager ? settingsManager.get_base_size() : 10
    property int titleSize: settingsManager ? settingsManager.get_title_size() : 12

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // Top bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            color: "#1a1a1a"
            border.color: "#333333"
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 8

                Text {
                    text: "Compose Email"
                    font.family: root.monoFont
                    font.pixelSize: root.titleSize
                    font.bold: true
                    color: "#7c6af7"
                }

                Item { Layout.fillWidth: true }

                // Close button
                Rectangle {
                    Layout.preferredWidth: 70
                    Layout.preferredHeight: 24
                    color: "#0d0d0d"
                    border.color: closeBtnMouse.containsMouse ? "#ff8787" : "#7c6af7"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "✕ Close"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: closeBtnMouse.containsMouse ? "#ff8787" : "#7c6af7"
                    }

                    MouseArea {
                        id: closeBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.visible = false
                    }
                }
            }
        }

        // To field
        Text {
            text: "To:"
            font.family: root.monoFont
            font.pixelSize: root.baseSize
            color: "#888888"
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            color: "#1a1a1a"
            border.color: toInputArea.activeFocus ? "#7c6af7" : "#333333"
            border.width: 1

            TextInput {
                id: toInput
                anchors.fill: parent
                anchors.margins: 6
                font.family: root.monoFont
                font.pixelSize: root.baseSize
                color: "#e8e8e8"
                selectByMouse: true
                placeholderText: "recipient@example.com"
                placeholderTextColor: "#555555"

                onTextChanged: {
                    composeBridge.set_to(text)
                }
            }

            MouseArea {
                id: toInputArea
                anchors.fill: parent
                onPressed: {
                    mouse.accepted = false
                    toInput.forceActiveFocus()
                }
            }
        }

        // Subject field
        Text {
            text: "Subject:"
            font.family: root.monoFont
            font.pixelSize: root.baseSize
            color: "#888888"
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            color: "#1a1a1a"
            border.color: subjectInputArea.activeFocus ? "#7c6af7" : "#333333"
            border.width: 1

            TextInput {
                id: subjectInput
                anchors.fill: parent
                anchors.margins: 6
                font.family: root.monoFont
                font.pixelSize: root.baseSize
                color: "#e8e8e8"
                selectByMouse: true
                placeholderText: "Email subject"
                placeholderTextColor: "#555555"

                onTextChanged: {
                    composeBridge.set_subject(text)
                }
            }

            MouseArea {
                id: subjectInputArea
                anchors.fill: parent
                onPressed: {
                    mouse.accepted = false
                    subjectInput.forceActiveFocus()
                }
            }
        }

        // Body field
        Text {
            text: "Body:"
            font.family: root.monoFont
            font.pixelSize: root.baseSize
            color: "#888888"
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#1a1a1a"
            border.color: bodyInputArea.activeFocus ? "#7c6af7" : "#333333"
            border.width: 1

            ScrollView {
                anchors.fill: parent

                TextEdit {
                    id: bodyInput
                    width: parent.width
                    font.family: root.monoFont
                    font.pixelSize: root.baseSize
                    color: "#e8e8e8"
                    selectByMouse: true
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.Wrap
                    padding: 6

                    onTextChanged: {
                        composeBridge.set_body(text)
                    }
                }
            }

            MouseArea {
                id: bodyInputArea
                anchors.fill: parent
                onPressed: {
                    mouse.accepted = false
                    bodyInput.forceActiveFocus()
                }
            }
        }

        // Bottom buttons row
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Item { Layout.fillWidth: true }

            // Clear button
            Rectangle {
                Layout.preferredWidth: 100
                Layout.preferredHeight: 32
                color: "#0d0d0d"
                border.color: clearBtnMouse.containsMouse ? "#9f8fff" : "#7c6af7"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "  ✖ Clear  "
                    font.family: root.monoFont
                    font.pixelSize: root.baseSize
                    color: clearBtnMouse.containsMouse ? "#9f8fff" : "#7c6af7"
                }

                MouseArea {
                    id: clearBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        toInput.clear()
                        subjectInput.clear()
                        bodyInput.clear()
                        composeBridge.clear()
                    }
                }
            }

            // Send button
            Rectangle {
                Layout.preferredWidth: 100
                Layout.preferredHeight: 32
                color: "#0d0d0d"
                border.color: sendBtnMouse.containsMouse ? "#51cf66" : "#7c6af7"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "  ✓ Send  "
                    font.family: root.monoFont
                    font.pixelSize: root.baseSize
                    color: sendBtnMouse.containsMouse ? "#51cf66" : "#7c6af7"
                }

                MouseArea {
                    id: sendBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (composeBridge.send()) {
                            sendStatus.text = "✓ Email sent!"
                            sendTimer.start()
                            toInput.clear()
                            subjectInput.clear()
                            bodyInput.clear()
                        } else {
                            sendStatus.text = "✕ Failed to send"
                            sendTimer.start()
                        }
                    }
                }
            }
        }

        // Send status message
        Text {
            id: sendStatus
            text: ""
            font.family: root.monoFont
            font.pixelSize: root.baseSize
            color: "#51cf66"
            Layout.alignment: Qt.AlignHCenter
            visible: text.length > 0
        }

        Timer {
            id: sendTimer
            interval: 3000
            onTriggered: sendStatus.text = ""
        }
    }
}
