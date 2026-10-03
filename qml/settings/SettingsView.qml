import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../common"
import "pages"

// Settings: category list on the left, one sub-page on the right. Add a
// category by (1) adding it to AppState.settingsCategories and (2) adding a
// case to `pageFor` below.
RowLayout {
  id: root

  required property var app

  signal loginRequested()
  signal logoutRequested()

  // True while the active page has an input that owns the keyboard.
  readonly property bool editing: pageLoader.item ? pageLoader.item.editing === true : false

  spacing: 0

  // ---- category list
  Item {
    Layout.preferredWidth: Style.space(200)
    Layout.fillHeight: true

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.spacing.md
      spacing: Style.spacing.sm

      PanelSectionHeader {
        text: "SETTINGS"
        Layout.leftMargin: Style.spacing.sm
      }

      Repeater {
        model: root.app.settingsCategories

        Button {
          required property var modelData
          required property int index
          Layout.fillWidth: true
          leftAlign: true
          iconText: modelData.icon
          text: modelData.label
          selected: root.app.settingsCategoryIndex === index
          hasCursor: root.app.focusPane === "msg" && root.app.settingsCategoryIndex === index
          onClicked: root.app.clickCategory(index)
        }
      }

      Item { Layout.fillHeight: true }
    }
  }

  VSeparator { Layout.preferredWidth: 1; Layout.fillHeight: true }

  // ---- active page
  ScrollView {
    id: scroll
    Layout.fillWidth: true
    Layout.fillHeight: true
    clip: true
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

    Loader {
      id: pageLoader
      x: Style.space(20)
      y: Style.space(16)
      width: scroll.availableWidth - Style.space(40)
      sourceComponent: {
        switch (root.app.settingsCategories[root.app.settingsCategoryIndex].id) {
          case "account":       return accountPage
          case "appearance":    return appearancePage
          case "mail":          return mailPage
          case "calendar":      return calendarPage
          case "notifications": return notificationsPage
          default:              return aboutPage
        }
      }
    }
  }

  Component {
    id: accountPage
    AccountPage {
      accounts: root.app.accounts
      isAuthenticated: root.app.auth.isAuthenticated
      onLoginRequested: root.loginRequested()
      onLogoutRequested: root.logoutRequested()
    }
  }
  Component {
    id: appearancePage
    AppearancePage {
      sidebarExpanded: root.app.sidebarExpanded
      onSidebarExpandedToggled: root.app.sidebarExpanded = !root.app.sidebarExpanded
    }
  }
  Component { id: mailPage;          MailPage {} }
  Component { id: calendarPage;      CalendarPage {} }
  Component { id: notificationsPage; NotificationsPage {} }
  Component {
    id: aboutPage
    AboutPage {
      backendUrl: root.app.backendUrl
      configDir: root.app.configDir
      backendOnline: root.app.backendOnline
    }
  }
}
