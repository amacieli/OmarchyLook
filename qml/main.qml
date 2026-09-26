import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtCore

Window {
    id: root
    
    visible: true
    width: 1200
    height: 800
    title: "OmarchyLook"
    
    // Default settings (will be overridden by TOML config)
    property int baseFontSize: 14
    property real scaleFactor: 1.0
    property string monoFont: "JetBrainsMono Nerd Font"
    property int normalFontSize: Math.round(baseFontSize * scaleFactor)
    
    // Colors from defaults
    property color bgColor: "#0d0d0d"
    property color bgSurface: "#242424"
    property color borderColor: "#333333"
    property color textColor: "#e8e8e8"
    property color textSecondary: "#888888"
    property color accentColor: "#7c6af7"
    property color dangerColor: "#ff6b6b"
    property color successColor: "#51cf66"
    
    // Trigger file helper
    property var triggerFile: Item {
        function write(content) {
            console.log("Trigger file write called - attempting to create /tmp/omarchylook-trigger-device-flow")
            // Note: Pure QML cannot directly create files. The button will be clicked,
            // QML will print a log, and we'll manually test by creating the file with shell.
            // In production, this would use a native bridge (cxx-qt) or D-Bus to call Rust.
            return true
        }
    }
    
    // Deferred initialization timer — runs AFTER all bindings are settled
    Timer {
        id: initTimer
        interval: 10
        running: true
        repeat: false
        onTriggered: {
            loadSettingsFromTOML()
            loadAuthState()
        }
    }

    Component.onCompleted: {
        console.log("=== OmarchyLook QML Initialized ===")
    }

    function loadAuthState() {
        var configDir = typeof Qt.application.environment !== "undefined"
            ? Qt.application.environment("CONFIG_DIR")
            : ""
        if (configDir === "") configDir = "/home/adam/.config/omarchy-look"

        var authStateFile = configDir + "/auth_state.json"
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText)
                    root.isAuthenticated = data.is_authenticated === true
                    console.log("[Auth] Loaded auth state from disk: isAuthenticated =", root.isAuthenticated)
                } catch (e) {
                    console.warn("[Auth] Failed to parse auth_state.json:", e)
                    root.isAuthenticated = false
                }
            } else if (xhr.readyState === XMLHttpRequest.DONE) {
                console.log("[Auth] auth_state.json not found, defaulting to unauthenticated")
                root.isAuthenticated = false
            }
        }
        xhr.open("GET", "file://" + authStateFile)
        xhr.send()
    }
    
    function loadSettingsFromTOML() {
        // Read CONFIG_DIR environment variable set by Rust backend
        var configDir = typeof Qt.application.environment !== "undefined" 
            ? Qt.application.environment("CONFIG_DIR")
            : ""
        
        if (configDir === "") {
            console.warn("CONFIG_DIR not set, using defaults")
            return
        }
        
        var settingsFile = configDir + "/settings.toml"
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file://" + settingsFile)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    parseToml(xhr.responseText)
                    console.log("Loaded settings from:", settingsFile)
                } catch (e) {
                    console.error("Failed to parse settings.toml:", e)
                }
            }
        }
        xhr.send()
    }
    
    function parseToml(content) {
        var lines = content.split("\n")
        var currentSection = ""
        
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            
            // Skip comments and empty lines
            if (line === "" || line.startsWith("#")) continue
            
            // Parse section headers
            if (line.startsWith("[") && line.endsWith("]")) {
                currentSection = line.slice(1, -1).trim()
                continue
            }
            
            // Parse key=value pairs
            var match = line.match(/^([^=]+)\s*=\s*(.+)$/)
            if (!match) continue
            
            var key = match[1].trim()
            var value = match[2].trim().replace(/^["']|["']$/g, "")
            
            // Font section
            if (currentSection === "font") {
                if (key === "family") monoFont = value
                else if (key === "base_size") baseFontSize = parseInt(value)
                else if (key === "scale_factor") scaleFactor = parseFloat(value)
            }
            // Color section
            else if (currentSection === "color") {
                if (key === "bg_dark") bgColor = value
                else if (key === "bg_surface") bgSurface = value
                else if (key === "border") borderColor = value
                else if (key === "text_primary") textColor = value
                else if (key === "text_secondary") textSecondary = value
                else if (key === "accent_purple") accentColor = value
                else if (key === "danger_red") dangerColor = value
                else if (key === "success_green") successColor = value
            }
        }
        
        // Recalculate normalFontSize after loading
        normalFontSize = Math.round(baseFontSize * scaleFactor)
    }
    
    color: bgColor
    
    // Authentication state - checked only when user navigates to Settings
    property bool isAuthenticated: false
    
    // Current view state
    property string currentView: "mail"  // "mail" or "settings"
    property bool showAuthModal: false  // Show authentication modal when true
    
    // Main content area - always show AppShell (auth happens in Settings page only)
    Loader {
        id: mainLoader
        anchors.fill: parent
        sourceComponent: appShellComponent
    }
    
    // ===== App Shell Component =====
    Component {
        id: appShellComponent
        
        Rectangle {
            color: root.color
            
            RowLayout {
                anchors.fill: parent
                spacing: 0
                
                // Sidebar
                Rectangle {
                    Layout.preferredWidth: 200
                    Layout.fillHeight: true
                    color: "#1a1a1a"
                    border.width: 1
                    border.color: "#000000"  // Left and top
                    
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: "#7c6af7"  // Right border
                    }
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12
                        
                        Text {
                            text: "╔═ MENU ═╗"
                            font.family: root.monoFont
                            font.pixelSize: 11
                            color: root.accentColor
                        }
                        
                        // Menu items
                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            color: root.currentView === "mail" ? root.accentColor : root.color
                            border.color: root.currentView === "mail" ? root.accentColor : "#7c6af7"
                            border.width: 1
                            
                            Text {
                                anchors.centerIn: parent
                                text: "  📧 Mail  "
                                font.family: root.monoFont
                                font.pixelSize: 11
                                color: root.currentView === "mail" ? "#0d0d0d" : root.accentColor
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.currentView = "mail"
                            }
                        }
                        
                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            color: "#0d0d0d"
                            border.color: "#666666"
                            border.width: 1
                            
                            Text {
                                anchors.centerIn: parent
                                text: "  📅 Calendar  "
                                font.family: root.monoFont
                                font.pixelSize: 11
                                color: "#888888"
                            }
                        }
                        
                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            color: "#0d0d0d"
                            border.color: "#666666"
                            border.width: 1
                            
                            Text {
                                anchors.centerIn: parent
                                text: "  👥 Contacts  "
                                font.family: root.monoFont
                                font.pixelSize: 11
                                color: "#888888"
                            }
                        }
                        
                        // Settings button
                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            color: root.currentView === "settings" ? root.accentColor : "#0d0d0d"
                            border.color: root.currentView === "settings" ? root.accentColor : "#666666"
                            border.width: 1
                            
                            Text {
                                anchors.centerIn: parent
                                text: "  ⚙️ Settings  "
                                font.family: root.monoFont
                                font.pixelSize: 11
                                color: root.currentView === "settings" ? "#0d0d0d" : "#888888"
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.currentView = "settings"
                            }
                        }
                        
                        Item { Layout.fillHeight: true }
                    }
                }
                
                // Main content area
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: root.color
                    
                    Loader {
                        id: contentLoader
                        anchors.fill: parent
                        sourceComponent: {
                            switch(root.currentView) {
                                case "settings": return settingsViewComponent
                                default: return mailViewComponent
                            }
                        }
                    }
                }
                
                // Mail view component
                Component {
                    id: mailViewComponent
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8
                        
                        // Header
                        Text {
                            text: "╔═ Mail Module (Phase 3) ═╗"
                            font.family: root.monoFont
                            font.pixelSize: 12
                            color: root.accentColor
                            font.bold: true
                        }
                        
                        // Placeholder
                        Text {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: "Mail list will load here\n\n(Phase 3 integration in progress)"
                            font.family: root.monoFont
                            font.pixelSize: 11
                            color: root.textColor
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
                // Settings view component
                Component {
                    id: settingsViewComponent
                    
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12
                        
                        // Header
                        Text {
                            text: "╔═ Settings ═╗"
                            font.family: root.monoFont
                            font.pixelSize: 12
                            color: root.accentColor
                            font.bold: true
                        }
                        
                        // Account Settings section
                        Text {
                            text: "📧 Account Settings"
                            font.family: root.monoFont
                            font.pixelSize: 11
                            color: root.accentColor
                        }
                        
                        Rectangle {
                            Layout.fillWidth: true
                            height: Math.max(40, authBtnText.implicitHeight + 16)
                            color: root.isAuthenticated ? "#1a3a1a" : root.color
                            border.color: root.isAuthenticated ? "#51cf66" : root.accentColor
                            border.width: 1
                            
                            Text {
                                id: authBtnText
                                anchors.centerIn: parent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                text: root.isAuthenticated 
                                    ? "  ✓ Logged in with Microsoft - click to log out  " 
                                    : "  🔐 Log in with Microsoft  "
                                font.family: root.monoFont
                                font.pixelSize: 10
                                color: root.isAuthenticated ? "#51cf66" : root.accentColor
                                wrapMode: Text.WordWrap
                                horizontalAlignment: Text.AlignHCenter
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: {
                                    if (root.isAuthenticated) {
                                        parent.border.color = "#ff6b6b"
                                    }
                                }
                                onExited: {
                                    parent.border.color = root.isAuthenticated ? "#51cf66" : root.accentColor
                                }
                                onClicked: {
                                    if (root.isAuthenticated) {
                                        console.log("[Settings] Logout clicked")
                                        root.triggerLogout()
                                    } else {
                                        console.log("[Settings] Authenticate clicked")
                                        root.triggerDeviceFlow()
                                    }
                                }
                            }
                        }
                        
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }
    
    // ===== Device Flow State =====
    property string deviceUserCode: ""
    property string deviceVerificationUri: ""
    property int deviceExpiresIn: 0
    property int deviceSecondsRemaining: 0
    property string authErrorMessage: ""

    // ===== Trigger Functions =====
    // POST to Rust's local HTTP trigger server (localhost:27182)
    // This is the IPC mechanism since QML cannot write files directly

    function triggerDeviceFlow() {
        console.log("[Auth] Sending device flow trigger to Rust HTTP server")
        // Clear any previous state
        root.deviceUserCode = ""
        root.deviceVerificationUri = ""
        root.deviceExpiresIn = 0
        root.deviceSecondsRemaining = 0
        root.authErrorMessage = ""
        root.showAuthModal = true

        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    console.log("[Auth] Device flow trigger accepted by Rust backend")
                    deviceCodePoller.start()
                } else {
                    console.warn("[Auth] Trigger server returned:", xhr.status)
                    root.authErrorMessage = "Failed to start authentication (backend not ready?)"
                }
            }
        }
        xhr.open("POST", "http://127.0.0.1:27182/auth/login")
        xhr.send()

        // Start pollers regardless — device code poller will find the file when ready
        deviceCodePoller.start()
    }

    function triggerLogout() {
        console.log("[Auth] Sending logout trigger to Rust HTTP server")
        var xhr = new XMLHttpRequest()
        xhr.open("POST", "http://127.0.0.1:27182/auth/logout")
        xhr.send()
        // authStatePoller (always running) will detect the updated auth_state.json
    }

    // ===== Device Code Poller =====
    // Polls device_code.json every 500ms waiting for Rust to write the device code
    Timer {
        id: deviceCodePoller
        interval: 500
        repeat: true
        running: false

        onTriggered: {
            var configDir = typeof Qt.application.environment !== "undefined"
                ? Qt.application.environment("CONFIG_DIR")
                : ""
            if (configDir === "") configDir = "/home/adam/.config/omarchy-look"

            var xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        if (data.user_code && data.user_code !== root.deviceUserCode) {
                            root.deviceUserCode = data.user_code
                            root.deviceVerificationUri = data.verification_uri || "https://microsoft.com/devicelogin"
                            root.deviceExpiresIn = data.expires_in || 900
                            root.deviceSecondsRemaining = data.expires_in || 900
                            console.log("[Auth] Device code received:", root.deviceUserCode)
                            // Start the countdown timer
                            deviceCountdownTimer.restart()
                        }
                    } catch(e) { /* file not ready yet */ }
                }
            }
            xhr.open("GET", "file://" + configDir + "/device_code.json")
            xhr.send()
        }
    }

    // ===== Auth State Poller =====
    // Polls auth_state.json to detect successful login or logout
    Timer {
        id: authStatePoller
        interval: 500
        repeat: true
        running: true   // Always running so logout is detected instantly too

        onTriggered: {
            var configDir = typeof Qt.application.environment !== "undefined"
                ? Qt.application.environment("CONFIG_DIR")
                : ""
            if (configDir === "") configDir = "/home/adam/.config/omarchy-look"

            var xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        var wasAuthenticated = root.isAuthenticated
                        root.isAuthenticated = data.is_authenticated === true

                        if (data.error) {
                            root.authErrorMessage = data.error
                            console.log("[Auth] Error from backend:", data.error)
                        }

                        // Auth just succeeded
                        if (!wasAuthenticated && root.isAuthenticated) {
                            console.log("[Auth] ✅ Authentication succeeded — closing modal")
                            root.showAuthModal = false
                            deviceCodePoller.stop()
                            deviceCountdownTimer.stop()
                            root.deviceUserCode = ""
                            root.authErrorMessage = ""
                        }

                        // Logout just happened
                        if (wasAuthenticated && !root.isAuthenticated) {
                            console.log("[Auth] 🔓 Logged out")
                        }
                    } catch(e) { /* file not ready yet */ }
                }
            }
            xhr.open("GET", "file://" + configDir + "/auth_state.json")
            xhr.send()
        }
    }

    // ===== Countdown Timer =====
    // Decrements deviceSecondsRemaining every second
    Timer {
        id: deviceCountdownTimer
        interval: 1000
        repeat: true
        running: false

        onTriggered: {
            if (root.deviceSecondsRemaining > 0) {
                root.deviceSecondsRemaining -= 1
            } else {
                // Code expired
                root.authErrorMessage = "Device code expired. Please try again."
                deviceCodePoller.stop()
                deviceCountdownTimer.stop()
            }
        }
    }

    // ===== Authentication Modal Overlay =====
    Rectangle {
        visible: root.showAuthModal
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.85)
        z: 1000

        // Click backdrop to cancel
        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.showAuthModal = false
                deviceCodePoller.stop()
                deviceCountdownTimer.stop()
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 520)
            height: authModalContent.implicitHeight + 40
            color: "#1a1a1a"
            border.color: "#7c6af7"
            border.width: 2

            // Prevent backdrop click from propagating through the dialog
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: authModalContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 20
                spacing: 14

                // Title
                Text {
                    Layout.fillWidth: true
                    text: "╔═ Microsoft Authentication ═╗"
                    font.family: root.monoFont
                    font.pixelSize: 13
                    font.bold: true
                    color: "#7c6af7"
                    horizontalAlignment: Text.AlignHCenter
                }

                // Status area: waiting for code vs code received
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: root.deviceUserCode === "" && root.authErrorMessage === ""

                    Text {
                        Layout.fillWidth: true
                        text: "⏳ Initiating device authentication..."
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: "#888888"
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Waiting for Microsoft to send a code..."
                        font.family: root.monoFont
                        font.pixelSize: 10
                        color: "#555555"
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Device code display (shown once code arrives)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: root.deviceUserCode !== "" && root.authErrorMessage === ""

                    // Step 1
                    Text {
                        Layout.fillWidth: true
                        text: "1. Open this URL in your browser:"
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: "#c0c0c0"
                    }

                    // URL row with copy hint
                    Rectangle {
                        Layout.fillWidth: true
                        height: 34
                        color: "#0d0d0d"
                        border.color: "#555555"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            text: root.deviceVerificationUri
                            font.family: root.monoFont
                            font.pixelSize: 11
                            color: "#7c6af7"
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    // Step 2
                    Text {
                        Layout.fillWidth: true
                        text: "2. Enter this code when prompted:"
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: "#c0c0c0"
                    }

                    // Big code display
                    Rectangle {
                        Layout.fillWidth: true
                        height: 60
                        color: "#0d0d0d"
                        border.color: "#7c6af7"
                        border.width: 2

                        Text {
                            anchors.centerIn: parent
                            text: root.deviceUserCode
                            font.family: root.monoFont
                            font.pixelSize: 28
                            font.bold: true
                            font.letterSpacing: 6
                            color: "#e8e8e8"
                        }
                    }

                    // Countdown
                    Text {
                        Layout.fillWidth: true
                        text: {
                            var m = Math.floor(root.deviceSecondsRemaining / 60)
                            var s = root.deviceSecondsRemaining % 60
                            var ss = s < 10 ? "0" + s : "" + s
                            return "⏱ Code expires in " + m + ":" + ss
                        }
                        font.family: root.monoFont
                        font.pixelSize: 10
                        color: root.deviceSecondsRemaining < 60 ? "#ff6b6b" : "#888888"
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Waiting confirmation
                    Text {
                        Layout.fillWidth: true
                        text: "⏳ Waiting for you to authenticate in browser..."
                        font.family: root.monoFont
                        font.pixelSize: 10
                        color: "#555555"
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Error state
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: root.authErrorMessage !== ""

                    Text {
                        Layout.fillWidth: true
                        text: "❌ " + root.authErrorMessage
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: "#ff6b6b"
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // Retry button
                    Rectangle {
                        Layout.fillWidth: true
                        height: 36
                        color: "#0d0d0d"
                        border.color: retryMouse.containsMouse ? "#9f8fff" : "#7c6af7"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "  🔄 Try Again  "
                            font.family: root.monoFont
                            font.pixelSize: 10
                            color: parent.border.color
                        }

                        MouseArea {
                            id: retryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.triggerDeviceFlow()
                        }
                    }
                }

                // Close / Cancel button
                Rectangle {
                    Layout.fillWidth: true
                    height: 36
                    color: "#0d0d0d"
                    border.color: modalCloseMouse.containsMouse ? "#ff8787" : "#444444"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "  ✕ Cancel  "
                        font.family: root.monoFont
                        font.pixelSize: 10
                        color: modalCloseMouse.containsMouse ? "#ff8787" : "#666666"
                    }

                    MouseArea {
                        id: modalCloseMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.showAuthModal = false
                            deviceCodePoller.stop()
                            deviceCountdownTimer.stop()
                        }
                    }
                }
            }
        }
    }
}
