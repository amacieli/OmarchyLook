.pragma library

// Date + event helpers shared by the calendar views. All dates are local.
// Event timestamps are treated as wall-clock strings ("YYYY-MM-DDTHH:MM[:SS]")
// so no timezone shifting happens in the UI.

var MONTHS = ["January","February","March","April","May","June",
              "July","August","September","October","November","December"]
var DAYS_SHORT = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]

function pad(n) { return n < 10 ? "0" + n : "" + n }

function startOfDay(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }

function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n) }

function addMonths(d, n) {
    var t = new Date(d.getFullYear(), d.getMonth() + n, 1)
    var last = new Date(t.getFullYear(), t.getMonth() + 1, 0).getDate()
    return new Date(t.getFullYear(), t.getMonth(), Math.min(d.getDate(), last))
}

function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth()
        && a.getDate() === b.getDate()
}

// Monday of the week containing d.
function weekStart(d) {
    var wd = (d.getDay() + 6) % 7   // 0 = Mon
    return addDays(startOfDay(d), -wd)
}

// 0 = Mon … 6 = Sun
function isoIndex(d) { return (d.getDay() + 6) % 7 }

function isWeekend(d) { return isoIndex(d) >= 5 }

function key(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }

// First of 42 cells (6 weeks) shown in the month grid for the month of d.
function monthGridStart(d) {
    return weekStart(new Date(d.getFullYear(), d.getMonth(), 1))
}

// "YYYY-MM" keys of every month touched by [from, to].
function monthsBetween(from, to) {
    var out = [], y = from.getFullYear(), m = from.getMonth()
    while (y < to.getFullYear() || (y === to.getFullYear() && m <= to.getMonth())) {
        out.push(y + "-" + pad(m + 1))
        if (++m > 11) { m = 0; y++ }
    }
    return out
}

function parseStamp(s) {
    if (!s || typeof s !== "string" || s.length < 10) return null
    var y = parseInt(s.substring(0, 4)), mo = parseInt(s.substring(5, 7)) - 1,
        d = parseInt(s.substring(8, 10))
    var hasTime = s.length >= 16
    var h = hasTime ? parseInt(s.substring(11, 13)) : 0
    var mi = hasTime ? parseInt(s.substring(14, 16)) : 0
    if (isNaN(y) || isNaN(mo) || isNaN(d)) return null
    return { date: new Date(y, mo, d), minutes: h * 60 + mi, hasTime: hasTime }
}

// Normalise raw backend events -> { title, location, startDate, endDate,
// startMin, endMin, allDay, raw }.  endDate is inclusive.
function normalise(events) {
    var out = []
    for (var i = 0; i < (events || []).length; i++) {
        var e = events[i], s = parseStamp(e.start)
        if (!s) continue
        var en = parseStamp(e.end)
        var allDay = e.allDay === true || e.is_all_day === true || !s.hasTime
                     || (s.minutes === 0 && en && en.minutes === 0 && en.date > s.date)
        var endDate = en ? en.date : s.date
        var endMin = en ? en.minutes : s.minutes + 60
        if (en && en.minutes === 0 && endDate > s.date) endDate = addDays(endDate, -1)  // exclusive midnight end
        if (endDate < s.date) endDate = s.date
        if (!allDay && endDate > s.date) { endDate = s.date; endMin = 24 * 60 }          // clip to start day
        if (!allDay && endMin <= s.minutes) endMin = Math.min(s.minutes + 30, 24 * 60)
        out.push({
            title: e.subject || e.summary || "Untitled",
            location: e.location || "",
            startDate: s.date, endDate: endDate,
            startMin: s.minutes, endMin: endMin,
            allDay: allDay, raw: e
        })
    }
    return out
}

function onDay(norm, day) {
    var t = startOfDay(day).getTime(), out = []
    for (var i = 0; i < norm.length; i++) {
        var e = norm[i]
        if (e.startDate.getTime() <= t && t <= e.endDate.getTime()) out.push(e)
    }
    out.sort(function(a, b) {
        if (a.allDay !== b.allDay) return a.allDay ? -1 : 1
        return a.startMin - b.startMin
    })
    return out
}

function timedOnDay(norm, day) {
    return onDay(norm, day).filter(function(e) { return !e.allDay })
}
function allDayOnDay(norm, day) {
    return onDay(norm, day).filter(function(e) { return e.allDay })
}

// Greedy column layout so overlapping timed events sit side by side.
// Returns the same objects annotated with .col and .cols.
function layoutOverlaps(list) {
    var items = list.slice().sort(function(a, b) { return a.startMin - b.startMin || b.endMin - a.endMin })
    var out = [], group = [], groupEnd = -1
    function flush() {
        var colEnds = []
        group.forEach(function(e) {
            var c = 0
            while (c < colEnds.length && colEnds[c] > e.startMin) c++
            colEnds[c] = e.endMin
            e.col = c
        })
        group.forEach(function(e) { e.cols = colEnds.length; out.push(e) })
        group = []
    }
    items.forEach(function(e) {
        if (group.length && e.startMin >= groupEnd) { flush(); groupEnd = -1 }
        group.push(e)
        groupEnd = Math.max(groupEnd, e.endMin)
    })
    if (group.length) flush()
    return out
}

function timeLabel(min) {
    var h = Math.floor(min / 60) % 24, m = min % 60
    return pad(h) + ":" + pad(m)
}

function hourLabel(h) { return pad(h) + ":00" }
