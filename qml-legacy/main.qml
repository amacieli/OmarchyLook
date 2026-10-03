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
        // Deferred load — HTTP server needs ~1s to be ready
        Qt.callLater(function() {
            Qt.createQmlObject(
                'import QtQuick 2.15; Timer { interval: 1500; running: true; repeat: false; onTriggered: { root.loadUiSettings(); root.loadFolders() } }',
                root, "initTimer"
            )
        })
    }

    function loadAuthState() {
        var configDir = typeof Qt.application.environment !== "undefined"
            ? Qt.application.environment("CONFIG_DIR")
            : ""
        if (configDir === "") configDir = "/home/adam/.config/omarchylook"

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
    
    color: "#000000"

    // Authentication state - checked only when user navigates to Settings
    property bool isAuthenticated: false

    // Current view state
    property string currentView: "mail"
    property bool showAuthModal: false

    // Navigation state
    // focus: "nav" = left bar active, "folder" = folder bar, "msg" = message pane
    property string focusPane: "nav"
    property int navIndex: 0   // which nav item the › is on (0=mail,1=cal,2=contacts,3=tasks,4=settings)
    property bool navOnToggle: false  // whether › is on the collapse/expand toggle row
    property int msgIndex: 0   // which message row the › is on
    property bool sidebarExpanded: true  // expand/collapse sidebar

    // Nav items definition (main items + settings pinned at bottom)
    // Mail uses the envelope icon (\uf0e0) as its prefix icon
    property var navItems: [
        { icon: "\uf0e0", label: "Mail",      view: "mail"     },
        { icon: "\uf073", label: "Calendar",  view: "calendar" },
        { icon: "\uf0c0", label: "People",    view: "contacts" },
        { icon: "\uf0ae", label: "Tasks",     view: "tasks"    },
        { icon: "\uf013", label: "Settings",  view: "settings" }
    ]

    // Folder pane state
    property int folderIndex: 0       // which folder row › is on
    property string selectedFolderId: ""  // folder_id passed to /messages

    // Folder data — populated by async XHR on load + folder pane activation
    ListModel { id: folderModel }

    // Persist sidebar state to settings.toml via HTTP
    onSidebarExpandedChanged: {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", "http://127.0.0.1:27182/settings/sidebar_expanded", true)
        xhr.send(root.sidebarExpanded ? "true" : "false")
    }

    function loadUiSettings() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "http://127.0.0.1:27182/settings/ui", true)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var s = JSON.parse(xhr.responseText)
                    if (typeof s.sidebar_expanded === "boolean") {
                        root.sidebarExpanded = s.sidebar_expanded
                    }
                } catch(e) {
                    console.log("[Settings] Parse error:", e)
                }
            }
        }
        xhr.send()
    }

    function loadFolders() {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "http://127.0.0.1:27182/folders", true)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var folders = JSON.parse(xhr.responseText)
                    folderModel.clear()
                    for (var i = 0; i < folders.length; i++) {
                        folderModel.append(folders[i])
                    }
                    // Default to first folder (Inbox) if none selected
                    if (selectedFolderId === "" && folderModel.count > 0) {
                        selectedFolderId = folderModel.get(0).id
                    }
                } catch(e) {
                    console.log("[Folders] Parse error:", e)
                }
            }
        }
        xhr.send()
    }

    // Main content area
    Loader {
        id: mainLoader
        anchors.fill: parent
        sourceComponent: appShellComponent
    }

    // ===== Global keyboard handler =====
    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            // ── Nav pane focused ──────────────────────────────────────
            if (root.focusPane === "nav") {
                if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                    if (root.navOnToggle) {
                        // Toggle row → first nav item
                        root.navOnToggle = false
                        root.navIndex = 0
                        root.currentView = root.navItems[0].view
                    } else {
                        root.navIndex = Math.min(root.navIndex + 1, root.navItems.length - 1)
                        root.currentView = root.navItems[root.navIndex].view
                    }
                    event.accepted = true
                } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                    if (root.navOnToggle) {
                        // Already at top — stay
                    } else if (root.navIndex === 0) {
                        // First nav item → toggle row
                        root.navOnToggle = true
                    } else {
                        root.navIndex = Math.max(root.navIndex - 1, 0)
                        root.currentView = root.navItems[root.navIndex].view
                    }
                    event.accepted = true
                } else if (event.key === Qt.Key_L || event.key === Qt.Key_Return || event.key === Qt.Key_Space) {
                    if (root.navOnToggle) {
                        root.sidebarExpanded = !root.sidebarExpanded
                    } else if (root.currentView === "mail") {
                        root.focusPane = "folder"
                        root.folderIndex = 0
                    } else {
                        root.focusPane = "msg"
                        root.msgIndex = 0
                    }
                    event.accepted = true
                } else if (event.key === Qt.Key_S) {
                    if (!root.navOnToggle) {
                        if (root.currentView === "mail") {
                            root.focusPane = "folder"
                            root.folderIndex = 0
                        } else {
                            root.focusPane = "msg"
                            root.msgIndex = 0
                        }
                    }
                    event.accepted = true
                }
            // ── Folder pane focused ───────────────────────────────────
            } else if (root.focusPane === "folder") {
                if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                    root.folderIndex = Math.min(root.folderIndex + 1, folderModel.count - 1)
                    // Immediately filter messages to this folder
                    if (folderModel.count > 0) {
                        root.selectedFolderId = folderModel.get(root.folderIndex).id
                    }
                    event.accepted = true
                } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                    root.folderIndex = Math.max(root.folderIndex - 1, 0)
                    if (folderModel.count > 0) {
                        root.selectedFolderId = folderModel.get(root.folderIndex).id
                    }
                    event.accepted = true
                } else if (event.key === Qt.Key_L || event.key === Qt.Key_Return) {
                    // Select folder and move to messages
                    if (folderModel.count > 0) {
                        root.selectedFolderId = folderModel.get(root.folderIndex).id
                    }
                    root.focusPane = "msg"
                    root.msgIndex = 0
                    event.accepted = true
                } else if (event.key === Qt.Key_H || event.key === Qt.Key_Escape) {
                    root.focusPane = "nav"
                    event.accepted = true
                } else if (event.key === Qt.Key_S) {
                    // s cycles: folder → msg
                    if (folderModel.count > 0) {
                        root.selectedFolderId = folderModel.get(root.folderIndex).id
                    }
                    root.focusPane = "msg"
                    root.msgIndex = 0
                    event.accepted = true
                }
            // ── Message pane focused ──────────────────────────────────
            } else if (root.focusPane === "msg") {
                if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
                    root.msgIndex = root.msgIndex + 1
                    event.accepted = true
                } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
                    root.msgIndex = Math.max(root.msgIndex - 1, 0)
                    event.accepted = true
                } else if (event.key === Qt.Key_H || event.key === Qt.Key_Escape) {
                    root.focusPane = "folder"
                    event.accepted = true
                } else if (event.key === Qt.Key_S) {
                    // s cycles: msg → nav
                    root.focusPane = "nav"
                    event.accepted = true
                }
            }
        }
    }

    // ===== App Shell Component =====
    Component {
        id: appShellComponent

        Rectangle {
            color: "#000000"
            // Forward key events to global handler
            Component.onCompleted: keyHandler.forceActiveFocus()

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // ── Sidebar ───────────────────────────────────────────
                Rectangle {
                    id: sidebar
                    Layout.preferredWidth: root.sidebarExpanded ? 180 : 42
                    Layout.fillHeight: true
                    color: "#000000"
                    clip: true

                    Behavior on Layout.preferredWidth { NumberAnimation { duration: 150 } }

                    // Subtle right separator
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: "#1a1a1a"
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.topMargin: 10
                        anchors.bottomMargin: 12
                        spacing: 0

                        // ── Collapse/expand toggle row ────────────────
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36

                            property bool hasFocus: root.focusPane === "nav" && root.navOnToggle

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                spacing: 0

                                // › selector (1-char left margin, consistent with nav items)
                                Text {
                                    text: parent.parent.hasFocus ? "›" : " "
                                    font.family: root.monoFont
                                    font.pixelSize: 13
                                    color: root.accentColor
                                    Layout.preferredWidth: 12
                                }

                                // Filled triangle: ▶ collapsed, ▼ expanded
                                Text {
                                    text: root.sidebarExpanded ? "\u25bc" : "\u25b6"
                                    font.family: root.monoFont
                                    font.pixelSize: 10
                                    color: parent.parent.hasFocus ? root.accentColor : "#333333"
                                    Layout.preferredWidth: 16
                                }

                                Item { Layout.fillWidth: true }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.sidebarExpanded = !root.sidebarExpanded
                                    root.navOnToggle = true
                                    root.focusPane = "nav"
                                    keyHandler.forceActiveFocus()
                                }
                            }
                        }

                        // Spacer
                        Item { Layout.preferredHeight: 4 }

                        // ── Main nav items (Mail, Calendar, People, Tasks) ─
                        Repeater {
                            model: 4  // indices 0-3
                            delegate: Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 34

                                property bool isActive: root.navIndex === index
                                property bool hasFocus: root.focusPane === "nav" && isActive

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    spacing: 0

                                    // › — always 1-char wide left margin
                                    Text {
                                        text: hasFocus ? "›" : " "
                                        font.family: root.monoFont
                                        font.pixelSize: 13
                                        color: root.accentColor
                                        Layout.preferredWidth: 12
                                    }

                                    // Icon
                                    Text {
                                        text: root.navItems[index].icon
                                        font.family: root.monoFont
                                        font.pixelSize: 15
                                        color: isActive ? root.accentColor : "#444444"
                                        Layout.preferredWidth: 20
                                    }

                                    // Label — only when expanded
                                    Text {
                                        visible: root.sidebarExpanded
                                        opacity: root.sidebarExpanded ? 1 : 0
                                        text: " " + root.navItems[index].label
                                        font.family: root.monoFont
                                        font.pixelSize: 12
                                        color: isActive ? root.accentColor : "#444444"
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        Behavior on opacity { NumberAnimation { duration: 100 } }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.navIndex = index
                                        root.currentView = root.navItems[index].view
                                        root.focusPane = "nav"
                                        root.navOnToggle = false
                                        keyHandler.forceActiveFocus()
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        // ── Settings — pinned to bottom ────────────────
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34

                            property bool isActive: root.navIndex === 4
                            property bool hasFocus: root.focusPane === "nav" && isActive

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                spacing: 0

                                Text {
                                    text: parent.parent.hasFocus ? "›" : " "
                                    font.family: root.monoFont
                                    font.pixelSize: 13
                                    color: root.accentColor
                                    Layout.preferredWidth: 12
                                }

                                Text {
                                    text: root.navItems[4].icon
                                    font.family: root.monoFont
                                    font.pixelSize: 15
                                    color: parent.parent.isActive ? root.accentColor : "#444444"
                                    Layout.preferredWidth: 20
                                }

                                Text {
                                    visible: root.sidebarExpanded
                                    opacity: root.sidebarExpanded ? 1 : 0
                                    text: " " + root.navItems[4].label
                                    font.family: root.monoFont
                                    font.pixelSize: 12
                                    color: parent.parent.isActive ? root.accentColor : "#444444"
                                    Layout.fillWidth: true
                                    Behavior on opacity { NumberAnimation { duration: 100 } }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.navIndex = 4
                                    root.currentView = "settings"
                                    root.focusPane = "nav"
                                    keyHandler.forceActiveFocus()
                                }
                            }
                        }
                    }
                }

                // ── Folder bar (mail view only) ───────────────────────
                Rectangle {
                    id: folderBar
                    visible: root.currentView === "mail"
                    Layout.preferredWidth: root.currentView === "mail" ? 180 : 0
                    Layout.fillHeight: true
                    color: "#000000"
                    clip: true

                    Behavior on Layout.preferredWidth { NumberAnimation { duration: 120 } }

                    // Right separator
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: "#1a1a1a"
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.topMargin: 10
                        anchors.bottomMargin: 8
                        spacing: 0

                        // Header
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                spacing: 0
                                Text {
                                    text: "Folders"
                                    font.family: root.monoFont
                                    font.pixelSize: 10
                                    color: "#333333"
                                    Layout.fillWidth: true
                                }
                                // Refresh icon
                                Text {
                                    text: "\uf021"  // refresh
                                    font.family: root.monoFont
                                    font.pixelSize: 10
                                    color: "#333333"
                                    rightPadding: 8
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.loadFolders()
                                    }
                                }
                            }
                        }

                        // Folder list
                        ListView {
                            id: folderListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            model: folderModel
                            clip: true
                            interactive: false  // keyboard-driven; mouse via delegate

                            delegate: Item {
                                width: folderListView.width
                                height: 28

                                property bool isFocused: root.focusPane === "folder" && root.folderIndex === index
                                property bool isSelected: model.id === root.selectedFolderId

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    spacing: 0

                                    // › cursor (1-char wide)
                                    Text {
                                        text: isFocused ? "›" : " "
                                        font.family: root.monoFont
                                        font.pixelSize: 12
                                        color: root.accentColor
                                        Layout.preferredWidth: 12
                                    }

                                    // Folder name
                                    Text {
                                        text: model.display_name
                                        font.family: root.monoFont
                                        font.pixelSize: 11
                                        color: isSelected ? root.accentColor : "#555555"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    // Unread count badge (if > 0)
                                    Text {
                                        visible: model.unread_item_count > 0
                                        text: model.unread_item_count > 99 ? "99+" : model.unread_item_count.toString()
                                        font.family: root.monoFont
                                        font.pixelSize: 9
                                        color: "#444444"
                                        rightPadding: 6
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.folderIndex = index
                                        root.selectedFolderId = model.id
                                        root.focusPane = "msg"
                                        root.msgIndex = 0
                                        keyHandler.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }

                    // Load folders: deferred 2s after init (server must be ready),
                    // and whenever auth state flips to true
                    Timer {
                        id: folderInitTimer
                        interval: 2000
                        running: false
                        repeat: false
                        onTriggered: root.loadFolders()
                    }

                    Connections {
                        target: root
                        function onIsAuthenticatedChanged() {
                            if (root.isAuthenticated && folderModel.count === 0) {
                                root.loadFolders()
                            }
                        }
                    }

                    onVisibleChanged: {
                        if (visible && folderModel.count === 0) {
                            root.loadFolders()
                        }
                    }

                    Component.onCompleted: {
                        if (root.currentView === "mail") {
                            folderInitTimer.start()
                        }
                    }
                }

                // ── Main content area ─────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "#000000"

                    Loader {
                        id: contentLoader
                        anchors.fill: parent
                        sourceComponent: {
                            switch(root.currentView) {
                                case "settings": return settingsViewComponent
                                case "calendar": return calendarViewComponent
                                case "contacts": return peopleViewComponent
                                case "tasks":    return tasksViewComponent
                                default:         return mailViewComponent
                            }
                        }
                    }
                }
                
                // ── Mail view component ───────────────────────────────────
                Component {
                    id: mailViewComponent

                    // Two-panel mail shell: list on left, reading pane on right
                    RowLayout {
                        spacing: 0

                        // ── Message list panel ────────────────────────────────
                        Rectangle {
                            Layout.preferredWidth: 360
                            Layout.fillHeight: true
                            color: "#000000"

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 0

                                // ── list header ───────────────────────────────
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 38
                                    color: "#000000"

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width; height: 1; color: "#111111"
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 8
                                        spacing: 0

                                        Text {
                                            text: "\uf0e0  "
                                            font.family: root.monoFont
                                            font.pixelSize: 12
                                            color: root.focusPane === "msg" ? root.accentColor : "#3a3a3a"
                                        }

                                        Text {
                                            text: (function() {
                                                for (var i = 0; i < folderModel.count; i++) {
                                                    if (folderModel.get(i).id === root.selectedFolderId)
                                                        return folderModel.get(i).display_name
                                                }
                                                return "Inbox"
                                            })()
                                            font.family: root.monoFont
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: root.focusPane === "msg" ? root.accentColor : "#555555"
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            id: inboxStatusText
                                            text: ""
                                            font.family: root.monoFont
                                            font.pixelSize: 9
                                            color: "#2a2a2a"
                                        }

                                        Text {
                                            text: " ↻"
                                            font.family: root.monoFont
                                            font.pixelSize: 12
                                            color: refreshMsgMouse.containsMouse ? root.accentColor : "#2a2a2a"
                                            rightPadding: 4
                                            MouseArea {
                                                id: refreshMsgMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    keyHandler.forceActiveFocus()
                                                    inboxLoader.loadMessages()
                                                }
                                            }
                                        }
                                    }
                                }

                                // ── message list ──────────────────────────────
                                ListView {
                                    id: inboxList
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: 0
                                    currentIndex: root.focusPane === "msg" ? root.msgIndex : -1

                                    onCountChanged: {
                                        if (root.msgIndex >= count && count > 0)
                                            root.msgIndex = count - 1
                                    }

                                    model: ListModel { id: inboxModel }

                                    // empty state
                                    Text {
                                        anchors.centerIn: parent
                                        visible: inboxModel.count === 0
                                        text: inboxStatusText.text.length > 0 && inboxStatusText.text !== "…"
                                              ? inboxStatusText.text : "no messages"
                                        font.family: root.monoFont
                                        font.pixelSize: 11
                                        color: "#2a2a2a"
                                    }

                                    delegate: Rectangle {
                                        id: msgRow
                                        width: inboxList.width
                                        height: 54
                                        color: "#000000"

                                        property bool isActive: root.focusPane === "msg" && root.msgIndex === index

                                        // active selection bar (left edge)
                                        Rectangle {
                                            visible: parent.isActive
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            width: 2
                                            color: root.accentColor
                                        }

                                        // unread accent: left fill strip
                                        Rectangle {
                                            visible: !model.is_read && !parent.isActive
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            width: 2
                                            color: Qt.rgba(0.49, 0.42, 0.97, 0.45)
                                        }

                                        // bottom separator
                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width; height: 1; color: "#0d0d0d"
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 8
                                            anchors.topMargin: 7
                                            anchors.bottomMargin: 7
                                            spacing: 6

                                            // › cursor
                                            Text {
                                                text: parent.parent.isActive ? "›" : " "
                                                font.family: root.monoFont
                                                font.pixelSize: 14
                                                color: root.accentColor
                                                Layout.preferredWidth: 12
                                            }

                                            // unread dot
                                            Rectangle {
                                                width: 5; height: 5; radius: 3
                                                color: model.is_read ? "transparent" : root.accentColor
                                                Layout.preferredWidth: 8
                                                Layout.alignment: Qt.AlignVCenter
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                spacing: 3

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 0

                                                    // sender
                                                    Text {
                                                        text: model.from_name !== "" ? model.from_name : model.from_email
                                                        font.family: root.monoFont
                                                        font.pixelSize: 12
                                                        font.bold: !model.is_read
                                                        color: model.is_read ? "#555555" : root.textColor
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }

                                                    // date
                                                    Text {
                                                        text: {
                                                            var s = model.received_at || ""
                                                            if (s.length >= 10) {
                                                                var d = new Date(s)
                                                                var now = new Date()
                                                                if (d.toDateString() === now.toDateString())
                                                                    return s.substring(11, 16)
                                                                return s.substring(5, 10)
                                                            }
                                                            return s.substring(0, 10)
                                                        }
                                                        font.family: root.monoFont
                                                        font.pixelSize: 10
                                                        color: "#2a2a2a"
                                                    }
                                                }

                                                // subject
                                                Text {
                                                    text: model.subject || "(no subject)"
                                                    font.family: root.monoFont
                                                    font.pixelSize: 11
                                                    color: model.is_read ? "#333333" : "#888888"
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.focusPane = "msg"
                                                root.msgIndex = index
                                                keyHandler.forceActiveFocus()
                                            }
                                        }
                                    }
                                }
                            }

                            // async data loader
                            Item {
                                id: inboxLoader

                                function loadMessages() {
                                    inboxStatusText.text = "…"
                                    var xhr = new XMLHttpRequest()
                                    xhr.onreadystatechange = function() {
                                        if (xhr.readyState !== XMLHttpRequest.DONE) return
                                        if (xhr.status === 200) {
                                            try {
                                                var messages = JSON.parse(xhr.responseText)
                                                inboxModel.clear()
                                                for (var i = 0; i < messages.length; i++)
                                                    inboxModel.append(messages[i])
                                                inboxStatusText.text = messages.length + ""
                                            } catch(e) {
                                                inboxStatusText.text = "err"
                                            }
                                        } else {
                                            inboxStatusText.text = xhr.status === 0 ? "" : "e" + xhr.status
                                        }
                                    }
                                    var url = "http://127.0.0.1:27182/messages"
                                    if (root.selectedFolderId !== "")
                                        url += "?folder_id=" + encodeURIComponent(root.selectedFolderId)
                                    xhr.open("GET", url)
                                    xhr.send()
                                }

                                Component.onCompleted: loadMessages()
                            }

                            // reload on folder change
                            Connections {
                                target: root
                                function onSelectedFolderIdChanged() { inboxLoader.loadMessages() }
                            }
                        }

                        // vertical divider
                        Rectangle {
                            Layout.fillHeight: true
                            width: 1; color: "#111111"
                        }

                        // ── Reading pane ──────────────────────────────────────
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "#000000"

                            // no selection placeholder
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 6
                                visible: root.msgIndex < 0 || inboxModel.count === 0

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "\uf0e0"
                                    font.family: root.monoFont
                                    font.pixelSize: 32
                                    color: "#1a1a1a"
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "select a message"
                                    font.family: root.monoFont
                                    font.pixelSize: 11
                                    color: "#1a1a1a"
                                }
                            }

                            // reading pane content
                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 0
                                visible: root.msgIndex >= 0 && inboxModel.count > root.msgIndex

                                property var msg: inboxModel.count > root.msgIndex && root.msgIndex >= 0
                                                  ? inboxModel.get(root.msgIndex) : null

                                // ── message header ────────────────────────────
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: readingHeader.implicitHeight + 20
                                    color: "#000000"

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width; height: 1; color: "#111111"
                                    }

                                    ColumnLayout {
                                        id: readingHeader
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 16
                                        anchors.topMargin: 12
                                        spacing: 5

                                        // subject
                                        Text {
                                            text: (parent.parent.parent.msg || {}).subject || "(no subject)"
                                            font.family: root.monoFont
                                            font.pixelSize: 15
                                            font.bold: true
                                            color: root.textColor
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            // sender name chip
                                            Rectangle {
                                                color: Qt.rgba(0.49, 0.42, 0.97, 0.12)
                                                border.color: Qt.rgba(0.49, 0.42, 0.97, 0.35)
                                                border.width: 1
                                                height: 20
                                                width: senderChipText.implicitWidth + 14

                                                Text {
                                                    id: senderChipText
                                                    anchors.centerIn: parent
                                                    text: {
                                                        var m = parent.parent.parent.parent.msg || {}
                                                        return m.from_name || m.from_email || ""
                                                    }
                                                    font.family: root.monoFont
                                                    font.pixelSize: 10
                                                    color: root.accentColor
                                                }
                                            }

                                            Text {
                                                text: {
                                                    var m = parent.parent.parent.msg || {}
                                                    var s = m.from_email || ""
                                                    return s.length > 0 ? "‹" + s + "›" : ""
                                                }
                                                font.family: root.monoFont
                                                font.pixelSize: 10
                                                color: "#333333"
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: {
                                                    var m = parent.parent.parent.msg || {}
                                                    var s = m.received_at || ""
                                                    if (s.length >= 16) return s.substring(0, 16).replace("T", "  ")
                                                    return s.substring(0, 10)
                                                }
                                                font.family: root.monoFont
                                                font.pixelSize: 10
                                                color: "#2a2a2a"
                                            }
                                        }

                                        // to / cc line
                                        Text {
                                            visible: text.length > 0
                                            text: {
                                                var m = parent.parent.parent.msg || {}
                                                var to = m.to_recipients || m.to || ""
                                                return to.length > 0 ? "to  " + to : ""
                                            }
                                            font.family: root.monoFont
                                            font.pixelSize: 10
                                            color: "#2a2a2a"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                // ── action bar ────────────────────────────────
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    color: "#000000"

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width; height: 1; color: "#0d0d0d"
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        spacing: 6

                                        // Reply
                                        Rectangle {
                                            height: 22; width: replyLbl.implicitWidth + 18
                                            color: "transparent"
                                            border.color: replyActMouse.containsMouse ? root.accentColor : "#1e1e1e"
                                            border.width: 1

                                            Text {
                                                id: replyLbl
                                                anchors.centerIn: parent
                                                text: "\uf112  reply"
                                                font.family: root.monoFont
                                                font.pixelSize: 10
                                                color: replyActMouse.containsMouse ? root.accentColor : "#3a3a3a"
                                            }
                                            MouseArea {
                                                id: replyActMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                            }
                                        }

                                        // Forward
                                        Rectangle {
                                            height: 22; width: fwdLbl.implicitWidth + 18
                                            color: "transparent"
                                            border.color: fwdActMouse.containsMouse ? root.accentColor : "#1e1e1e"
                                            border.width: 1

                                            Text {
                                                id: fwdLbl
                                                anchors.centerIn: parent
                                                text: "\uf064  forward"
                                                font.family: root.monoFont
                                                font.pixelSize: 10
                                                color: fwdActMouse.containsMouse ? root.accentColor : "#3a3a3a"
                                            }
                                            MouseArea {
                                                id: fwdActMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        // read/unread toggle
                                        Text {
                                            property var msg: inboxModel.count > root.msgIndex && root.msgIndex >= 0
                                                              ? inboxModel.get(root.msgIndex) : null
                                            text: (msg && msg.is_read) ? "\uf2e5  mark unread" : "\uf2e7  mark read"
                                            font.family: root.monoFont
                                            font.pixelSize: 10
                                            color: markReadMouse.containsMouse ? root.accentColor : "#2a2a2a"
                                            MouseArea {
                                                id: markReadMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                            }
                                        }
                                    }
                                }

                                // ── body ──────────────────────────────────────
                                ScrollView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                                    Text {
                                        width: parent.parent.width - 32
                                        anchors.left: parent.left
                                        anchors.leftMargin: 16
                                        topPadding: 14
                                        bottomPadding: 24

                                        text: {
                                            var m = parent.parent.parent.parent.msg || {}
                                            return m.body_preview || m.body || m.snippet || ""
                                        }
                                        font.family: root.monoFont
                                        font.pixelSize: 12
                                        color: "#aaaaaa"
                                        wrapMode: Text.WordWrap
                                        lineHeight: 1.5
                                        textFormat: Text.PlainText
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Calendar view component ──────────────────────────────
                Component {
                    id: calendarViewComponent
                    CalendarView {
                        monoFont:     root.monoFont
                        accentColor:  root.accentColor
                        successColor: root.successColor
                        dangerColor:  root.dangerColor
                        textColor:    root.textColor
                    }
                }

                // ── People view component ────────────────────────────────
                Component {
                    id: peopleViewComponent
                    PeopleView {
                        monoFont:     root.monoFont
                        accentColor:  root.accentColor
                        successColor: root.successColor
                        dangerColor:  root.dangerColor
                        textColor:    root.textColor
                    }
                }

                // ── Tasks view component ─────────────────────────────────
                Component {
                    id: tasksViewComponent
                    TasksView {
                        monoFont:     root.monoFont
                        accentColor:  root.accentColor
                        successColor: root.successColor
                        dangerColor:  root.dangerColor
                        textColor:    root.textColor
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
            if (configDir === "") configDir = "/home/adam/.config/omarchylook"

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
            if (configDir === "") configDir = "/home/adam/.config/omarchylook"

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
