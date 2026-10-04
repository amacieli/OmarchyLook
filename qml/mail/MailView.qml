import QtQuick
import QtQuick.Layouts
import "../common"

// Composes the message list and the reading pane. Glue only: data + intents
// come from the shared AppState.
RowLayout {
  id: root

  required property var app

  readonly property int pageRows: messages.pageRows
  readonly property bool editing: preview.editing

  spacing: 0

  MessageList {
    id: messages
    Layout.preferredWidth: implicitWidth
    Layout.fillHeight: true
    model: root.app.messageModel
    folderName: root.app.selectedFolderName
    status: root.app.messagesStatus
    currentIndex: root.app.msgIndex
    paneFocused: root.app.focusPane === "msg"
    onRowClicked: function(i) { root.app.clickMessage(i) }
    onEndReached: root.app.loadMoreMessages()
    onRefreshRequested: { root.app.loadMessages(); root.app.focusRequested() }
  }

  VSeparator { Layout.preferredWidth: 1; Layout.fillHeight: true }

  MessagePreview {
    id: preview
    Layout.fillWidth: true
    Layout.fillHeight: true
    message: root.app.currentMessage
    onToggleReadRequested: root.app.toggleRead()
    onToggleHtmlRequested: root.app.toggleHtml()
    htmlMode: root.app.currentHtmlMode
    htmlOffer: root.app.currentHtmlOffer
    onViewAsHtmlRequested: function(scope) { root.app.viewAsHtml(scope); root.app.focusRequested() }
    imagesAllowed: root.app.currentImagesAllowed
    onUnblockRequested: function(scope) { root.app.unblockImages(scope); root.app.focusRequested() }
    onFocusRequested: root.app.focusRequested()
    body: root.app.currentBody
  }
}
