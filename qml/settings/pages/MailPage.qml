import QtQuick
import qs.Commons
import qs.Ui
import "../../common"
import ".."

// Only "Message rendering" is wired to the backend (settings.toml); the other values
// are placeholders and are not persisted.
SettingsPage {
  id: page

  property var app: null

  property string syncInterval: "5"
  property int markReadDelay: 2
  property bool conversationView: true

  editing: signature.activeFocus || syncDropdown.popupOpen || delay.field.activeFocus || renderingDropdown.popupOpen

  title: "Mail"
  description: "Sync behaviour and reading preferences."
  placeholder: true

  Column {
    width: parent.width
    spacing: Style.space(6)

    PanelSectionHeader { text: "SYNC" }
    Dropdown {
      id: syncDropdown
      width: parent.width
      label: "Check for new mail"
      value: page.syncInterval
      options: [
        { value: "1",  label: "Every minute" },
        { value: "5",  label: "Every 5 minutes" },
        { value: "15", label: "Every 15 minutes" },
        { value: "0",  label: "Manually" }
      ]
      onChanged: function(v) { page.syncInterval = v }
    }
  }

  PanelSeparator { width: parent.width }

  Column {
    width: parent.width
    spacing: Style.space(6)

    PanelSectionHeader { text: "MESSAGE RENDERING" }
    Dropdown {
      id: renderingDropdown
      width: parent.width
      label: "Show messages as"
      value: page.app ? page.app.messageRendering : "system_sender"
      options: [
        { value: "html",          label: "Always HTML" },
        { value: "system",        label: "Always System" },
        { value: "system_sender", label: "Always System with per-sender override" }
      ]
      onChanged: function(v) { if (page.app) page.app.setMessageRendering(v) }
    }
    UiText {
      width: parent.width
      text: page.app && page.app.messageRendering === "system_sender"
        ? "System font, except for senders marked \"Always HTML\" under Senders."
        : "The HTML / System button on a message still overrides this for that message."
      dim: true
      wrapMode: Text.WordWrap
      font.pixelSize: Style.font.caption
    }
  }

  PanelSeparator { width: parent.width }

  Toggle {
    width: parent.width
    label: "Conversation view"
    description: page.conversationView ? "Messages grouped by thread" : "Flat message list"
    checked: page.conversationView
    onClicked: page.conversationView = !page.conversationView
  }

  NumberField {
    id: delay
    label: "Mark as read after (seconds)"
    value: page.markReadDelay
    from: 0
    to: 60
    onModified: function(v) { page.markReadDelay = v }
  }

  Column {
    width: parent.width
    spacing: Style.space(6)

    PanelSectionHeader { text: "SIGNATURE" }
    TextField {
      id: signature
      width: parent.width
      placeholderText: "Appended to new messages"
    }
  }
}
