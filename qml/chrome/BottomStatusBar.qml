import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../common"

// Context (where am I), counts, and the key hints for the focused pane.
Item {
  id: root

  property bool backendOnline: false
  property string viewLabel: ""
  property string folderName: ""
  property int messageCount: 0
  property int unreadCount: 0
  property string focusPane: "nav"
  property string currentView: "mail"

  function fmt(n) { return Number(n).toLocaleString(Qt.locale("en_US"), "f", 0) }

  property string pendingText: ""
  property var pendingOptions: []
  property string notice: ""

  // Hints for the focused pane. ":" always opens the full command list.
  readonly property string hints: {
    if (focusPane === "nav")    return "j/k move   l open   tab next pane   g go to"
    if (focusPane === "folder") return "j/k move   l select   h back   tab next pane"
    if (focusPane === "reader") return "j/k scroll   space page   r reply   h back"
    if (currentView === "settings") return "j/k category   h back   tab next pane"
    if (currentView === "mail") return "j/k move   l read   r reply   z read/unread   tab next pane"
    if (currentView === "calendar") return "j/k period   t today   d/w/m view   tab next pane"
    if (currentView === "tasks") return "j/k move   space done   f filter   tab next pane"
    return "j/k move   h back   tab next pane"
  }

  // While a chord is half typed ("g"), show what can follow instead of the hints.
  readonly property string pendingHelp: {
    var t = pendingText + " …   "
    for (var i = 0; i < pendingOptions.length; i++) {
      var o = pendingOptions[i]
      t += o.next + " " + o.cmd.title.replace(/^Go to /, "").toLowerCase() + "   "
    }
    return t
  }

  implicitHeight: row.implicitHeight + Style.spacing.md * 2

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.xl
    anchors.rightMargin: Style.spacing.xl
    spacing: Style.spacing.xxl

    UiText {
      text: root.currentView === "mail" ? root.viewLabel + " › " + root.folderName : root.viewLabel
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    UiText {
      visible: root.currentView === "mail"
      text: root.fmt(root.messageCount) + (root.messageCount === 1 ? " message · " : " messages · ") + root.fmt(root.unreadCount) + " unread"
      dim: true
      font.pixelSize: Style.font.caption
    }

    Item { Layout.fillWidth: true }

    UiText {
      text: root.pendingText !== "" ? root.pendingHelp : (root.notice !== "" ? root.notice : root.hints)
      dim: root.pendingText === "" && root.notice === ""
      foreground: root.pendingText !== "" ? Color.accent : (root.notice !== "" ? Color.urgent : Color.foreground)
      font.pixelSize: Style.font.caption
    }

    UiText {
      text: "  :  commands"
      color: Color.accent
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    UiText {
      text: root.backendOnline ? "online" : "offline"
      color: root.backendOnline ? Color.accent : Color.urgent
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
}
