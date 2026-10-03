import QtQuick
import QtQuick.Layouts

// PeopleView — contacts list + detail panel, omarchy aesthetic
// Data source: http://127.0.0.1:27182/contacts
Rectangle {
    id: root
    color: "#000000"

    property string monoFont:     "JetBrainsMono Nerd Font"
    property color  accentColor:  "#7c6af7"
    property color  successColor: "#51cf66"
    property color  dangerColor:  "#ff6b6b"
    property color  textColor:    "#e8e8e8"
    property color  dimColor:     "#555555"
    property color  veryDimColor: "#2a2a2a"

    property var contacts: []
    property int selectedIndex: -1
    property bool loading: true
    property string searchQuery: ""

    // derive initials for avatar
    function initials(name) {
        if (!name || name.length === 0) return "?"
        var parts = name.trim().split(/\s+/)
        if (parts.length >= 2)
            return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
        return name[0].toUpperCase()
    }

    // consistent accent hue per contact (deterministic from name)
    function avatarColor(name) {
        var palette = [
            "#7c6af7", "#51cf66", "#ff6b6b", "#ffd43b",
            "#74c0fc", "#f783ac", "#a9e34b", "#63e6be"
        ]
        if (!name || name.length === 0) return palette[0]
        var h = 0
        for (var i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) & 0xffff
        return palette[h % palette.length]
    }

    function filteredContacts() {
        if (root.searchQuery.trim() === "") return root.contacts
        var q = root.searchQuery.toLowerCase()
        return root.contacts.filter(function(c) {
            return (c.display_name || "").toLowerCase().indexOf(q) >= 0
                || (c.email || "").toLowerCase().indexOf(q) >= 0
        })
    }

    function loadContacts() {
        loading = true
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            loading = false
            if (xhr.status === 200) {
                try { root.contacts = JSON.parse(xhr.responseText) }
                catch(e) { root.contacts = [] }
            } else {
                root.contacts = []
            }
        }
        xhr.open("GET", "http://127.0.0.1:27182/contacts")
        xhr.send()
    }

    // ── layout ────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── LEFT: search + contact list ───────────────────────────
        ColumnLayout {
            Layout.preferredWidth: 280
            Layout.fillHeight: true
            spacing: 0

            // search bar
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
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    Text {
                        text: "\uf002"  // search icon
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: root.dimColor
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        font.family: root.monoFont
                        font.pixelSize: 12
                        color: root.textColor
                        selectedTextColor: "#000000"
                        selectionColor: root.accentColor
                        selectByMouse: true

                        // placeholder
                        Text {
                            visible: searchInput.text.length === 0
                            text: "search contacts"
                            font.family: root.monoFont
                            font.pixelSize: 12
                            color: root.veryDimColor
                        }

                        onTextChanged: root.searchQuery = text
                    }

                    // clear button
                    Text {
                        visible: searchInput.text.length > 0
                        text: "✕"
                        font.family: root.monoFont
                        font.pixelSize: 10
                        color: clearMouse.containsMouse ? root.dangerColor : root.dimColor
                        MouseArea {
                            id: clearMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: searchInput.text = ""
                        }
                    }
                }
            }

            // header
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                color: "#000000"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    Text {
                        text: "People"
                        font.family: root.monoFont
                        font.pixelSize: 9
                        color: "#2a2a2a"
                        Layout.fillWidth: true
                    }
                    Text {
                        visible: !root.loading
                        text: root.filteredContacts().length.toString()
                        font.family: root.monoFont
                        font.pixelSize: 9
                        color: "#2a2a2a"
                    }
                }
            }

            // list
            ListView {
                id: contactList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 0
                model: root.filteredContacts()

                // loading / empty
                Text {
                    anchors.centerIn: parent
                    visible: root.loading
                    text: "loading…"
                    font.family: root.monoFont
                    font.pixelSize: 11
                    color: root.veryDimColor
                }
                Text {
                    anchors.centerIn: parent
                    visible: !root.loading && contactList.count === 0
                    text: "no contacts"
                    font.family: root.monoFont
                    font.pixelSize: 11
                    color: root.veryDimColor
                }

                delegate: Rectangle {
                    width: contactList.width
                    height: 50
                    color: "#000000"

                    property bool isSelected: index === root.selectedIndex

                    // selected left bar
                    Rectangle {
                        visible: parent.isSelected
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 2
                        color: root.accentColor
                    }

                    // bottom separator
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width; height: 1; color: "#0d0d0d"
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: parent.isSelected ? 12 : 14
                        anchors.rightMargin: 10
                        anchors.topMargin: 6
                        anchors.bottomMargin: 6
                        spacing: 10

                        // avatar circle
                        Rectangle {
                            width: 32; height: 32; radius: 16
                            color: root.avatarColor(modelData.display_name || "")
                            opacity: 0.85

                            Text {
                                anchors.centerIn: parent
                                text: root.initials(modelData.display_name || "")
                                font.family: root.monoFont
                                font.pixelSize: 11
                                font.bold: true
                                color: "#000000"
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 2

                            Text {
                                text: modelData.display_name || "Unknown"
                                font.family: root.monoFont
                                font.pixelSize: 12
                                font.bold: parent.parent.parent.isSelected
                                color: parent.parent.parent.isSelected ? root.accentColor : root.textColor
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: modelData.email || modelData.job_title || ""
                                font.family: root.monoFont
                                font.pixelSize: 10
                                color: root.dimColor
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedIndex = index
                    }
                }
            }
        }

        // vertical divider
        Rectangle {
            Layout.fillHeight: true
            width: 1; color: "#111111"
        }

        // ── RIGHT: contact detail ─────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#000000"

            // nothing selected
            Text {
                anchors.centerIn: parent
                visible: root.selectedIndex < 0 || root.filteredContacts().length === 0
                text: "select a contact"
                font.family: root.monoFont
                font.pixelSize: 12
                color: root.veryDimColor
            }

            // detail view
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 0
                visible: root.selectedIndex >= 0 && root.filteredContacts().length > root.selectedIndex

                property var contact: root.selectedIndex >= 0 && root.filteredContacts().length > root.selectedIndex
                                      ? root.filteredContacts()[root.selectedIndex] : null

                // avatar + name header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 18

                    // big avatar
                    Rectangle {
                        width: 64; height: 64; radius: 32
                        color: root.avatarColor((parent.parent.contact || {}).display_name || "")
                        opacity: 0.85

                        Text {
                            anchors.centerIn: parent
                            text: root.initials((parent.parent.parent.contact || {}).display_name || "")
                            font.family: root.monoFont
                            font.pixelSize: 22
                            font.bold: true
                            color: "#000000"
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: (parent.parent.parent.contact || {}).display_name || "Unknown"
                            font.family: root.monoFont
                            font.pixelSize: 18
                            font.bold: true
                            color: root.textColor
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }

                        Text {
                            visible: text.length > 0
                            text: (parent.parent.parent.contact || {}).job_title || ""
                            font.family: root.monoFont
                            font.pixelSize: 11
                            color: root.dimColor
                        }
                    }
                }

                Item { Layout.preferredHeight: 20 }

                // separator
                Rectangle {
                    Layout.fillWidth: true
                    height: 1; color: "#111111"
                }

                Item { Layout.preferredHeight: 16 }

                // contact fields
                Repeater {
                    model: [
                        { icon: "\uf0e0", label: "email",  key: "email"        },
                        { icon: "\uf095", label: "phone",  key: "phone"        },
                        { icon: "\uf3c5", label: "office", key: "office"       },
                        { icon: "\uf0c0", label: "dept",   key: "department"   },
                        { icon: "\uf1ad", label: "company",key: "company"      },
                    ]

                    delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        property var contact: parent.parent.contact || {}
                        property string val: contact[modelData.key] || ""

                        visible: val.length > 0

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 10
                            spacing: 12

                            Text {
                                text: modelData.icon
                                font.family: root.monoFont
                                font.pixelSize: 12
                                color: root.accentColor
                                Layout.preferredWidth: 18
                            }

                            Text {
                                text: modelData.label
                                font.family: root.monoFont
                                font.pixelSize: 10
                                color: root.dimColor
                                Layout.preferredWidth: 60
                            }

                            Text {
                                text: val
                                font.family: root.monoFont
                                font.pixelSize: 12
                                color: root.textColor
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                // compose button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    color: "#000000"
                    border.color: composeMouse.containsMouse ? root.accentColor : "#222222"
                    border.width: 1

                    visible: ((parent.contact || {}).email || "").length > 0

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: "\uf0e0"
                            font.family: root.monoFont
                            font.pixelSize: 11
                            color: composeMouse.containsMouse ? root.accentColor : root.dimColor
                        }
                        Text {
                            text: "compose mail"
                            font.family: root.monoFont
                            font.pixelSize: 11
                            color: composeMouse.containsMouse ? root.accentColor : root.dimColor
                        }
                    }

                    MouseArea {
                        id: composeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // navigation is handled by parent main.qml
                    }
                }
            }
        }
    }

    Component.onCompleted: loadContacts()
}
