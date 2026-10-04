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

  readonly property string hints: {
    if (focusPane === "nav")    return "j/k move   l open   s next pane   esc close"
    if (focusPane === "folder") return "j/k move   l select   h back   s next pane"
    return currentView === "settings" ? "j/k category   h back   s next pane"
                                      : "j/k move   h back   s next pane"
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
      text: root.hints
      dim: true
      font.pixelSize: Style.font.caption
    }

    UiText {
      text: root.backendOnline ? "online" : "offline"
      color: root.backendOnline ? Color.accent : Color.urgent
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
}
