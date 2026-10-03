import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../common"

// Title, search entry, backend/sync indicator and account shortcut.
Item {
  id: root

  property bool backendOnline: false
  property bool isAuthenticated: false
  property string viewLabel: ""

  readonly property bool searchFocused: search.activeFocus

  signal accountClicked()

  implicitHeight: row.implicitHeight + Style.spacing.lg * 2

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.xl
    anchors.rightMargin: Style.spacing.xl
    spacing: Style.spacing.xl

    UiText {
      text: "OmarchyLook"
      font.pixelSize: Style.font.title
      font.bold: true
    }

    UiText {
      visible: root.viewLabel !== ""
      text: "› " + root.viewLabel
      dim: true
      font.pixelSize: Style.font.subtitle
    }

    Item { Layout.fillWidth: true }

    TextField {
      id: search
      Layout.preferredWidth: Style.space(240)
      placeholderText: "Search…"
      // Placeholder: not yet wired to a backend search endpoint.
    }

    // Backend / sync state: accent = reachable, urgent = offline.
    PanelActionButton {
      iconText: root.backendOnline ? "\uf00c" : "\uf071"
      foreground: root.backendOnline ? Color.foreground : Color.urgent
      tooltipText: root.backendOnline ? "Backend connected" : "Backend offline"
    }

    PanelActionButton {
      iconText: "\uf007"
      foreground: root.isAuthenticated ? Color.accent : Color.foreground
      tooltipText: root.isAuthenticated ? "Signed in — open account settings" : "Signed out — open account settings"
      onClicked: root.accountClicked()
    }
  }
}
