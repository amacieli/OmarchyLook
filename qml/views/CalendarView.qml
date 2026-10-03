import QtQuick
import QtQuick.Layouts

// CalendarView — month grid + event sidebar, omarchy aesthetic
// Data source: http://127.0.0.1:27182/calendar/events?month=YYYY-MM
Rectangle {
    id: root
    color: "#000000"

    // ── theme props forwarded from main.qml root ──────────────────
    property string monoFont:     "JetBrainsMono Nerd Font"
    property color  accentColor:  "#7c6af7"
    property color  successColor: "#51cf66"
    property color  dangerColor:  "#ff6b6b"
    property color  textColor:    "#e8e8e8"
    property color  dimColor:     "#555555"
    property color  veryDimColor: "#2a2a2a"

    // ── calendar state ────────────────────────────────────────────
    property int viewYear:  new Date().getFullYear()
    property int viewMonth: new Date().getMonth() + 1   // 1-based
    property int todayDay:  new Date().getDate()
    property int todayMonth: new Date().getMonth() + 1
    property int todayYear:  new Date().getFullYear()
    property int selectedDay: new Date().getDate()

    // events loaded from backend (array of objects)
    property var events: []
    property bool loading: true

    readonly property var monthNames: [
        "January","February","March","April","May","June",
        "July","August","September","October","November","December"
    ]
    readonly property var dayNames: ["Mo","Tu","We","Th","Fr","Sa","Su"]

    // ── helper functions ──────────────────────────────────────────
    function daysInMonth(y, m) {
        return new Date(y, m, 0).getDate()
    }

    // ISO weekday of the 1st of viewYear/viewMonth (1=Mon … 7=Sun)
    function firstWeekday(y, m) {
        var d = new Date(y, m - 1, 1).getDay()  // 0=Sun…6=Sat
        return d === 0 ? 7 : d                   // convert to 1=Mon
    }

    function eventsForDay(day) {
        if (!root.events || root.events.length === 0) return []
        var pad = function(n){ return n < 10 ? "0" + n : "" + n }
        var prefix = viewYear + "-" + pad(viewMonth) + "-" + pad(day)
        var out = []
        for (var i = 0; i < events.length; i++) {
            if (events[i].start && events[i].start.startsWith(prefix))
                out.push(events[i])
        }
        return out
    }

    function prevMonth() {
        if (viewMonth === 1) { viewMonth = 12; viewYear-- }
        else viewMonth--
        selectedDay = 1
        loadEvents()
    }

    function nextMonth() {
        if (viewMonth === 12) { viewMonth = 1; viewYear++ }
        else viewMonth++
        selectedDay = 1
        loadEvents()
    }

    function loadEvents() {
        loading = true
        var pad = function(n){ return n < 10 ? "0" + n : "" + n }
        var month = viewYear + "-" + pad(viewMonth)
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            loading = false
            if (xhr.status === 200) {
                try { root.events = JSON.parse(xhr.responseText) }
                catch(e) { root.events = [] }
            } else {
                root.events = []
            }
        }
        xhr.open("GET", "http://127.0.0.1:27182/calendar/events?month=" + month)
        xhr.send()
    }

    // ── layout ────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── LEFT: month grid ──────────────────────────────────────
        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: 460
            spacing: 0

            // ── header row: nav + month label ─────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                color: "#000000"

                // subtle bottom separator
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 1
                    color: "#111111"
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 0

                    // prev
                    Text {
                        text: "‹"
                        font.family: root.monoFont
                        font.pixelSize: 18
                        color: prevMouse.containsMouse ? root.accentColor : root.dimColor
                        MouseArea {
                            id: prevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.prevMonth()
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.monthNames[root.viewMonth - 1] + "  " + root.viewYear
                        font.family: root.monoFont
                        font.pixelSize: 13
                        font.bold: true
                        color: root.accentColor
                        font.letterSpacing: 1
                    }

                    Item { Layout.fillWidth: true }

                    // next
                    Text {
                        text: "›"
                        font.family: root.monoFont
                        font.pixelSize: 18
                        color: nextMouse.containsMouse ? root.accentColor : root.dimColor
                        MouseArea {
                            id: nextMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.nextMonth()
                        }
                    }
                }
            }

            // ── day-name header row ───────────────────────────────
            Row {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                Repeater {
                    model: root.dayNames
                    delegate: Item {
                        width: Math.floor((460) / 7)
                        height: 24
                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.family: root.monoFont
                            font.pixelSize: 10
                            color: (index >= 5) ? root.dimColor : "#444444"
                        }
                    }
                }
            }

            // ── calendar grid ─────────────────────────────────────
            Grid {
                id: calGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                rowSpacing: 1
                columnSpacing: 1

                property int cellW: Math.floor(459 / 7)
                property int cellH: Math.floor(height / 6)
                property int totalDays:  root.daysInMonth(root.viewYear, root.viewMonth)
                property int startOffset: root.firstWeekday(root.viewYear, root.viewMonth) - 1

                Repeater {
                    // 6 weeks × 7 days = 42 cells
                    model: 42
                    delegate: Rectangle {
                        width:  calGrid.cellW
                        height: calGrid.cellH
                        color:  "#000000"

                        property int dayNum: index - calGrid.startOffset + 1
                        property bool inMonth:   dayNum >= 1 && dayNum <= calGrid.totalDays
                        property bool isToday:   inMonth && dayNum === root.todayDay
                                                  && root.viewMonth === root.todayMonth
                                                  && root.viewYear  === root.todayYear
                        property bool isSelected: inMonth && dayNum === root.selectedDay
                        property bool isWeekend: (index % 7) >= 5
                        property var  dayEvts:   inMonth ? root.eventsForDay(dayNum) : []

                        // selected day ring
                        Rectangle {
                            visible: parent.isSelected
                            anchors.top:  parent.top
                            anchors.left: parent.left
                            width:  parent.width - 1
                            height: parent.height - 1
                            color:  "transparent"
                            border.color: root.accentColor
                            border.width: 1
                        }

                        // today fill
                        Rectangle {
                            visible: parent.isToday && !parent.isSelected
                            anchors.centerIn: parent
                            width:  Math.min(parent.width, parent.height) - 6
                            height: width
                            radius: width / 2
                            color:  Qt.rgba(0.49, 0.42, 0.97, 0.14)
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 3
                            spacing: 1

                            // day number
                            Text {
                                text: parent.parent.inMonth ? parent.parent.dayNum : ""
                                font.family: root.monoFont
                                font.pixelSize: 11
                                color: {
                                    if (!parent.parent.inMonth) return "transparent"
                                    if (parent.parent.isToday) return root.accentColor
                                    if (parent.parent.isWeekend) return root.dimColor
                                    return root.textColor
                                }
                                font.bold: parent.parent.isToday
                            }

                            // event dots (up to 3)
                            Row {
                                id: dotRow
                                spacing: 2
                                visible: parent.parent.inMonth

                                property var cellEvts: parent.parent.dayEvts || []

                                Repeater {
                                    model: Math.min(dotRow.cellEvts.length, 3)
                                    Rectangle {
                                        width: 4; height: 4; radius: 2
                                        color: root.accentColor
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: parent.inMonth
                            onClicked: root.selectedDay = parent.dayNum
                        }
                    }
                }
            }

            // ── "today" button ────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                color: "#000000"

                Rectangle {
                    anchors.top: parent.top
                    width: parent.width; height: 1; color: "#111111"
                }

                Text {
                    anchors.centerIn: parent
                    text: "  today  "
                    font.family: root.monoFont
                    font.pixelSize: 10
                    color: todayBtnMouse.containsMouse ? root.accentColor : root.dimColor
                }

                MouseArea {
                    id: todayBtnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.viewYear  = root.todayYear
                        root.viewMonth = root.todayMonth
                        root.selectedDay = root.todayDay
                        root.loadEvents()
                    }
                }
            }
        }

        // vertical divider
        Rectangle {
            Layout.fillHeight: true
            width: 1
            color: "#111111"
        }

        // ── RIGHT: event list for selected day ────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // day header
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
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 8

                    Text {
                        text: "\uf073"  // calendar icon
                        font.family: root.monoFont
                        font.pixelSize: 13
                        color: root.accentColor
                    }
                    Text {
                        property var pad: function(n){ return n < 10 ? "0" + n : "" + n }
                        text: root.dayNames[(new Date(root.viewYear, root.viewMonth - 1, root.selectedDay).getDay() + 6) % 7]
                              + "  " + root.selectedDay + " " + root.monthNames[root.viewMonth - 1]
                        font.family: root.monoFont
                        font.pixelSize: 13
                        font.bold: true
                        color: root.textColor
                        Layout.fillWidth: true
                    }

                    // loading spinner text
                    Text {
                        visible: root.loading
                        text: "⟳"
                        font.family: root.monoFont
                        font.pixelSize: 11
                        color: root.dimColor

                        RotationAnimation on rotation {
                            from: 0; to: 360; duration: 1200
                            loops: Animation.Infinite
                            running: root.loading
                        }
                    }
                }
            }

            // event list
            ListView {
                id: eventList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 0

                model: {
                    var evts = root.eventsForDay(root.selectedDay)
                    return evts.length > 0 ? evts : []
                }

                // empty state
                Text {
                    anchors.centerIn: parent
                    visible: eventList.count === 0 && !root.loading
                    text: "no events"
                    font.family: root.monoFont
                    font.pixelSize: 11
                    color: root.veryDimColor
                }

                delegate: Rectangle {
                    width: eventList.width
                    height: 62
                    color: "#000000"

                    // left accent bar
                    Rectangle {
                        anchors.left:   parent.left
                        anchors.top:    parent.top
                        anchors.bottom: parent.bottom
                        anchors.topMargin: 2
                        anchors.bottomMargin: 2
                        width: 2
                        color: root.accentColor
                    }

                    // bottom separator
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width; height: 1; color: "#111111"
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 10
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        spacing: 3

                        Text {
                            text: modelData.subject || modelData.summary || "Untitled"
                            font.family: root.monoFont
                            font.pixelSize: 12
                            font.bold: true
                            color: root.textColor
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        RowLayout {
                            spacing: 12
                            Text {
                                text: "\uf017  " + (modelData.start ? modelData.start.substring(11, 16) : "all day")
                                font.family: root.monoFont
                                font.pixelSize: 10
                                color: root.dimColor
                            }
                            Text {
                                visible: modelData.location && modelData.location.length > 0
                                text: "\uf3c5  " + (modelData.location || "")
                                font.family: root.monoFont
                                font.pixelSize: 10
                                color: root.dimColor
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: loadEvents()
}
