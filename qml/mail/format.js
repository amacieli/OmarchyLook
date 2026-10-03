.pragma library

// Display helpers for message rows / headers. Pure functions.

function senderName(m) {
  if (!m) return ""
  return m.from_name ? m.from_name : (m.from_email || "")
}

function listDate(s) {
  s = s || ""
  if (s.length >= 10) {
    var d = new Date(s)
    var now = new Date()
    if (d.toDateString() === now.toDateString()) return s.substring(11, 16)
    return s.substring(5, 10)
  }
  return s.substring(0, 10)
}

function fullDate(s) {
  s = s || ""
  if (s.length >= 16) return s.substring(0, 16).replace("T", "  ")
  return s.substring(0, 10)
}

function recipients(m) {
  if (!m) return ""
  var to = m.to_recipients || m.to || ""
  return to.length > 0 ? "to  " + to : ""
}

function body(m) {
  if (!m) return ""
  return m.body_preview || m.body || m.snippet || ""
}
