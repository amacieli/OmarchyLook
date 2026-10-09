import QtQuick
import Quickshell
import "../mail/format.js" as Fmt

// All non-visual state: navigation + focus model, folder/message data, and the
// backend (Rust daemon, local HTTP) calls. Components read properties and call
// the intent functions below; none of them talk to the backend themselves.
Item {
  id: root

  // ------------------------------------------------------------- backend
  readonly property string backendUrl: "http://127.0.0.1:27182"
  readonly property string configDir: {
    var d = Quickshell.env("CONFIG_DIR")
    return (d && d.length > 0) ? d : Quickshell.env("HOME") + "/.config/omarchylook"
  }
  property bool backendOnline: false
  onBackendOnlineChanged: {
    if (backendOnline) { perfMark("backend first answered"); loadCalendarSettings(); loadUiSettings(); loadSenders(); loadMailSettings() }
  }

  // ---- launch timing (see src/perf.rs): marks are queued until the backend answers, then
  // posted to POST /perf so they land in the same ~/.config/omarchylook/perf.log timeline.
  // Each carries its own QML-side age (ms since AppState was created).
  property double _perfT0: Date.now()
  property var _perfQueue: []
  function perfMark(label) {
    var text = label + " (qml +" + (Date.now() - _perfT0) + "ms)"
    if (!backendOnline && label !== "backend first answered") { _perfQueue.push(text); return }
    var q = _perfQueue; _perfQueue = []
    q.push(text)
    for (var i = 0; i < q.length; i++) {
      var xhr = new XMLHttpRequest()
      xhr.open("POST", backendUrl + "/perf?m=" + encodeURIComponent(q[i]), true)
      xhr.send()
    }
  }
  Component.onCompleted: perfMark("AppState created")
  // Calendar view chosen in the calendar dropdown: day | workweek | week | month
  property string calendarMode: "month"
  // People view dropdowns: all | favorites | lists   and   first | last | company | recent
  property string peopleView: "all"
  property string peopleSort: "first"
  readonly property alias auth: authController

  // ---------------------------------------------------------- navigation
  // `pinned` items render at the bottom of the nav bar.
  readonly property var navItems: [
    { icon: "\uf0e0", label: "Mail",     view: "mail"     },
    { icon: "\uf073", label: "Calendar", view: "calendar" },
    { icon: "\uf0c0", label: "People",   view: "contacts" },
    { icon: "\uf0ae", label: "Tasks",    view: "tasks"    },
    { icon: "\uf27a", label: "SMS",      view: "sms"      },
    { icon: "\uf013", label: "Settings", view: "settings", pinned: true }
  ]

  readonly property var settingsCategories: [
    { id: "account",       icon: "\uf007", label: "Accounts"      },
    { id: "appearance",    icon: "\uf1fc", label: "Appearance"    },
    { id: "mail",          icon: "\uf0e0", label: "Mail"          },
    { id: "senders",       icon: "\uf2bd", label: "Senders"       },
    { id: "calendar",      icon: "\uf073", label: "Calendar"      },
    { id: "sms",           icon: "\uf27a", label: "SMS"           },
    { id: "notifications", icon: "\uf0f3", label: "Notifications" },
    { id: "about",         icon: "\uf05a", label: "About"         }
  ]

  property string currentView: "mail"
  // "nav" = left bar, "folder" = folder bar, "msg" = message list (or the
  // category list when the Settings view is showing).
  property string focusPane: "nav"
  property int navIndex: 0
  property bool navOnToggle: false
  property bool sidebarExpanded: true
  property int folderIndex: 0
  property string selectedFolderId: ""
  property int msgIndex: 0
  property int settingsCategoryIndex: 0

  readonly property string currentViewLabel: navItems[navIndex].label
  readonly property alias folderModel: folderModelObj
  readonly property alias messageModel: messageModelObj

  property string messagesStatus: ""

  // _readRev is bumped whenever a row's read flag changes, so the reading pane's
  // button label re-evaluates (ListModel.get() hands back a snapshot).
  property int _readRev: 0
  readonly property var currentMessage: {
    _readRev
    return messageModelObj.count > msgIndex && msgIndex >= 0 ? messageModelObj.get(msgIndex) : null
  }

  readonly property string selectedFolderName: {
    var n = folderModelObj.count
    for (var i = 0; i < n; i++)
      if (folderModelObj.get(i).id === selectedFolderId) return folderModelObj.get(i).display_name
    return "Inbox"
  }

  // Counts come from the folder row (Graph's totalItemCount / unreadItemCount):
  // the message list is paged, so counting the loaded rows would stop at the
  // first page, and the cached per-message read flag is not reliable.
  readonly property var selectedFolder: {
    _readRev
    for (var i = 0; i < folderModelObj.count; i++)
      if (folderModelObj.get(i).id === selectedFolderId) return folderModelObj.get(i)
    return null
  }
  readonly property int messageTotal: selectedFolder && selectedFolder.total_item_count > 0
    ? selectedFolder.total_item_count : messageModelObj.count
  readonly property int unreadCount: selectedFolder ? (selectedFolder.unread_item_count || 0) : 0

  readonly property int messagePageSize: 200
  property bool _hasMoreMessages: false
  property bool _loadingMessages: false
  property int _messageGeneration: 0

  // ---- message body (reading pane) -----------------------------------------
  // The list carries only previews; the full body is fetched when a message is
  // opened (the backend caches it on disk, and the last few are kept here too).
  // Which view a message opens in (Settings → Mail → Message rendering):
  //   "html"          every message as HTML
  //   "system"        every message in the system font
  //   "system_sender" system font, unless the sender is listed with "always HTML"
  // The HTML/System button (and the "view as HTML" bar) override it per message,
  // for as long as the app is running.
  property string messageRendering: "system_sender"
  property var _htmlOverride: ({})
  property int _htmlRev: 0

  readonly property bool currentSenderAlwaysHtml: {
    _imagesRev
    for (var i = 0; i < senderModelObj.count; i++) {
      var s = senderModelObj.get(i)
      if (s.email === currentSenderEmail) return s.always_html === true
    }
    return false
  }

  readonly property bool currentHtmlOverridden: {
    _htmlRev
    return currentMessageId !== "" && _htmlOverride[currentMessageId] !== undefined
  }

  readonly property bool currentHtmlMode: {
    _htmlRev
    if (currentMessageId === "") return false
    var o = _htmlOverride[currentMessageId]
    if (o !== undefined) return o
    if (messageRendering === "html") return true
    if (messageRendering === "system") return false
    return currentSenderAlwaysHtml
  }

  // Offer "view as HTML" (this message / always for this sender) only where it can
  // matter: an HTML message, shown in the system font, in the mode that honours
  // sender preferences, that the user has not already chosen a view for.
  readonly property bool currentHtmlOffer:
    !currentHtmlMode && !currentHtmlOverridden && messageRendering === "system_sender"
    && currentBody.state === "ready" && currentBody.type === "html"

  function toggleHtml() {
    if (currentMessageId === "") return
    _htmlOverride[currentMessageId] = !currentHtmlMode
    _htmlRev++
  }

  // scope: "message" | "sender" (list the sender with always-HTML on).
  function viewAsHtml(scope) {
    var id = currentMessageId
    if (id === "") return
    _htmlOverride[id] = true
    _htmlRev++
    if (scope === "sender") _listSenderWith(currentSenderEmail, "html")
  }

  function setMessageRendering(mode) {
    if (mode !== "html" && mode !== "system" && mode !== "system_sender") return
    var before = messageRendering
    messageRendering = mode
    request("POST", "/settings/message_rendering?value=" + mode, function(xhr) {
      var ok = false
      try { ok = JSON.parse(xhr.responseText).ok === true } catch (e) { ok = false }
      if (!ok) root.messageRendering = before
    })
  }
  property var currentBody: ({ id: "", state: "idle", type: "", content: "" })
  property var _bodyCache: ({})
  property var _bodyOrder: []

  readonly property string currentMessageId: currentMessage ? String(currentMessage.id || "") : ""
  // Debounced: holding j/k (or gg/G) changes the selection many times a second, and each
  // uncached message would start a fetch plus a rich-text layout (OL-001). Cached bodies
  // show at once; everything else waits until the cursor has rested for 120 ms.
  onCurrentMessageIdChanged: {
    var id = currentMessageId
    if (id === "" || _bodyCache[id]) { _bodyDebounce.stop(); loadBody(id); return }
    currentBody = { id: id, state: "loading", type: "", content: "" }
    _bodyDebounce.restart()
  }
  Timer { id: _bodyDebounce; interval: 120; onTriggered: root.loadBody(root.currentMessageId) }

  function loadBody(id) {
    if (id === "") { currentBody = { id: "", state: "idle", type: "", content: "" }; return }
    var hit = _bodyCache[id]
    if (hit) { currentBody = { id: id, state: "ready", type: hit.type, content: hit.content }; return }
    currentBody = { id: id, state: "loading", type: "", content: "" }
    request("GET", "/messages/body?id=" + encodeURIComponent(id), function(xhr) {
      var result = null
      if (xhr.status === 200) {
        try { result = JSON.parse(xhr.responseText) } catch (e) { result = null }
      }
      var ok = result && result.error === undefined && result.type !== undefined
      if (ok) {
        _bodyCache[id] = { type: result.type, content: result.content }
        _bodyOrder.push(id)
        if (_bodyOrder.length > 30) delete _bodyCache[_bodyOrder.shift()]
      }
      if (root.currentMessageId !== id) return       // moved on while it loaded
      root.currentBody = ok
        ? { id: id, state: "ready", type: result.type, content: result.content }
        : { id: id, state: "error", type: "", content: "",
            reason: (result && result.error) ? String(result.error) : "could not load the message body",
            preview: (result && result.preview) ? String(result.preview) : "" }
    })
  }

  // ---- per-sender preferences (Settings → Senders) --------------------------
  // [{ email, always_html, always_images }] from /settings/senders. Stored only;
  // nothing in the reading pane consults them yet.
  readonly property alias senderModel: senderModelObj
  ListModel { id: senderModelObj }
  property string senderNotice: ""

  function loadSenders() {
    request("GET", "/settings/senders", function(xhr) {
      if (xhr.status !== 200) return
      try {
        var rows = JSON.parse(xhr.responseText)
        if (!Array.isArray(rows)) return
        senderModelObj.clear()
        for (var i = 0; i < rows.length; i++) senderModelObj.append(rows[i])
        root._imagesRev++
      } catch (e) { console.log("[Senders] parse error:", e) }
    })
  }

  function addSender(email, done) {
    var e = String(email || "").trim()
    if (e === "") { senderNotice = "Enter an email address."; if (done) done(false); return }
    request("POST", "/settings/senders/add?email=" + encodeURIComponent(e), function(xhr) {
      var r = null
      try { r = JSON.parse(xhr.responseText) } catch (x) { r = null }
      var status = r && r.status ? r.status : "error"
      senderNotice = status === "added" ? ""
        : (status === "exists" ? e.toLowerCase() + " is already listed."
        : (status === "invalid" ? "That doesn't look like an email address."
        : "Could not add the address."))
      if (status === "added" || status === "exists") loadSenders()
      if (done) done(status === "added")
    })
  }

  // field: "html" | "images". Optimistic; put back if the backend refuses.
  function setSenderPref(email, field, value) {
    var key = field === "html" ? "always_html" : "always_images"
    function apply(v) {
      for (var i = 0; i < senderModelObj.count; i++)
        if (senderModelObj.get(i).email === email) { senderModelObj.setProperty(i, key, v); return }
    }
    apply(value)
    root._imagesRev++
    request("POST", "/settings/senders/set?email=" + encodeURIComponent(email)
            + "&field=" + field + "&value=" + value, function(xhr) {
      var ok = false
      try { ok = JSON.parse(xhr.responseText).ok === true } catch (x) { ok = false }
      if (!ok) { apply(!value); root._imagesRev++ }
    })
  }

  function removeSender(email) {
    request("POST", "/settings/senders/remove?email=" + encodeURIComponent(email), function(xhr) {
      loadSenders()
    })
  }

  // ---- remote images in the HTML view ------------------------------------------
  // Blocked unless this message was unblocked (kept for the session) or its sender
  // is listed with "always load images" (Settings → Senders).
  property var _imagesUnblocked: ({})
  property int _imagesRev: 0

  readonly property string currentSenderEmail:
    currentMessage ? String(currentMessage.from_email || "").trim().toLowerCase() : ""

  readonly property bool currentImagesAllowed: {
    _imagesRev
    if (currentMessageId === "") return false
    if (_imagesUnblocked[currentMessageId] === true) return true
    for (var i = 0; i < senderModelObj.count; i++) {
      var s = senderModelObj.get(i)
      if (s.email === currentSenderEmail) return s.always_images === true
    }
    return false
  }

  // scope: "message" = just this one (session only); "sender" = also list the sender
  // with always-load-images on.
  function unblockImages(scope) {
    var id = currentMessageId
    if (id === "") return
    _imagesUnblocked[id] = true     // either way, load them now
    _imagesRev++
    if (scope === "sender") _listSenderWith(currentSenderEmail, "images")
  }

  // Make sure `email` is in the senders list with `field` ("html" | "images") on.
  function _listSenderWith(email, field) {
    if (email === "") return
    request("POST", "/settings/senders/add?email=" + encodeURIComponent(email), function(xhr) {
      var status = ""
      try { status = JSON.parse(xhr.responseText).status } catch (e) { status = "" }
      if (status !== "added" && status !== "exists") return
      request("POST", "/settings/senders/set?email=" + encodeURIComponent(email)
              + "&field=" + field + "&value=true", function(x2) { root.loadSenders() })
    })
  }

  signal focusRequested()   // ask the shell to put keyboard focus back on the key catcher
  signal closeRequested()   // `Q` / `:q` — close the window

  ListModel { id: folderModelObj }
  ListModel { id: messageModelObj }

  AuthController {
    id: authController
    backendUrl: root.backendUrl
    configDir: root.configDir
    onAccountsChanged: root.loadAccounts()
    onIsAuthenticatedChanged: {
      if (isAuthenticated) { root.loadFolders(); root.loadMessages() }
      root.loadAccounts()
    }
  }

  // Settings → Calendar: how far recurring meetings are expanded (whole years either side of
  // today). Owned by the backend (settings.toml); the daemon applies changes on its next cycle.
  property int recurrenceYearsBack: 5
  property int recurrenceYearsAhead: 10
  property int maxYearsBack: 20
  property int maxYearsAhead: 30

  function applyCalendarSettings(data) {
    recurrenceYearsBack = data.recurrence_years_back
    recurrenceYearsAhead = data.recurrence_years_ahead
    if (data.max_years_back) maxYearsBack = data.max_years_back
    if (data.max_years_ahead) maxYearsAhead = data.max_years_ahead
  }

  function loadCalendarSettings() {
    request("GET", "/settings/calendar", function(xhr) {
      if (xhr.status !== 200) return
      try { applyCalendarSettings(JSON.parse(xhr.responseText)) } catch (e) { console.log("[CalendarSettings] parse error:", e) }
    })
  }

  // Called on every stepper change; the actual save is debounced so rapid clicks send one request.
  function setRecurrenceWindow(back, ahead) {
    recurrenceYearsBack = back
    recurrenceYearsAhead = ahead
    calendarSettingsSave.restart()
  }

  Timer {
    id: calendarSettingsSave
    interval: 600
    onTriggered: root.request("POST",
      "/settings/calendar?back=" + root.recurrenceYearsBack + "&ahead=" + root.recurrenceYearsAhead,
      function(xhr) {
        if (xhr.status !== 200) return
        // the backend clamps; show what was actually stored
        try { root.applyCalendarSettings(JSON.parse(xhr.responseText)) } catch (e) {}
      })
  }

  // Signed-in accounts for Settings → Accounts: [{ id, provider, email, signed_in }]
  property var accounts: []

  function loadAccounts() {
    request("GET", "/accounts", function(xhr) {
      if (xhr.status !== 200) return
      try {
        var list = JSON.parse(xhr.responseText)
        root.accounts = list
        // The backend resolves the address asynchronously — re-poll until it's there
        accountRetry.running = list.some(function(a) { return !a.email })
      } catch (e) { console.log("[Accounts] parse error:", e) }
    })
  }

  Timer {
    id: accountRetry
    interval: 2000
    repeat: true
    onTriggered: root.loadAccounts()
  }

  // --------------------------------------------------------- backend calls
  function request(method, path, onDone, body) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      root.backendOnline = xhr.status !== 0
      if (onDone) onDone(xhr)
    }
    xhr.open(method, root.backendUrl + path, true)
    xhr.send(body)
  }

  function loadFolders() {
    request("GET", "/folders", function(xhr) {
      if (xhr.status !== 200) return
      try {
        var folders = JSON.parse(xhr.responseText)
        folderModelObj.clear()
        for (var i = 0; i < folders.length; i++) folderModelObj.append(folders[i])
        if (root.selectedFolderId === "" && folderModelObj.count > 0)
          root.selectedFolderId = folderModelObj.get(0).id
      } catch (e) { console.log("[Folders] parse error:", e) }
    })
  }

  // Folder rows carry the unread count the status bar shows; nudge it locally so it
  // follows a toggle straight away (the next folder sync replaces it with the provider's).
  function _bumpFolderUnread(folderId, delta) {
    for (var i = 0; i < folderModelObj.count; i++) {
      var f = folderModelObj.get(i)
      if (f.id === folderId) {
        folderModelObj.setProperty(i, "unread_item_count", Math.max(0, (f.unread_item_count || 0) + delta))
        return
      }
    }
  }

  function _setRead(index, isRead) {
    messageModelObj.setProperty(index, "is_read", isRead)
    root._readRev++
  }

  // ---- compose ---------------------------------------------------------------------------
  // The compose pane takes the reading pane's slot while `composing`. This is state + intents
  // only; sending is not wired to the backend yet (PLAN-compose.md Phase A), so submitCompose
  // reports that instead of pretending.
  property bool composing: false
  property var composeInitial: ({ kind: "new" })
  property string composeStatus: ""
  property string composeDefaultMode: "system"   // [mail.compose] default_format, once settings carry it
  property var composeContacts: []               // [{ name, email }] for recipient suggestions

  function loadComposeContacts() {
    request("GET", "/contacts?view=all", function(xhr) {
      if (xhr.status !== 200) return
      try {
        var list = JSON.parse(xhr.responseText), out = []
        for (var i = 0; i < list.length; i++)
          for (var j = 0; j < (list[i].emails || []).length; j++)
            out.push({ name: list[i].display_name || "", email: list[i].emails[j] })
        root.composeContacts = out
      } catch (e) { console.log("[Compose] contacts parse error:", e) }
    })
  }

  function _addr(m) {
    var e = m && m.from_email ? String(m.from_email) : ""
    var n = m && m.from_name ? String(m.from_name) : ""
    return n !== "" && e !== "" ? n + " <" + e + ">" : e
  }

  // kind: "new" | "reply" | "replyAll" | "forward". Default source: the message under the cursor.
  function openCompose(kind) {
    var m = currentMessage
    var init = { kind: kind, accountId: "", to: "", cc: "", bcc: "", subject: "", quote: null, inReplyTo: "" }
    var acct = accounts.filter(function(a) { return a.signed_in && a.email })
    if (acct.length > 0) init.accountId = acct[0].id
    if (kind !== "new" && m) {
      if (m.account_id) init.accountId = String(m.account_id)
      var subj = String(m.subject || "")
      var plain = currentBody && currentBody.state === "ready"
        ? (currentBody.type === "html" ? Fmt.htmlToText(currentBody.content) : currentBody.content)
        : String(m.body_preview || "")
      init.quote = { from: _addr(m), date: Fmt.fullDate(m.received_at), text: plain }
      init.inReplyTo = String(m.id || "")
      if (kind === "forward") {
        init.subject = /^fw(d)?:/i.test(subj) ? subj : "Fwd: " + subj
      } else {
        init.subject = /^re:/i.test(subj) ? subj : "Re: " + subj
        init.to = _addr(m)
        // Reply-all keeps the original To list; the backend phase will drop our own address.
        if (kind === "replyAll") init.cc = String(m.to_recipients || m.to || "")
      }
    }
    composeStatus = ""
    composeInitial = init
    composing = true
    if (composeContacts.length === 0) loadComposeContacts()
  }

  function closeCompose() { composing = false; composeStatus = ""; focusRequested() }

  // ---- sending ---------------------------------------------------------------------------
  // Send hands the message to the backend's outbox, which holds it for `sendDelaySecs` (Settings
  // -> Mail) so it can still be taken back, then sends it at once from its own worker. The
  // compose pane closes straight away; SendToast shows each message's progress and offers Undo.
  property int sendDelaySecs: 3
  property int maxSendDelaySecs: 60

  function applyMailSettings(d) {
    if (d.send_delay_secs !== undefined) sendDelaySecs = d.send_delay_secs
    if (d.max_send_delay_secs) maxSendDelaySecs = d.max_send_delay_secs
  }

  function loadMailSettings() {
    request("GET", "/settings/mail", function(xhr) {
      if (xhr.status !== 200) return
      try { applyMailSettings(JSON.parse(xhr.responseText)) } catch (e) { console.log("[MailSettings] parse error:", e) }
    })
  }

  // Called on every stepper change; the save is debounced so rapid clicks send one request.
  function setSendDelay(secs) {
    sendDelaySecs = secs
    mailSettingsSave.restart()
  }

  Timer {
    id: mailSettingsSave
    interval: 600
    onTriggered: root.request("POST", "/settings/mail?send_delay=" + root.sendDelaySecs, function(xhr) {
      if (xhr.status !== 200) return
      try { root.applyMailSettings(JSON.parse(xhr.responseText)) } catch (e) {}   // the backend clamps
    })
  }

  // Messages handed to the backend and not yet dismissed:
  // [{ id, message, sendAt (ms), state: pending|sending|sent|failed, error, doneAt }]
  property var sends: []
  property real sendNow: Date.now()      // ticks while anything is in flight, for the countdown
  readonly property bool sending: sends.length > 0

  function _sendIndex(id) {
    for (var i = 0; i < sends.length; i++) if (sends[i].id === id) return i
    return -1
  }

  function _patchSend(id, patch) {
    var i = _sendIndex(id)
    if (i < 0) return
    var next = sends.slice(), cur = next[i], merged = {}
    for (var k in cur) merged[k] = cur[k]
    for (var p in patch) merged[p] = patch[p]
    next[i] = merged
    sends = next
  }

  function dismissSend(id) { sends = sends.filter(function(s) { return s.id !== id }) }

  function submitCompose(message) {
    composeStatus = "sending…"
    request("POST", "/compose/send", function(xhr) {
      var r = null
      try { r = JSON.parse(xhr.responseText) } catch (e) {}
      if (xhr.status !== 200 || !r || !r.ok) {
        // Stay in the editor: nothing was queued, nothing is lost.
        composeStatus = r && r.error ? String(r.error) : "Could not queue the message (is the backend running?)"
        return
      }
      sendNow = Date.now()
      sends = sends.concat([{
        id: r.id, message: message, sendAt: sendNow + r.delay_secs * 1000, delaySecs: r.delay_secs,
        state: r.delay_secs > 0 ? "pending" : "sending", error: "", doneAt: 0, polling: false
      }])
      closeCompose()
    }, JSON.stringify(message))
  }

  function _pollSend(id) {
    var i = _sendIndex(id)
    if (i < 0 || sends[i].polling) return
    _patchSend(id, { polling: true })
    request("GET", "/compose/status?id=" + encodeURIComponent(id), function(xhr) {
      var r = null
      try { r = JSON.parse(xhr.responseText) } catch (e) {}
      if (_sendIndex(id) < 0) return
      if (!r || !r.state) { _patchSend(id, { polling: false }); return }
      if (r.state === "sent") _patchSend(id, { state: "sent", doneAt: Date.now(), polling: false })
      else if (r.state === "failed") _patchSend(id, { state: "failed", error: String(r.error || "The message could not be sent."), polling: false })
      else if (r.state === "cancelled") dismissSend(id)
      else _patchSend(id, { state: Date.now() >= sends[_sendIndex(id)].sendAt ? "sending" : "pending", polling: false })
    })
  }

  Timer {
    id: sendTick
    interval: 250
    repeat: true
    running: root.sends.length > 0
    onTriggered: {
      root.sendNow = Date.now()
      var keep = [], changed = false
      for (var i = 0; i < root.sends.length; i++) {
        var s = root.sends[i]
        if (s.state === "sent" && root.sendNow - s.doneAt > 2500) { changed = true; continue }   // fade out
        keep.push(s)
        // Once the delay is over, ask how it went (about once a second).
        if ((s.state === "pending" || s.state === "sending") && root.sendNow >= s.sendAt - 100
            && Math.floor(root.sendNow / 1000) !== Math.floor((root.sendNow - 250) / 1000))
          root._pollSend(s.id)
      }
      if (changed) root.sends = keep
    }
  }

  // Take a queued message back and return to drafting. Only works while it is still waiting;
  // once the worker has started sending it is too late, and the toast says so.
  function undoSend(id) {
    if (composing) return          // one compose at a time: finish or discard the open one first
    var i = _sendIndex(id)
    if (i < 0) return
    var msg = sends[i].message
    request("POST", "/compose/cancel?id=" + encodeURIComponent(id), function(xhr) {
      var r = null
      try { r = JSON.parse(xhr.responseText) } catch (e) {}
      if (r && r.cancelled) { dismissSend(id); reopenCompose(msg) }
      else _patchSend(id, { state: r && r.state === "sent" ? "sent" : "sending", doneAt: Date.now() })
    })
  }

  function reopenFailedSend(id) {
    if (composing) return
    var i = _sendIndex(id)
    if (i < 0) return
    var msg = sends[i].message
    dismissSend(id)
    reopenCompose(msg)
  }

  function _addrText(list) {
    return (list || []).map(function(a) { return a.name ? a.name + " <" + a.email + ">" : a.email }).join(", ")
  }

  // Back into the editor exactly as it was sent: recipients, subject, body and mode.
  function reopenCompose(m) {
    composeStatus = ""
    composeInitial = {
      kind: m.kind, accountId: m.account_id, inReplyTo: m.in_reply_to || "",
      to: _addrText(m.to), cc: _addrText(m.cc), bcc: _addrText(m.bcc),
      subject: m.subject, quote: null, restore: m.body, mode: m.mode
    }
    composing = true
    if (composeContacts.length === 0) loadComposeContacts()
  }

  // The newest message still inside its delay (what `u` takes back).
  function undoLatest() {
    for (var i = sends.length - 1; i >= 0; i--)
      if (sends[i].state === "pending") { undoSend(sends[i].id); return true }
    return false
  }

  // Mark the message at `index` read/unread (default: the one under the cursor).
  // Optimistic: the row, the reading pane and the folder count change at once; the
  // backend stores it and the daemon pushes it to the provider. A refused request
  // puts everything back.
  function toggleRead(index) {
    var i = index === undefined ? msgIndex : index
    if (i < 0 || i >= messageModelObj.count) return
    var m = messageModelObj.get(i)
    var id = m.id
    var wasRead = !!m.is_read
    var delta = wasRead ? 1 : -1
    _setRead(i, !wasRead)
    _bumpFolderUnread(selectedFolderId, delta)
    request("POST", "/messages/read?id=" + encodeURIComponent(id) + "&read=" + (!wasRead), function(xhr) {
      if (xhr.status === 200 && xhr.responseText === "ok") return
      // Roll back — the list may have been reloaded meanwhile, so find the row by id.
      for (var j = 0; j < messageModelObj.count; j++) {
        if (messageModelObj.get(j).id === id) { root._setRead(j, wasRead); break }
      }
      root._bumpFolderUnread(root.selectedFolderId, -delta)
    })
  }

  // Background refresh: the daemon changes read flags and folder counts on its own
  // (sync, reads done in other clients), so pick those up without disturbing the
  // cursor or scroll position. Rows are patched in place when the loaded ids still
  // line up; if mail arrived or left, the first page is reloaded instead.
  function refreshFolderCounts() {
    request("GET", "/folders", function(xhr) {
      if (xhr.status !== 200) return
      try {
        var folders = JSON.parse(xhr.responseText)
        var same = folders.length === folderModelObj.count
        for (var i = 0; same && i < folders.length; i++)
          if (folders[i].id !== folderModelObj.get(i).id) same = false
        if (!same) { loadFolders(); return }
        for (var j = 0; j < folders.length; j++) {
          var f = folderModelObj.get(j)
          if (f.unread_item_count !== folders[j].unread_item_count)
            folderModelObj.setProperty(j, "unread_item_count", folders[j].unread_item_count)
          if (f.total_item_count !== folders[j].total_item_count)
            folderModelObj.setProperty(j, "total_item_count", folders[j].total_item_count)
        }
        root._readRev++
      } catch (e) { console.log("[Folders] refresh parse error:", e) }
    })
  }

  function refreshMessages() {
    if (_loadingMessages || messageModelObj.count === 0) return
    var gen = root._messageGeneration
    var n = Math.min(messageModelObj.count, 1000)
    var path = "/messages?limit=" + n + "&offset=0"
    if (root.selectedFolderId !== "") path += "&folder_id=" + encodeURIComponent(root.selectedFolderId)
    request("GET", path, function(xhr) {
      if (xhr.status !== 200 || gen !== root._messageGeneration || root._loadingMessages) return
      try {
        var rows = JSON.parse(xhr.responseText)
        var aligned = rows.length === n
        for (var i = 0; aligned && i < n; i++)
          if (rows[i].id !== messageModelObj.get(i).id) aligned = false
        if (!aligned) { root.perfMark("refreshMessages: list changed on disk (new mail) -> reload"); if (messageModelObj.count <= root.messagePageSize) loadMessages(); return }
        var changed = false
        for (var j = 0; j < n; j++) {
          if (!!messageModelObj.get(j).is_read !== !!rows[j].is_read) {
            messageModelObj.setProperty(j, "is_read", rows[j].is_read)
            changed = true
          }
        }
        if (changed) root._readRev++
      } catch (e) { console.log("[Messages] refresh parse error:", e) }
    })
  }

  Timer {
    interval: 20000
    running: root.backendOnline
    repeat: true
    onTriggered: { root.refreshFolderCounts(); root.refreshMessages(); root.loadSenders() }
  }

  // ---- backend change signal: the daemon bumps a counter whenever a sync stage changed what
  // the mail UI shows (recent-50 stored, read flags, folder counts, new/older mail). Polling
  // this tiny endpoint (no DB access) makes fresh mail appear within one tick of being
  // stored. Fast (500 ms) for the first 90 s after launch while the stages land, then 3 s.
  property int _syncSerial: -1
  property bool _syncFast: true
  Timer { interval: 90000; running: root.backendOnline; onTriggered: root._syncFast = false }
  Timer {
    interval: root._syncFast ? 500 : 3000
    running: root.backendOnline
    repeat: true
    onTriggered: root.checkSyncSerial()
  }
  function checkSyncSerial() {
    request("GET", "/sync/serial", function(xhr) {
      if (xhr.status !== 200) return
      var n = -1
      try { n = JSON.parse(xhr.responseText).mail } catch (e) { return }
      if (root._syncSerial === -1) { root._syncSerial = n; if (n === 0) return }
      else if (n === root._syncSerial) return
      root._syncSerial = n
      root.perfMark("sync serial " + n + " seen -> refreshing mail UI")
      root.refreshFolderCounts()
      if (messageModelObj.count === 0) root.loadMessages()
      else root.refreshMessages()
    })
  }

  function _messagesPath(offset) {
    var path = "/messages?limit=" + messagePageSize + "&offset=" + offset
    if (root.selectedFolderId !== "") path += "&folder_id=" + encodeURIComponent(root.selectedFolderId)
    return path
  }

  property bool _perfFirstMessages: true
  function loadMessages() {
    if (_perfFirstMessages) perfMark("first loadMessages request sent")
    root.messagesStatus = "…"
    var gen = ++root._messageGeneration
    root._loadingMessages = true
    request("GET", _messagesPath(0), function(xhr) {
      if (gen !== root._messageGeneration) return   // folder changed meanwhile
      root._loadingMessages = false
      if (xhr.status === 200) {
        try {
          var messages = JSON.parse(xhr.responseText)
          messageModelObj.clear()
          for (var i = 0; i < messages.length; i++) messageModelObj.append(messages[i])
          if (root._perfFirstMessages && messages.length > 0) { root._perfFirstMessages = false; perfMark("EMAILS VISIBLE: model populated with " + messages.length + " rows") }
          else if (messages.length > 0) perfMark("mail list reloaded: " + messages.length + " rows")
          root._hasMoreMessages = messages.length >= root.messagePageSize
          root.messagesStatus = root.messageTotal.toLocaleString(Qt.locale("en_US"), "f", 0)
          if (root.msgIndex >= messageModelObj.count) root.msgIndex = Math.max(0, messageModelObj.count - 1)
        } catch (e) { root.messagesStatus = "err" }
      } else {
        root.messagesStatus = xhr.status === 0 ? "" : "e" + xhr.status
      }
    })
  }

  // Next page of the open folder, appended below what is already loaded.
  function loadMoreMessages() {
    if (!_hasMoreMessages || _loadingMessages) return
    var gen = root._messageGeneration
    root._loadingMessages = true
    request("GET", _messagesPath(messageModelObj.count), function(xhr) {
      if (gen !== root._messageGeneration) return
      root._loadingMessages = false
      if (xhr.status !== 200) return
      try {
        var messages = JSON.parse(xhr.responseText)
        for (var i = 0; i < messages.length; i++) messageModelObj.append(messages[i])
        root._hasMoreMessages = messages.length >= root.messagePageSize
      } catch (e) { console.log("[Messages] page parse error:", e) }
    })
  }

  property bool _applyingSettings: false

  function loadUiSettings() {
    request("GET", "/settings/ui", function(xhr) {
      if (xhr.status !== 200) return
      try {
        var s = JSON.parse(xhr.responseText)
        if (s.message_rendering === "html" || s.message_rendering === "system" || s.message_rendering === "system_sender")
          root.messageRendering = s.message_rendering
        if (typeof s.sidebar_expanded === "boolean") {
          root._applyingSettings = true
          root.sidebarExpanded = s.sidebar_expanded
          root._applyingSettings = false
        }
      } catch (e) { console.log("[Settings] parse error:", e) }
    })
  }

  onSidebarExpandedChanged: {
    if (!_applyingSettings)
      request("POST", "/settings/sidebar_expanded", null, sidebarExpanded ? "true" : "false")
  }

  onSelectedFolderIdChanged: loadMessages()

  // Backend may still be starting: retry until it answers, then load once.
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      if (root.backendOnline) { stop(); return }
      root.loadUiSettings()
      root.loadFolders()
      root.loadMessages()
      root.loadSenders()
    }
  }

  // ------------------------------------------------------- navigation intents
  function setNavIndex(i) {
    navIndex = i
    currentView = navItems[i].view
  }

  function drillIn() {
    if (currentView === "mail") { focusPane = "folder"; folderIndex = Math.max(0, folderIndex) }
    else { focusPane = "msg"; msgIndex = 0 }
  }

  function selectFolderAt(i) {
    if (i >= 0 && i < folderModelObj.count) selectedFolderId = folderModelObj.get(i).id
  }

  function openSettingsCategory(id) {
    for (var i = 0; i < settingsCategories.length; i++)
      if (settingsCategories[i].id === id) settingsCategoryIndex = i
    for (var j = 0; j < navItems.length; j++)
      if (navItems[j].view === "settings") setNavIndex(j)
    navOnToggle = false
    focusPane = "msg"
    focusRequested()
  }

  // Mouse intents ------------------------------------------------------
  function clickNav(i)        { setNavIndex(i); focusPane = "nav"; navOnToggle = false; focusRequested() }
  function clickNavToggle()   { sidebarExpanded = !sidebarExpanded; navOnToggle = true; focusPane = "nav"; focusRequested() }
  function clickFolder(i)     { folderIndex = i; selectFolderAt(i); focusPane = "msg"; msgIndex = 0; focusRequested() }
  function clickMessage(i)    { focusPane = "msg"; msgIndex = i; focusRequested() }
  function clickCategory(i)   { settingsCategoryIndex = i; focusPane = "msg"; focusRequested() }

  // Keyboard intents (called from PanelKeyCatcher) ---------------------
  function moveCursor(dx, dy) {
    if (dy !== 0) moveVertical(dy)
    else if (dx > 0) moveInto()
    else if (dx < 0) back(true)
  }

  function moveVertical(dy) {
    if (focusPane === "nav") {
      if (dy > 0) {
        if (navOnToggle) { navOnToggle = false; setNavIndex(0) }
        else setNavIndex(Math.min(navIndex + 1, navItems.length - 1))
      } else {
        if (navOnToggle) return
        if (navIndex === 0) navOnToggle = true
        else setNavIndex(navIndex - 1)
      }
    } else if (focusPane === "folder") {
      folderIndex = Math.max(0, Math.min(folderIndex + dy, folderModelObj.count - 1))
      selectFolderAt(folderIndex)
    } else if (focusPane === "msg") {
      if (currentView === "settings")
        settingsCategoryIndex = Math.max(0, Math.min(settingsCategoryIndex + dy, settingsCategories.length - 1))
      else if (currentView === "mail")
        msgIndex = Math.max(0, Math.min(msgIndex + dy, messageModelObj.count - 1))
    }
  }

  function moveInto() {
    if (focusPane === "nav") {
      if (navOnToggle) sidebarExpanded = !sidebarExpanded
      else drillIn()
    } else if (focusPane === "folder") {
      selectFolderAt(folderIndex)
      focusPane = "msg"
      msgIndex = 0
    } else if (focusPane === "msg" && currentView === "mail" && currentMessage) {
      focusPane = "reader"
    }
  }

  function activate() { moveInto() }

  // `h` / Esc: one pane to the left. Never closes the window (that is `Q`).
  function back() {
    if (focusPane === "reader") focusPane = "msg"
    else if (focusPane === "msg") focusPane = currentView === "mail" ? "folder" : "nav"
    else if (focusPane === "folder") focusPane = "nav"
  }

  // Panes that exist in the current view, left to right.
  function panesInView() {
    return currentView === "mail" ? ["nav", "folder", "msg", "reader"] : ["nav", "msg"]
  }

  // Put the cursor in `pane` (no-op if the view has no such pane). Entering the
  // message list from outside resets nothing, so the cursor stays where it was.
  function focusPaneNamed(pane) {
    if (panesInView().indexOf(pane) < 0) return
    if (pane === "folder") folderIndex = Math.max(0, folderIndex)
    if (pane === "reader" && !currentMessage) return
    if (pane === "msg" && currentView !== "mail" && focusPane === "nav") msgIndex = 0
    navOnToggle = false
    focusPane = pane
  }

  // Tab / Shift-Tab.
  function cyclePane(dir) {
    var panes = panesInView()
    var i = panes.indexOf(focusPane)
    if (i < 0) i = 0
    for (var n = 1; n <= panes.length; n++) {
      var next = panes[(i + dir * n + panes.length * n) % panes.length]
      if (next === "reader" && !currentMessage) continue
      focusPaneNamed(next)
      return
    }
  }

  // Jump to the first/last entry in the nav bar.
  function navEdge(bottom) {
    navOnToggle = false
    setNavIndex(bottom ? navItems.length - 1 : 0)
  }

  // Jump to folder `i` of the folder model and land in its message list.
  function gotoFolder(i) {
    gotoView("mail")
    clickFolder(i)
  }

  // `g` + letter: go to a module and land in its main pane.
  function gotoView(view) {
    for (var i = 0; i < navItems.length; i++) {
      if (navItems[i].view !== view) continue
      setNavIndex(i)
      navOnToggle = false
      if (view !== "mail") msgIndex = 0
      focusPane = "msg"
      return
    }
  }

  // `s`: cycle nav -> folder/list -> nav.
  function cycleFocus() {
    if (focusPane === "nav") { if (!navOnToggle) drillIn() }
    else if (focusPane === "folder") { selectFolderAt(folderIndex); focusPane = "msg"; msgIndex = 0 }
    else focusPane = "nav"
  }
}
