import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../common"

// Left menu bar. Presentational: owns no state, reports clicks via signals.
//   items: [{ icon, label, view, pinned? }]  (pinned items sit at the bottom)
Item {
  id: root

  PaneFrame { tint: Hues.magenta; focused: root.paneFocused; hotkey: "\u00b9"; title: root.expanded ? "menu" : "" }

  property var items: []
  property int currentIndex: 0
  property bool expanded: true
  property bool paneFocused: false
  property bool cursorOnToggle: false

  signal itemClicked(int index)
  signal toggleClicked()

  implicitWidth: expanded ? Style.space(180) : Style.space(56)
  Behavior on implicitWidth { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
  clip: true

  component NavButton: Button {
    required property var modelData
    required property int index
    Layout.fillWidth: true
    leftAlign: true
    iconText: modelData.icon
    text: root.expanded ? modelData.label : ""
    tooltipText: root.expanded ? "" : modelData.label
    selected: root.currentIndex === index
    hasCursor: root.paneFocused && !root.cursorOnToggle && root.currentIndex === index
    onClicked: root.itemClicked(index)
  }

  ColumnLayout {
    anchors.fill: parent; anchors.topMargin: Style.spacing.lg
    anchors.margins: Style.spacing.md
    spacing: Style.spacing.xs

    Button {
      Layout.fillWidth: true
      leftAlign: true
      iconText: root.expanded ? "\u25bc" : "\u25b6"
      iconSize: Style.font.caption
      tooltipText: root.expanded ? "Collapse sidebar" : "Expand sidebar"
      hasCursor: root.paneFocused && root.cursorOnToggle
      onClicked: root.toggleClicked()
    }

    Repeater {
      model: root.items
      NavButton { visible: modelData.pinned !== true }
    }

    Item { Layout.fillHeight: true }

    Repeater {
      model: root.items
      NavButton { visible: modelData.pinned === true }
    }
  }
}
