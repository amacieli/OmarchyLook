// Runs on WorkerScript's own thread (see MessagePreview.qml): turns a message body into what
// the two reading views show, so the regex passes over big HTML never block scrolling.
// Qt's own rich-text layout still has to happen on the GUI thread; this removes everything else.
WorkerScript.onMessage = function(m) {
  Qt.include("format.js")
  var out = { seq: m.seq, plain: "", html: "", blocked: 0 }
  try {
    if (m.type === "html") {
      out.plain = htmlToText(m.content)
      if (m.wantHtml) {
        var r = sanitizeHtml(m.content, m.maxWidth, m.allowRemote)
        out.html = r.html
        out.blocked = r.blocked
      }
    } else {
      out.plain = String(m.content || "")
      if (m.wantHtml) out.html = textToHtml(m.content)
    }
  } catch (e) {
    out.plain = "could not render this message: " + e
  }
  WorkerScript.sendMessage(out)
}
