import QtQuick
import QtQuick.Layouts
import "CalendarUtil.js" as CU

// Shared hour-by-hour grid used by DayView, WorkWeekView and FullWeekView.
// `days` is an array of Date objects; one column is drawn per day.
// Each column header is a cell with the date number in its top-left corner.
Item {
    id: root

    property var    days: []
    property var    events: []          // normalised (CU.normalise)
    property date   selectedDate: new Date()
    property date   today: new Date()

    property string monoFont:     "JetBrainsMono Nerd Font"
    property color  accentColor:  "#7c6af7"
    property color  textColor:    "#e8e8e8"
    property color  dimColor:     "#555555"
    property color  veryDimColor: "#2a2a2a"
    property color  lineColor:    "#141414"

    property int hourHeight:  48
    property int gutterWidth: 52
    property int headerHeight: 56
    property int firstVisibleHour: 7

    signal dayClicked(date day)
    signal dayActivated(date day)       // double-click → open in day view

    readonly property real colWidth: days.length > 0 ? (width - gutterWidth) / days.length : 0

    // all-day strip height = tallest day
    property int allDayRows: {
        var m = 0
        for (var i = 0; i < days.length; i++)
            m = Math.max(m, CU.allDayOnDay(events, days[i]).length)
        return Math.min(m, 4)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── day header cells (date number top-left) ───────────────
        Row {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            Item { width: root.gutterWidth; height: root.headerHeight }
            Repeater {
                model: root.days
                delegate: Rectangle {
                    id: hcell
                    property date day: modelData
                    property bool isToday: CU.sameDay(day, root.today)
                    property bool isSel:   CU.sameDay(day, root.selectedDate)
                    width: root.colWidth
                    height: root.headerHeight
                    color: "transparent"

                    Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: root.lineColor }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.lineColor }

                    // date number — top-left
                    Text {
                        id: num
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.leftMargin: 8
                        anchors.topMargin: 5
                        text: hcell.day.getDate()
                        font.family: root.monoFont
                        font.pixelSize: 20
                        font.bold: hcell.isToday
                        color: hcell.isToday ? root.accentColor
                             : CU.isWeekend(hcell.day) ? root.dimColor : root.textColor
                    }
                    Text {
                        anchors.left: num.right
                        anchors.leftMargin: 8
                        anchors.baseline: num.baseline
                        text: CU.DAYS_SHORT[CU.isoIndex(hcell.day)].toUpperCase()
                        font.family: root.monoFont
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        color: root.dimColor
                    }
                    Rectangle {
                        visible: hcell.isSel
                        anchors.bottom: parent.bottom
                        width: parent.width; height: 2
                        color: root.accentColor
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dayClicked(hcell.day)
                        onDoubleClicked: root.dayActivated(hcell.day)
                    }
                }
            }
        }

        // ── all-day strip ─────────────────────────────────────────
        Row {
            visible: root.allDayRows > 0
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? root.allDayRows * 20 + 6 : 0
            Item {
                width: root.gutterWidth; height: parent.height
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 6
                    anchors.top: parent.top; anchors.topMargin: 4
                    text: "all-day"
                    font.family: root.monoFont; font.pixelSize: 9
                    color: root.dimColor
                }
            }
            Repeater {
                model: root.days
                delegate: Rectangle {
                    width: root.colWidth
                    height: parent.height
                    color: "transparent"
                    property var list: CU.allDayOnDay(root.events, modelData)
                    Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: root.lineColor }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.lineColor }
                    Column {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 2
                        Repeater {
                            model: Math.min(parent.parent.list.length, 4)
                            delegate: Rectangle {
                                width: parent.width; height: 18
                                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                                Text {
                                    anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 3
                                    verticalAlignment: Text.AlignVCenter
                                    text: parent.parent.parent.list[index].title
                                    elide: Text.ElideRight
                                    font.family: root.monoFont; font.pixelSize: 10
                                    color: root.textColor
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── scrollable hour grid ──────────────────────────────────
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: root.hourHeight * 24
            boundsBehavior: Flickable.StopAtBounds
            // Pin the first visible hour until the user scrolls, so the initial
            // position survives layout passes that resize the viewport.
            property bool _userScrolled: false
            onMovingChanged: if (moving) _userScrolled = true
            onHeightChanged: {
                if (!_userScrolled && height > 0)
                    contentY = Math.min(root.firstVisibleHour * root.hourHeight,
                                        Math.max(0, contentHeight - height))
            }

            // hour lines + labels
            Repeater {
                model: 24
                delegate: Item {
                    y: index * root.hourHeight
                    width: flick.width
                    height: root.hourHeight
                    Text {
                        x: 0
                        width: root.gutterWidth - 12
                        horizontalAlignment: Text.AlignRight
                        y: index === 0 ? 0 : -height / 2
                        text: index === 0 ? "" : CU.hourLabel(index)
                        font.family: root.monoFont; font.pixelSize: 9
                        color: root.dimColor
                    }
                    Rectangle {
                        x: root.gutterWidth; width: parent.width - root.gutterWidth
                        height: 1; color: root.lineColor
                    }
                }
            }

            // day columns
            Row {
                x: root.gutterWidth
                height: flick.contentHeight
                Repeater {
                    model: root.days
                    delegate: Item {
                        id: col
                        property date day: modelData
                        property bool isToday: CU.sameDay(day, root.today)
                        property var  timed: CU.layoutOverlaps(CU.timedOnDay(root.events, day))
                        width: root.colWidth
                        height: flick.contentHeight

                        Rectangle { width: 1; height: parent.height; color: root.lineColor }
                        Rectangle {
                            anchors.fill: parent
                            visible: col.isToday
                            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.04)
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.dayClicked(col.day)
                            onDoubleClicked: root.dayActivated(col.day)
                        }

                        Repeater {
                            model: col.timed
                            delegate: Rectangle {
                                property var ev: modelData
                                x: 2 + (col.width - 4) * ev.col / ev.cols
                                width: (col.width - 4) / ev.cols - 2
                                y: ev.startMin / 60 * root.hourHeight + 1
                                height: Math.max(16, (ev.endMin - ev.startMin) / 60 * root.hourHeight - 2)
                                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
                                clip: true
                                Rectangle { width: 2; height: parent.height; color: root.accentColor }
                                Column {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6; anchors.topMargin: 2; anchors.rightMargin: 3
                                    Text {
                                        width: parent.width
                                        text: ev.title
                                        elide: Text.ElideRight
                                        font.family: root.monoFont; font.pixelSize: 10; font.bold: true
                                        color: root.textColor
                                    }
                                    Text {
                                        width: parent.width
                                        visible: parent.parent.height > 30
                                        text: CU.timeLabel(ev.startMin) + "–" + CU.timeLabel(ev.endMin)
                                              + (ev.location ? "  " + ev.location : "")
                                        elide: Text.ElideRight
                                        font.family: root.monoFont; font.pixelSize: 9
                                        color: root.dimColor
                                    }
                                }
                            }
                        }

                        // now-line
                        Rectangle {
                            visible: col.isToday
                            y: (root.today.getHours() * 60 + root.today.getMinutes()) / 60 * root.hourHeight
                            width: parent.width; height: 1
                            color: "#ff6b6b"
                        }
                    }
                }
            }
        }
    }
}
