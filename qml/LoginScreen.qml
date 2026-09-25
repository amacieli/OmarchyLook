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
                    console.log("Login succeeded signal received")
                    deviceCodeDialog.close()
                    loginButton.enabled = true
                    loginButton.text = "Sign in with Microsoft"
                }
                function onLoginFailed(errorMsg) {
                    console.log("Login failed signal received:", errorMsg)
                    deviceCodeDialog.close()
                    loginButton.enabled = true
                    loginButton.text = "Sign in with Microsoft"
                    errorMessage.text = errorMsg || "Login failed. Please try again."
                }
                function onDeviceCodeReceived(userCode, verificationUri) {
                    console.log("Device code received:", userCode)
                    // Display device code dialog
                    deviceCodeDialog.userCode = userCode
                    deviceCodeDialog.verificationUri = verificationUri
                    deviceCodeDialog.open()
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

    // Device Code Dialog
    Popup {
        id: deviceCodeDialog
        anchors.centerIn: parent
        width: 500
        height: 350
        background: Rectangle {
            color: "#1e1e1e"
            radius: 12
            border.color: "#333333"
            border.width: 1
        }

        property string userCode: ""
        property string verificationUri: ""

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            // Title
            Text {
                text: "🔐 Device Authentication"
                font.family: "Inter"
                font.pixelSize: 18
                font.weight: Font.Bold
                color: "#ffffff"
                Layout.fillWidth: true
            }

            // Instructions
            Text {
                text: "1. Open this URL on any device (phone, tablet, or another computer):"
                font.family: "Inter"
                font.pixelSize: 13
                color: "#cccccc"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            // Verification URI
            Rectangle {
                Layout.fillWidth: true
                height: 44
                color: "#2d2d2d"
                radius: 6
                border.color: "#444444"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    Text {
                        text: deviceCodeDialog.verificationUri
                        font.family: "Courier"
                        font.pixelSize: 12
                        color: "#7c6af7"
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Button {
                        text: "Copy"
                        font.pixelSize: 11
                        onClicked: {
                            authBridge.copyToClipboard(deviceCodeDialog.verificationUri)
                            text = "Copied!"
                            enabled = false
                            timer.start()
                        }
                    }

                    Timer {
                        id: timer
                        interval: 2000
                        onTriggered: {
                            parent.children[1].text = "Copy"
                            parent.children[1].enabled = true
                        }
                    }
                }
            }

            // Instructions 2
            Text {
                text: "2. Enter this code when prompted:"
                font.family: "Inter"
                font.pixelSize: 13
                color: "#cccccc"
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            // Device Code Display
            Rectangle {
                Layout.fillWidth: true
                height: 60
                color: "#2d2d2d"
                radius: 6
                border.color: "#7c6af7"
                border.width: 2

                Text {
                    anchors.centerIn: parent
                    text: deviceCodeDialog.userCode
                    font.family: "Courier"
                    font.pixelSize: 28
                    font.weight: Font.Bold
                    color: "#7c6af7"
                }
            }

            // Waiting message
            Text {
                text: "Waiting for authentication..."
                font.family: "Inter"
                font.pixelSize: 12
                color: "#888888"
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 8
            }

            Layout.fillHeight: true

            // Close button
            Button {
                text: "Cancel"
                Layout.fillWidth: true
                Layout.preferredHeight: 40

                onClicked: deviceCodeDialog.close()
            }
        }
    }
}
