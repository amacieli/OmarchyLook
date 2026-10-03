import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../common"

// Folder list for the mail view. Model roles: id, display_name, unread_item_count.
Item {
  id: root

  property var model
  property int currentIndex: 0
  property string selectedId: ""
  property bool paneFocused: false

  signal folderClicked(int index)
  signal refreshRequested()

  implicitWidth: Style.space(180)
  clip: true

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.spacing.md
    spacing: Style.spacing.sm

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.spacing.sm

      PanelSectionHeader {
        text: "FOLDERS"
        Layout.fillWidth: true
      }

      PanelActionButton {
        iconText: "\uf021"
        tooltipText: "Refresh folders"
        onClicked: root.refreshRequested()
      }
    }

    ListView {
      id: list
      Layout.fillWidth: true
      Layout.fillHeight: true
      model: root.model
      clip: true
      interactive: false          // keyboard-driven; mouse via delegates
      spacing: Style.spacing.xxs
      currentIndex: root.currentIndex
      onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

      delegate: Item {
        id: rowItem
        width: list.width
        height: folderButton.implicitHeight

        Button {
          id: folderButton
          anchors.fill: parent
          leftAlign: true
          text: model.display_name
          selected: model.id === root.selectedId
          hasCursor: root.paneFocused && root.currentIndex === index
          onClicked: root.folderClicked(index)
        }

        UiText {
          visible: model.unread_item_count > 0
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          text: model.unread_item_count > 99 ? "99+" : String(model.unread_item_count)
          dim: true
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
