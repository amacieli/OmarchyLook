import QtQuick
import "CalendarUtil.js" as CU

// Day view — one tall column, hour by hour. Date number sits top-left.
CalendarTimeGrid {
    property date anchorDate: new Date()
    days: [CU.startOfDay(anchorDate)]
    selectedDate: anchorDate
    gutterWidth: 60
    headerHeight: 64
}
