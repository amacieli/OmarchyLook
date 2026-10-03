import QtQuick
import QtQuick.Layouts
import "../common"

// Composes the message list and the reading pane. Glue only: data + intents
// come from the shared AppState.
RowLayout {
  id: root

  required property var app

  spacing: 0

  MessageList {
    Layout.preferredWidth: implicitWidth
    Layout.fillHeight: true
    model: root.app.messageModel
    folderName: root.app.selectedFolderName
    status: root.app.messagesStatus
    currentIndex: root.app.msgIndex
    paneFocused: root.app.focusPane === "msg"
    onRowClicked: function(i) { root.app.clickMessage(i) }
    onRefreshRequested: { root.app.loadMessages(); root.app.focusRequested() }
  }

  VSeparator { Layout.preferredWidth: 1; Layout.fillHeight: true }

  MessagePreview {
    Layout.fillWidth: true
    Layout.fillHeight: true
    message: root.app.currentMessage
  }
}
