import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Ui
import "../common"

// PeopleView — header (view dropdown, sort dropdown) above a contact list.
// Every contact row has the same height: a name column, and a contact-info column with
// three single-line, non-wrapping lines (emails / phones with type / addresses). Lines
// that are too long are cut with an ellipsis.
// Data source: http://127.0.0.1:27182/contacts?view=all|favorites|lists&sort=first|last|company|recent
Rectangle {
    id: root

    // PageUp/PageDown: the list has no keyboard cursor, so scroll it a screenful
    // (less a little overlap), clamped to its ends.
    function pageScroll(dir) {
        var max = Math.max(0, list.contentHeight - list.height)
        list.contentY = Math.max(0, Math.min(max, list.contentY + dir * list.height * 0.9))
    }
    color: "#000000"

    // ── theme props forwarded from AppShell ───────────────────────
    property string monoFont:     "JetBrainsMono Nerd Font"
    property color  accentColor:  "#7c6af7"
    property color  successColor: "#51cf66"
    property color  dangerColor:  "#ff6b6b"
    property color  textColor:    "#e8e8e8"
    property color  dimColor:     "#555555"
    property color  veryDimColor: "#2a2a2a"

    // "all" | "favorites" | "lists"   and   "first" | "last" | "company" | "recent"
    // (AppShell keeps both across tab switches)
    property string viewMode: "all"
    property string sortKey:  "first"

    property var  contacts: []
    property bool loading: false
    property bool loaded: false
    property int  _serial: 0

    readonly property int rowHeight: 64
    readonly property int lineHeight: 16
    readonly property int sectionHeight: 28

    readonly property var viewOptions: [
        { value: "all",       label: "All contacts" },
        { value: "favorites", label: "Favorites" },
        { value: "lists",     label: "Contact lists" }
    ]
    readonly property var sortOptions: [
        { value: "first",   label: "First name" },
        { value: "last",    label: "Last name" },
        { value: "company", label: "Company" },
        { value: "recent",  label: "Recently added" }
    ]

    // ── line builders ─────────────────────────────────────────────
    function emailLine(c)   { return (c.emails || []).join("; ") }
    function phoneLine(c)   { return (c.phones || []).map(function(p) { return p.kind + ": " + p.number }).join("  ·  ") }
    function addressLine(c) { return (c.addresses || []).map(function(a) { return a.kind + ": " + a.text }).join("  |  ") }
    function subtitle(c) {
        var parts = []
        if (c.job_title) parts.push(c.job_title)
        if (c.company)   parts.push(c.company)
        return parts.join(" · ")
    }

    // ── data ──────────────────────────────────────────────────────
    function load() {
        var serial = ++_serial
        loading = true
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || serial !== root._serial) return
            root.loading = false
            if (xhr.status === 200) {
                try { root.contacts = JSON.parse(xhr.responseText); root.loaded = true }
                catch (e) { console.log("[People] parse error:", e) }
            }
        }
        xhr.open("GET", "http://127.0.0.1:27182/contacts?view=" + viewMode + "&sort=" + sortKey)
        xhr.send()
    }

    function setFavorite(id, value) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) root.load()
        }
        xhr.open("POST", "http://127.0.0.1:27182/contacts/favorite?id=" + encodeURIComponent(id) + "&value=" + value)
        xhr.send()
    }

    onViewModeChanged: load()
    onSortKeyChanged:  load()
    Component.onCompleted: load()

    // the initial sync fills the address book over time — keep the list fresh
    Timer { interval: 20000; running: true; repeat: true; onTriggered: root.load() }

    // ── layout ────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // header bar
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            color: "#000000"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#111111" }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                Dropdown {
                    Layout.preferredWidth: 170
                    Layout.alignment: Qt.AlignVCenter
                    showLabel: false
                    options: root.viewOptions
                    value: root.viewMode
                    onChanged: function(v) { root.viewMode = v }
                }

                Text {
                    text: "Sort by"
                    font.family: root.monoFont; font.pixelSize: 11
                    color: root.dimColor
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 8
                }

                Dropdown {
                    Layout.preferredWidth: 170
                    Layout.alignment: Qt.AlignVCenter
                    showLabel: false
                    options: root.sortOptions
                    value: root.sortKey
                    onChanged: function(v) { root.sortKey = v }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.contacts.length + (root.contacts.length === 1 ? " contact" : " contacts")
                    font.family: root.monoFont; font.pixelSize: 11
                    color: root.dimColor
                }

                Text {
                    visible: root.loading
                    text: "⟳"
                    font.family: root.monoFont; font.pixelSize: 12
                    color: root.dimColor
                    RotationAnimation on rotation {
                        from: 0; to: 360; duration: 1200
                        loops: Animation.Infinite; running: root.loading
                    }
                }
            }
        }

        // column headings
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            color: "#000000"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#111111" }
            Text {
                x: 44; anchors.verticalCenter: parent.verticalCenter
                text: "NAME"
                font.family: root.monoFont; font.pixelSize: 10; font.letterSpacing: 1
                color: root.dimColor
            }
            Text {
                x: 44 + nameColumnWidth + 12; anchors.verticalCenter: parent.verticalCenter
                text: "CONTACT INFO"
                font.family: root.monoFont; font.pixelSize: 10; font.letterSpacing: 1
                color: root.dimColor
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.contacts
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ThemedScrollBar {}

            // "Contact lists": group by folder (the backend already orders by folder)
            section.property: root.viewMode === "lists" ? "folder_name" : ""
            section.criteria: ViewSection.FullString
            section.delegate: Rectangle {
                required property string section
                width: list.width
                height: root.sectionHeight
                color: "#050505"
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: section
                    font.family: root.monoFont; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1
                    color: root.accentColor
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#111111" }
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0 && root.loaded
                text: root.viewMode === "favorites" ? "no favorites yet — click ☆ on a contact" : "no contacts"
                font.family: root.monoFont; font.pixelSize: 11
                color: root.veryDimColor
            }

            delegate: Rectangle {
                id: row
                required property var modelData
                width: list.width
                height: root.rowHeight     // identical for every contact
                color: rowHover.hovered ? "#0a0a0a" : "transparent"
                HoverHandler { id: rowHover }

                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#111111" }

                // favorite star
                Text {
                    x: 12; y: 10
                    text: row.modelData.is_favorite ? "\uf005" : "\uf006"
                    font.family: root.monoFont; font.pixelSize: 14
                    color: row.modelData.is_favorite ? "#ffd43b"
                         : starMouse.containsMouse ? root.accentColor : root.veryDimColor
                    MouseArea {
                        id: starMouse
                        anchors.fill: parent; anchors.margins: -6
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.setFavorite(row.modelData.id, !row.modelData.is_favorite)
                    }
                }

                // name column
                Column {
                    x: 44; y: 10
                    width: nameColumnWidth
                    spacing: 3
                    Text {
                        width: parent.width
                        text: row.modelData.display_name
                        elide: Text.ElideRight; wrapMode: Text.NoWrap; maximumLineCount: 1
                        font.family: root.monoFont; font.pixelSize: 13; font.bold: true
                        color: root.textColor
                    }
                    Text {
                        width: parent.width
                        text: root.subtitle(row.modelData)
                        elide: Text.ElideRight; wrapMode: Text.NoWrap; maximumLineCount: 1
                        font.family: root.monoFont; font.pixelSize: 10
                        color: root.dimColor
                    }
                }

                // contact info column: emails / phones / addresses — one line each, never wrapped
                Column {
                    x: 44 + nameColumnWidth + 12; y: 8
                    width: row.width - x - 12
                    spacing: 0
                    InfoLine { icon: "\uf0e0"; value: root.emailLine(row.modelData) }
                    InfoLine { icon: "\uf095"; value: root.phoneLine(row.modelData) }
                    InfoLine { icon: "\uf3c5"; value: root.addressLine(row.modelData) }
                }
            }
        }
    }

    readonly property real nameColumnWidth: Math.max(180, Math.min(320, width * 0.28))

    // One fixed-height, single-line field. Overflow is cut with an ellipsis, never wrapped.
    component InfoLine: Item {
        property string icon: ""
        property string value: ""
        width: parent.width
        height: root.lineHeight
        Text {
            id: ic
            width: 18
            text: parent.icon
            font.family: root.monoFont; font.pixelSize: 10
            color: root.veryDimColor
            verticalAlignment: Text.AlignVCenter
            height: parent.height
        }
        Text {
            anchors.left: ic.right
            anchors.right: parent.right
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: parent.value
            wrapMode: Text.NoWrap
            maximumLineCount: 1
            elide: Text.ElideRight
            font.family: root.monoFont; font.pixelSize: 11
            color: root.textColor
        }
    }
}
