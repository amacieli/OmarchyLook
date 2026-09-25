import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#1a1a1a"

    required property var authBridge

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 24
        width: 400

        // Logo / Title
        Text {
            text: "omarchy-look"
            font.family: "Inter"
            font.pixelSize: 32
            font.weight: Font.Bold
            color: "#e8e8e8"
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: "Outlook clone for Microsoft 365"
            font.family: "Inter"
            font.pixelSize: 14
            color: "#888888"
            Layout.alignment: Qt.AlignHCenter
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#333333"
        }

        // Login button
        Button {
            id: loginButton
            text: "Sign in with Microsoft"
            Layout.fillWidth: true
            Layout.preferredHeight: 48

            font.family: "Inter"
            font.pixelSize: 14
            font.weight: Font.Medium

            background: Rectangle {
                color: loginButton.hovered ? "#8c7dff" : "#7c6af7"
                radius: 6
                border.color: "#7c6af7"
                border.width: 1
            }

            contentItem: Text {
                text: loginButton.text
                font: loginButton.font
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: {
                loginButton.enabled = false
                loginButton.text = "Signing in..."
                authBridge.login()
            }

            Connections {
                target: authBridge
                function onLoginSucceeded() {
                    loginButton.enabled = true
                    loginButton.text = "Sign in with Microsoft"
                }
                function onLoginFailed(errorMsg) {
                    loginButton.enabled = true
                    loginButton.text = "Sign in with Microsoft"
                    errorText.text = errorMsg
                }
            }
        }

        // Error message
        Text {
            id: errorText
            text: ""
            font.family: "Inter"
            font.pixelSize: 12
            color: "#e05c5c"
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            visible: text.length > 0
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#333333"
        }

        // Help text
        Text {
            text: "First launch will open your browser for authentication.\nTokens are cached locally for offline access."
            font.family: "Inter"
            font.pixelSize: 12
            color: "#888888"
            Layout.alignment: Qt.AlignHCenter
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }
}
