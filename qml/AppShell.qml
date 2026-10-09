import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "nav"
import "mail"
import "chrome"
import "auth"
import "settings"
import "views"
import "state"
import "common"

// Window content: wires the state object to the presentational components and
// owns keyboard dispatch. No styling or backend logic lives here.
FocusScope {
  id: root

  signal closeRequested()

  function focusKeys() { keyCatcher.forceActiveFocus() }

  AppState {
    id: appState
    onFocusRequested: root.focusKeys()
    onCloseRequested: root.closeRequested()
  }

  Component.onCompleted: root.focusKeys()

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent

    // Hand keys to text inputs / popups while they own focus.
    blocked: topBar.searchFocused || settingsEditing || appState.auth.showModal

    // A page (settings fields, the mail view's image dropdown) owns the keyboard.
    readonly property bool settingsEditing: contentLoader.item && contentLoader.item.editing === true

    onMoveRequested: function(dx, dy) { appState.moveCursor(dx, dy) }
    onActivateRequested: appState.activate()
    onCloseRequested: appState.back()
    onTextKey: function(t) {
      if (t === "s") appState.cycleFocus()
      else if (appState.currentView === "mail" && !appState.composing) {
        if (t === "c") appState.openCompose("new")
        else if (t === "r") appState.openCompose("reply")
        else if (t === "a") appState.openCompose("replyAll")
        else if (t === "f") appState.openCompose("forward")
      }
      // `u` takes back the message that is still inside its send delay.
      if (t === "u" && !appState.composing) appState.undoLatest()
    }

    // PageUp/PageDown move the cursor a screenful in the pane that has it. Qt's
    // `Keys` has no page-key signal, so these are Shortcuts, switched off while a
    // text field or the auth modal owns the keyboard (`blocked`).
    function page(dir) {
      var v = appState.currentView
      if (v === "contacts") {
        if (contentLoader.item && contentLoader.item.pageScroll) contentLoader.item.pageScroll(dir)
      } else if (appState.focusPane === "folder") {
        appState.moveVertical(dir * folderBar.pageRows)
      } else if (appState.focusPane === "msg" && v === "mail") {
        appState.moveVertical(dir * (contentLoader.item ? contentLoader.item.pageRows : 1))
      }
    }

    Shortcut { sequences: ["Ctrl+N"]; enabled: appState.currentView === "mail" && !appState.composing; onActivated: appState.openCompose("new") }
    Shortcut { sequences: ["PgUp"];   enabled: !keyCatcher.blocked; onActivated: keyCatcher.page(-1) }
    Shortcut { sequences: ["PgDown"]; enabled: !keyCatcher.blocked; onActivated: keyCatcher.page(1) }

    // Esc must still dismiss the auth modal even though `blocked` is set.
    Keys.priority: Keys.BeforeItem
    Keys.onEscapePressed: function(event) {
      // Specific key handlers accept by default; only swallow Esc for the modal.
      event.accepted = appState.auth.showModal
      if (event.accepted) appState.auth.cancel()
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: 0

      TopStatusBar {
        id: topBar
        Layout.fillWidth: true
        backendOnline: appState.backendOnline
        isAuthenticated: appState.auth.isAuthenticated
        viewLabel: appState.currentViewLabel
        onAccountClicked: appState.openSettingsCategory("account")
      }

      PanelSeparator { Layout.fillWidth: true }

      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 0

        NavBar {
          Layout.preferredWidth: implicitWidth
          Layout.fillHeight: true
          items: appState.navItems
          currentIndex: appState.navIndex
          expanded: appState.sidebarExpanded
          paneFocused: appState.focusPane === "nav"
          cursorOnToggle: appState.navOnToggle
          onItemClicked: function(i) { appState.clickNav(i) }
          onToggleClicked: appState.clickNavToggle()
        }

        VSeparator { Layout.preferredWidth: 1; Layout.fillHeight: true }

        FolderBar {
          id: folderBar
          visible: appState.currentView === "mail"
          Layout.preferredWidth: visible ? implicitWidth : 0
          Layout.fillHeight: true
          model: appState.folderModel
          currentIndex: appState.folderIndex
          selectedId: appState.selectedFolderId
          paneFocused: appState.focusPane === "folder"
          onFolderClicked: function(i) { appState.clickFolder(i) }
          onRefreshRequested: { appState.loadFolders(); appState.focusRequested() }
        }

        VSeparator { visible: appState.currentView === "mail"; Layout.preferredWidth: 1; Layout.fillHeight: true }

        Loader {
          id: contentLoader
          Layout.fillWidth: true
          Layout.fillHeight: true
          sourceComponent: {
            switch (appState.currentView) {
              case "settings": return settingsComponent
              case "calendar": return calendarComponent
              case "contacts": return peopleComponent
              case "tasks":    return tasksComponent
              default:         return mailComponent
            }
          }
        }
      }

      PanelSeparator { Layout.fillWidth: true }

      BottomStatusBar {
        Layout.fillWidth: true
        backendOnline: appState.backendOnline
        viewLabel: appState.currentViewLabel
        folderName: appState.selectedFolderName
        messageCount: appState.messageTotal
        unreadCount: appState.unreadCount
        focusPane: appState.focusPane
        currentView: appState.currentView
      }
    }

    Component { id: mailComponent;     MailView { app: appState } }
    Component { id: calendarComponent; CalendarView { mode: appState.calendarMode; onModeChanged: appState.calendarMode = mode; monoFont: Style.font.family; accentColor: Color.accent; successColor: Color.accent; dangerColor: Color.urgent; textColor: Color.foreground } }
    Component { id: peopleComponent;   PeopleView   { viewMode: appState.peopleView; onViewModeChanged: appState.peopleView = viewMode; sortKey: appState.peopleSort; onSortKeyChanged: appState.peopleSort = sortKey; monoFont: Style.font.family; accentColor: Color.accent; successColor: Color.accent; dangerColor: Color.urgent; textColor: Color.foreground } }
    Component { id: tasksComponent;    TasksView    { monoFont: Style.font.family; accentColor: Color.accent; successColor: Color.accent; dangerColor: Color.urgent; textColor: Color.foreground } }
    Component {
      id: settingsComponent
      SettingsView {
        app: appState
        onLoginRequested: function(provider) { appState.auth.startLogin(provider) }
        onAccountLoginRequested: function(accountId, provider) { appState.auth.loginAccount(accountId, provider) }
        onLogoutRequested: function(accountId) { appState.auth.logout(accountId) }
        onRemoveRequested: function(accountId) { appState.auth.removeAccount(accountId) }
      }
    }
  }

  AuthModal {
    anchors.fill: parent
  SendToast {
    app: appState
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: Style.spacing.huge
    anchors.bottomMargin: Style.space(40)      // clear of the bottom status bar
    z: 900
  }

    auth: appState.auth
    z: 1000
  }

  ReauthConfirm {
    anchors.fill: parent
    auth: appState.auth
    z: 1001
  }
}
