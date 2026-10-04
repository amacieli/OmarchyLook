import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../common"
import "format.js" as Fmt

// Message list pane. Model roles: from_name, from_email, subject,
// received_at, is_read.
Item {
  id: root

  property var model
  property string folderName: "Inbox"
  property string status: ""
  property int currentIndex: 0
  property bool paneFocused: false

  // Rows that fit in one screenful (less one for overlap): the step PageUp/PageDown take.
  readonly property int pageRows: list.count > 0 && list.contentHeight > 0
    ? Math.max(1, Math.floor(list.height / (list.contentHeight / list.count)) - 1) : 1

  signal rowClicked(int index)
  signal refreshRequested()
  signal endReached()   // scrolled (or j/k'd) near the bottom: ask for the next page

  implicitWidth: Style.space(360)

  ColumnLayout {
    anchors.fill: parent
    spacing: 0

    // ---- header
    RowLayout {
      Layout.fillWidth: true
      Layout.margins: Style.spacing.lg
      spacing: Style.spacing.md

      UiText {
        text: "\uf0e0"
        foreground: root.paneFocused ? Color.accent : Color.foreground
        font.pixelSize: Style.font.icon
      }

      UiText {
        text: root.folderName
        Layout.fillWidth: true
        elide: Text.ElideRight
        foreground: root.paneFocused ? Color.accent : Color.foreground
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      UiText {
        text: root.status
        dim: true
        font.pixelSize: Style.font.caption
      }

      PanelActionButton {
        iconText: "\uf021"
        tooltipText: "Refresh messages"
        onClicked: root.refreshRequested()
      }
    }

    PanelSeparator { Layout.fillWidth: true }

    // ---- list
    ListView {
      id: list
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ThemedScrollBar {}
      model: root.model
      currentIndex: root.currentIndex
      onCurrentIndexChanged: {
        positionViewAtIndex(currentIndex, ListView.Contain)
        if (currentIndex >= count - 20) root.endReached()
      }
      onAtYEndChanged: if (atYEnd && count > 0) root.endReached()
      onContentYChanged: if (count > 0 && contentY + height > contentHeight - height * 2) root.endReached()

      UiText {
        anchors.centerIn: parent
        visible: list.count === 0
        text: root.status.length > 0 && root.status !== "…" ? root.status : "no messages"
        dim: true
      }

      delegate: BorderSurface {
        id: row
        width: list.width
        height: content.implicitHeight + Style.spacing.lg * 2

        readonly property bool hasCursor: root.paneFocused && root.currentIndex === index
        readonly property bool isCurrent: root.currentIndex === index
        readonly property bool unread: !model.is_read

        radius: Style.cornerRadius
        color: hasCursor ? Style.hoverFillFor(Color.foreground, Color.accent)
             : isCurrent ? Style.selectedFillFor(Color.foreground, Color.accent)
             : mouse.containsMouse ? Style.normalFillFor(Color.foreground, Color.accent)
             : "transparent"
        borderSpec: hasCursor ? Border.controlSpec("hover-cursor", Color.foreground, Color.accent) : Border.none()

        // unread strip
        Rectangle {
          visible: row.unread
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Style.space(2)
          color: Color.accent
        }

        RowLayout {
          id: content
          anchors.fill: parent
          anchors.leftMargin: Style.spacing.xl
          anchors.rightMargin: Style.spacing.lg
          anchors.topMargin: Style.spacing.lg
          anchors.bottomMargin: Style.spacing.lg
          spacing: Style.spacing.md

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.xxs

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.md

              UiText {
                text: Fmt.senderName(model)
                Layout.fillWidth: true
                elide: Text.ElideRight
                dim: !row.unread
                font.bold: row.unread
              }

              UiText {
                text: Fmt.listDate(model.received_at)
                dim: true
                font.pixelSize: Style.font.caption
              }
            }

            UiText {
              text: model.subject || "(no subject)"
              Layout.fillWidth: true
              elide: Text.ElideRight
              dim: true
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.rowClicked(index)
        }
      }
    }
  }
}
