import QtQuick
import Quickshell

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
  readonly property alias auth: authController

  // ---------------------------------------------------------- navigation
  // `pinned` items render at the bottom of the nav bar.
  readonly property var navItems: [
    { icon: "\uf0e0", label: "Mail",     view: "mail"     },
    { icon: "\uf073", label: "Calendar", view: "calendar" },
    { icon: "\uf0c0", label: "People",   view: "contacts" },
    { icon: "\uf0ae", label: "Tasks",    view: "tasks"    },
    { icon: "\uf013", label: "Settings", view: "settings", pinned: true }
  ]

  readonly property var settingsCategories: [
    { id: "account",       icon: "\uf007", label: "Account"       },
    { id: "appearance",    icon: "\uf1fc", label: "Appearance"    },
    { id: "mail",          icon: "\uf0e0", label: "Mail"          },
    { id: "calendar",      icon: "\uf073", label: "Calendar"      },
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

  readonly property var currentMessage: messageModelObj.count > msgIndex && msgIndex >= 0
    ? messageModelObj.get(msgIndex) : null

  readonly property string selectedFolderName: {
    var n = folderModelObj.count
    for (var i = 0; i < n; i++)
      if (folderModelObj.get(i).id === selectedFolderId) return folderModelObj.get(i).display_name
    return "Inbox"
  }

  readonly property int unreadCount: {
    var c = 0
    for (var i = 0; i < messageModelObj.count; i++)
      if (!messageModelObj.get(i).is_read) c++
    return c
  }

  signal focusRequested()   // ask the shell to put keyboard focus back on the key catcher
  signal closeRequested()   // Esc pressed at the top level

  ListModel { id: folderModelObj }
  ListModel { id: messageModelObj }

  AuthController {
    id: authController
    backendUrl: root.backendUrl
    configDir: root.configDir
    onIsAuthenticatedChanged: {
      if (isAuthenticated) { root.loadFolders(); root.loadMessages() }
    }
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

  function loadMessages() {
    root.messagesStatus = "…"
    var path = "/messages"
    if (root.selectedFolderId !== "") path += "?folder_id=" + encodeURIComponent(root.selectedFolderId)
    request("GET", path, function(xhr) {
      if (xhr.status === 200) {
        try {
          var messages = JSON.parse(xhr.responseText)
          messageModelObj.clear()
          for (var i = 0; i < messages.length; i++) messageModelObj.append(messages[i])
          root.messagesStatus = messages.length + ""
          if (root.msgIndex >= messageModelObj.count) root.msgIndex = Math.max(0, messageModelObj.count - 1)
        } catch (e) { root.messagesStatus = "err" }
      } else {
        root.messagesStatus = xhr.status === 0 ? "" : "e" + xhr.status
      }
    })
  }

  property bool _applyingSettings: false

  function loadUiSettings() {
    request("GET", "/settings/ui", function(xhr) {
      if (xhr.status !== 200) return
      try {
        var s = JSON.parse(xhr.responseText)
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
    }
  }

  function activate() { moveInto() }

  // `h` / Esc: one pane to the left. At the top level Esc closes the window,
  // `h` does nothing.
  function back(isH) {
    if (focusPane === "msg") focusPane = currentView === "mail" ? "folder" : "nav"
    else if (focusPane === "folder") focusPane = "nav"
    else if (!isH) closeRequested()
  }

  // `s`: cycle nav -> folder/list -> nav.
  function cycleFocus() {
    if (focusPane === "nav") { if (!navOnToggle) drillIn() }
    else if (focusPane === "folder") { selectFolderAt(folderIndex); focusPane = "msg"; msgIndex = 0 }
    else focusPane = "nav"
  }
}
