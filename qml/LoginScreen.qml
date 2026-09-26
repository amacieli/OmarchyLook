import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    color: "#0d0d0d"

    required property var authBridge
    property var settingsManagerRef: typeof settingsManager !== 'undefined' ? settingsManager : null

    // Use system monospace font (respects terminal font settings)
    property string monoFont: settingsManagerRef ? settingsManagerRef.get_font_family() : "monospace"
    property int baseSize: settingsManagerRef ? settingsManagerRef.get_base_size() : 10
    property int titleSize: settingsManagerRef ? settingsManagerRef.get_title_size() : 12
    property int hintSize: settingsManagerRef ? settingsManagerRef.get_hint_size() : 8

    ColumnLayout {
        anchors.centerIn: parent
        anchors.margins: 20
        spacing: 12
        width: Math.min(parent.width - 40, 600)

        // Listen for settings changes to update font sizes
        Connections {
            target: root.settingsManagerRef
            function onFontSettingsChanged() {
                console.log("LoginScreen.qml: Font settings changed, updating properties")
                root.monoFont = settingsManagerRef ? settingsManagerRef.get_font_family() : "monospace"
                root.baseSize = settingsManagerRef ? settingsManagerRef.get_base_size() : 10
                root.titleSize = settingsManagerRef ? settingsManagerRef.get_title_size() : 12
                root.hintSize = settingsManagerRef ? settingsManagerRef.get_hint_size() : 8
            }
        }

        // Top border
        Text {
            text: "┌─────────────────────────────────────┐"
            font.family: root.monoFont
            font.pixelSize: root.baseSize
            color: "#7c6af7"
            Layout.alignment: Qt.AlignHCenter
        }

        // Logo / Title
        Text {
            text: "  OmarchyLook"
            font.family: root.monoFont
            font.pixelSize: root.baseSize
            font.weight: Font.Bold
            color: "#7c6af7"
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: "Omarchy Mail"
            font.family: root.monoFont
            font.pixelSize: root.baseSize
            color: "#888888"
            Layout.alignment: Qt.AlignHCenter
        }

        // Divider
        Text {
            text: "├─────────────────────────────────────┤"
            font.family: root.monoFont
            font.pixelSize: root.baseSize
            color: "#7c6af7"
            Layout.alignment: Qt.AlignHCenter
        }

        // Description
        Text {
            text: "  Authenticate with your Microsoft 365 account\n  using Device Flow authentication."
            font.family: root.monoFont
            font.pixelSize: root.baseSize
            color: "#cccccc"
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
        }

        // Spacer
        Item {
            Layout.preferredHeight: 8
        }

        // Login button (TUI style)
        Rectangle {
            id: loginButton
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            color: "#0d0d0d"
            border.color: loginMouseArea.containsMouse ? "#9f8fff" : "#7c6af7"
            border.width: 1

            property bool isPressed: false

            Text {
                anchors.centerIn: parent
                text: "  ▶ Sign in with Microsoft  "
                font.family: root.monoFont
                font.pixelSize: root.baseSize
                color: loginMouseArea.containsMouse ? "#9f8fff" : "#7c6af7"
            }

            MouseArea {
                id: loginMouseArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    loginButton.isPressed = true
                    parent.children[0].text = "  ⟳ Signing in...  "
                    authBridge.login()
                    // Start polling for device code file
                    deviceCodePoller.start()
                }
            }

            Connections {
                target: authBridge
                function onLoginSucceeded() {
                    console.log("Login succeeded signal received")
                    deviceCodeDialog.close()
                    loginButton.isPressed = false
                    loginButton.children[0].text = "  ▶ Sign in with Microsoft  "
                }
                function onLoginFailed(errorMsg) {
                    console.log("Login failed signal received:", errorMsg)
                    deviceCodeDialog.close()
                    loginButton.isPressed = false
                    loginButton.children[0].text = "  ▶ Sign in with Microsoft  "
                    errorMessage.text = errorMsg || "Login failed. Please try again."
                }
                function onDeviceCodeReceived(userCode, verificationUri) {
                    console.log("Device code received:", userCode)
                    deviceCodeDialog.userCode = userCode
                    deviceCodeDialog.verificationUri = verificationUri
                    deviceCodeDialog.open()
                }
            }
        }

        // Error message
        Text {
            id: errorMessage
            text: ""
            font.family: root.monoFont
            font.pixelSize: root.baseSize
            color: "#ff6b6b"
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            visible: text.length > 0
        }

        // Bottom border
        Text {
            text: "└─────────────────────────────────────┘"
            font.family: root.monoFont
            font.pixelSize: root.baseSize
            color: "#7c6af7"
            Layout.alignment: Qt.AlignHCenter
        }
    }

    // Timer to poll for device code file (since we use static qmlscene, not cxx-qt FFI bridges)
    Timer {
        id: deviceCodePoller
        interval: 500  // Poll every 500ms
        repeat: true
        running: false

        onTriggered: {
            try {
                // Call Rust backend to read device_code.json
                const deviceCodeJson = authBridge.getDeviceCode()
                if (deviceCodeJson && deviceCodeJson.length > 0) {
                    const deviceCode = JSON.parse(deviceCodeJson)
                    if (deviceCode.user_code && deviceCode.verification_uri) {
                        deviceCodeDialog.userCode = deviceCode.user_code
                        deviceCodeDialog.verificationUri = deviceCode.verification_uri
                        deviceCodeDialog.expiresIn = deviceCode.expires_in || 900
                        deviceCodeDialog.open()
                        deviceCodePoller.stop()  // Stop polling once dialog is shown
                    }
                }
            } catch (e) {
                // Keep polling until device code appears
                console.log("Waiting for device code...", e)
            }
        }
    }

    // Device Code Dialog (TUI style)
    Popup {
        id: deviceCodeDialog
        anchors.centerIn: parent
        width: 500
        height: 380
        modal: true
        focus: true

        property string userCode: ""
        property string verificationUri: ""
        property int expiresIn: 900
        property int secondsRemaining: 900

        background: Rectangle {
            color: "#0d0d0d"
            border.color: "#7c6af7"
            border.width: 1
        }

        // Countdown timer for expiration
        Timer {
            id: expirationCountdown
            interval: 1000  // Update every second
            repeat: true
            running: deviceCodeDialog.visible

            onTriggered: {
                deviceCodeDialog.secondsRemaining--;
                if (deviceCodeDialog.secondsRemaining <= 0) {
                    expirationCountdown.stop();
                    deviceCodeDialog.close();
                    errorMessage.text = "Device code expired. Please try again.";
                }
            }
        }

        onOpened: {
            expirationCountdown.start();
            deviceCodeDialog.secondsRemaining = deviceCodeDialog.expiresIn;
        }

        onClosed: {
            expirationCountdown.stop()
            deviceCodePoller.stop()
            // Clean up the device code file via Rust backend
            try {
                authBridge.clearDeviceCode()
            } catch (e) {
                // Ignore cleanup errors
                console.log("Error clearing device code:", e)
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            // Title
            Text {
                text: "┌─ Device Code Authentication ─┐"
                font.family: root.monoFont
                font.pixelSize: root.baseSize
                color: "#7c6af7"
                Layout.alignment: Qt.AlignHCenter
            }

            // Instructions
            Text {
                text: "1. Go to: https://microsoft.com/devicelogin"
                font.family: root.monoFont
                font.pixelSize: root.baseSize
                color: "#cccccc"
                Layout.fillWidth: true
            }

            Text {
                text: "2. Enter this code:"
                font.family: root.monoFont
                font.pixelSize: root.baseSize
                color: "#cccccc"
                Layout.fillWidth: true
            }

            // Device code display (large, centered, copyable)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                color: "#1a1a1a"
                border.color: "#7c6af7"
                border.width: 1

                ColumnLayout {
                    anchors.centerIn: parent
                    anchors.margins: 8
                    spacing: 4
                    width: parent.width - 16

                    Text {
                        id: deviceCodeText
                        text: deviceCodeDialog.userCode
                        font.family: root.monoFont
                        font.pixelSize: root.titleSize
                        font.bold: true
                        color: "#7c6af7"
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "Click to copy"
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: "#888888"
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        authBridge.copyToClipboard(deviceCodeDialog.userCode)
                        copyFeedback.text = "✓ Copied!"
                        copyTimer.start()
                    }
                }
            }

            // Expiration countdown
            Text {
                text: "Expires in: " + deviceCodeDialog.secondsRemaining + "s"
                font.family: root.monoFont
                font.pixelSize: root.hintSize
                color: deviceCodeDialog.secondsRemaining < 60 ? "#ff6b6b" : "#888888"
                Layout.alignment: Qt.AlignHCenter
            }

            // Copy feedback
            Text {
                id: copyFeedback
                text: ""
                font.family: root.monoFont
                font.pixelSize: root.baseSize
                color: "#51cf66"
                Layout.alignment: Qt.AlignHCenter
            }

            Timer {
                id: copyTimer
                interval: 2000
                onTriggered: copyFeedback.text = ""
            }

            // Spacing
            Item {
                Layout.preferredHeight: 4
            }

            // Buttons row
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // Copy button (TUI style)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    color: "#0d0d0d"
                    border.color: copyBtnMouse.containsMouse ? "#9f8fff" : "#7c6af7"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "  ◆ Copy Code  "
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: copyBtnMouse.containsMouse ? "#9f8fff" : "#7c6af7"
                    }

                    MouseArea {
                        id: copyBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            authBridge.copyToClipboard(deviceCodeDialog.userCode)
                            copyFeedback.text = "✓ Copied to clipboard!"
                            copyTimer.start()
                        }
                    }
                }

                // Close button (TUI style)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    color: "#0d0d0d"
                    border.color: closeBtnMouse.containsMouse ? "#ff8787" : "#7c6af7"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "  ✕ Close  "
                        font.family: root.monoFont
                        font.pixelSize: root.baseSize
                        color: closeBtnMouse.containsMouse ? "#ff8787" : "#7c6af7"
                    }

                    MouseArea {
                        id: closeBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: deviceCodeDialog.close()
                    }
                }
            }

            // Bottom border
            Text {
                text: "└──────────────────────────────────┘"
                font.family: root.monoFont
                font.pixelSize: root.baseSize
                color: "#7c6af7"
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
