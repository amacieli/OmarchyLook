import QtQuick
import "CalendarUtil.js" as CU

// Full-week view — Monday to Sunday of the week containing anchorDate.
CalendarTimeGrid {
    property date anchorDate: new Date()
    days: {
        var s = CU.weekStart(anchorDate), out = []
        for (var i = 0; i < 7; i++) out.push(CU.addDays(s, i))
        return out
    }
    selectedDate: anchorDate
}
