import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../common"
import "Commands.js" as Cmd

// `?` — every key binding, generated from the registry and grouped by where it works.
// Groups that apply to the current pane lead and are marked. j/k/PgUp/PgDn scroll;
// Esc, q or ? close.
FocusScope {
  id: root

  property var commands: []
  property var scopes: ["global"]
  property bool open: false

  signal closed()

  visible: open
  function show() { open = true; flick.contentY = 0; forceActiveFocus() }
  function hide() { if (!open) return; open = false; closed() }

  readonly property var groups: Cmd.grouped(commands, scopes)

  Rectangle { anchors.fill: parent; color: "#B3000000" }
  MouseArea { anchors.fill: parent; onClicked: root.hide() }

  Keys.priority: Keys.BeforeItem
  Keys.onPressed: function(e) {
    var step = flick.height * 0.9
    if (e.key === Qt.Key_Escape || e.text === "q" || e.text === "?") hide()
    else if (e.key === Qt.Key_Down || e.text === "j") flick.contentY = Math.min(flick.contentY + 40, Math.max(0, flick.contentHeight - flick.height))
    else if (e.key === Qt.Key_Up || e.text === "k") flick.contentY = Math.max(0, flick.contentY - 40)
    else if (e.key === Qt.Key_PageDown || e.key === Qt.Key_Space) flick.contentY = Math.min(flick.contentY + step, Math.max(0, flick.contentHeight - flick.height))
    else if (e.key === Qt.Key_PageUp || e.text === "b") flick.contentY = Math.max(0, flick.contentY - step)
    else if (e.text === "g" || e.key === Qt.Key_Home) flick.contentY = 0
    else if (e.text === "G" || e.key === Qt.Key_End) flick.contentY = Math.max(0, flick.contentHeight - flick.height)
    else return
    e.accepted = true
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(60), Style.space(760))
    height: parent.height - Style.space(80)
    color: Color.background
    border.width: 2
    border.color: Color.accent

    MouseArea { anchors.fill: parent }

    UiText {
      id: heading
      x: Style.spacing.xl; y: Style.spacing.lg
      text: "Keyboard help"
      font.bold: true
      font.pixelSize: Style.font.subtitle
      foreground: Color.accent
    }
    UiText {
      anchors.right: parent.right; anchors.rightMargin: Style.spacing.xl
      y: Style.spacing.lg
      text: "j/k scroll   esc close"
      dim: true
      font.pixelSize: Style.font.caption
    }

    Flickable {
      id: flick
      anchors.fill: parent
      anchors.topMargin: heading.y + heading.height + Style.spacing.lg
      anchors.margins: Style.spacing.xl
      contentWidth: width
      contentHeight: body.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: body
        width: flick.width
        spacing: Style.spacing.lg

        Repeater {
          model: root.groups

          Column {
            required property var modelData
            width: body.width
            spacing: Style.spacing.xs

            UiText {
              text: modelData.name + (modelData.active ? "   ← active here" : "")
              font.bold: true
              foreground: modelData.active ? Color.accent : Color.foreground
            }
            Rectangle { width: parent.width; height: 1; color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2) }

            Repeater {
              model: modelData.commands
              Row {
                required property var modelData
                spacing: Style.spacing.lg
                UiText {
                  width: Style.space(190)
                  text: Cmd.keyLabel(modelData.keys)
                  foreground: Color.accent
                  elide: Text.ElideRight
                }
                UiText { text: modelData.title + (modelData.ex ? "   :" + modelData.ex[0] : ""); dim: false }
              }
            }
          }
        }
      }
    }
  }
}
