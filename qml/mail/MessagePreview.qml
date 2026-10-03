import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../common"
import "format.js" as Fmt

// Reading pane. `message` is the model row (or null for the empty state).
Item {
  id: root

  property var message: null

  signal replyRequested()
  signal forwardRequested()
  signal toggleReadRequested()

  // ---- empty state
  ColumnLayout {
    anchors.centerIn: parent
    visible: !root.message
    spacing: Style.spacing.md

    UiText {
      Layout.alignment: Qt.AlignHCenter
      text: "\uf0e0"
      dim: true
      opacity: 0.5
      font.pixelSize: Style.font.displayLarge
    }
    UiText {
      Layout.alignment: Qt.AlignHCenter
      text: "select a message"
      dim: true
      opacity: 0.5
      font.pixelSize: Style.font.bodySmall
    }
  }

  // ---- message
  ColumnLayout {
    anchors.fill: parent
    visible: !!root.message
    spacing: 0

    // header
    ColumnLayout {
      Layout.fillWidth: true
      Layout.margins: Style.spacing.huge
      spacing: Style.spacing.md

      UiText {
        text: (root.message && root.message.subject) || "(no subject)"
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.md

        BorderSurface {
          implicitWidth: chip.implicitWidth + Style.spacing.lg * 2
          implicitHeight: chip.implicitHeight + Style.spacing.sm * 2
          radius: Style.cornerRadius
          color: Style.selectedFillFor(Color.accent, Color.accent)
          borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)

          UiText {
            id: chip
            anchors.centerIn: parent
            text: Fmt.senderName(root.message)
            foreground: Color.accent
            font.pixelSize: Style.font.caption
          }
        }

        UiText {
          text: root.message && root.message.from_email ? "<" + root.message.from_email + ">" : ""
          Layout.fillWidth: true
          elide: Text.ElideRight
          dim: true
          font.pixelSize: Style.font.caption
        }

        UiText {
          text: Fmt.fullDate(root.message ? root.message.received_at : "")
          dim: true
          font.pixelSize: Style.font.caption
        }
      }

      UiText {
        visible: text.length > 0
        text: Fmt.recipients(root.message)
        Layout.fillWidth: true
        elide: Text.ElideRight
        dim: true
        font.pixelSize: Style.font.caption
      }
    }

    PanelSeparator { Layout.fillWidth: true }

    // actions
    RowLayout {
      Layout.fillWidth: true
      Layout.margins: Style.spacing.lg
      spacing: Style.spacing.md

      Button {
        text: "reply"
        iconText: "\uf112"
        bordered: true
        onClicked: root.replyRequested()
      }
      Button {
        text: "forward"
        iconText: "\uf064"
        bordered: true
        onClicked: root.forwardRequested()
      }

      Item { Layout.fillWidth: true }

      Button {
        text: root.message && root.message.is_read ? "mark unread" : "mark read"
        iconText: root.message && root.message.is_read ? "\uf2b6" : "\uf2b7"
        onClicked: root.toggleReadRequested()
      }
    }

    PanelSeparator { Layout.fillWidth: true }

    // body
    ScrollView {
      id: scroll
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

      UiText {
        width: scroll.availableWidth
        leftPadding: Style.spacing.huge
        rightPadding: Style.spacing.huge
        topPadding: Style.spacing.xxxl
        bottomPadding: Style.spacing.huge * 1.3
        text: Fmt.body(root.message)
        wrapMode: Text.WordWrap
        lineHeight: 1.4
      }
    }
  }
}
