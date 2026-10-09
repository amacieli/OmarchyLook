import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../common"

// SMS: placeholder. Will show phone conversations (thread list + message pane) read from,
// and sent through, the paired phone via KDE Connect (kdeconnectd over D-Bus).
// Nothing here talks to the phone yet; set it up under Settings -> SMS.
Rectangle {
  id: root
  color: "transparent"

  ColumnLayout {
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(40), Style.space(420))
    spacing: Style.space(10)

    UiText {
      Layout.alignment: Qt.AlignHCenter
      text: "\uf27a"
      font.pixelSize: Style.space(40)
      dim: true
    }
    UiText {
      Layout.alignment: Qt.AlignHCenter
      text: "SMS"
      font.pixelSize: Style.font.heading
      font.bold: true
    }
    UiText {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      dim: true
      text: "Placeholder. Text messages from your phone will appear here once KDE Connect is installed and paired (Settings \u203a SMS)."
    }
  }
}
