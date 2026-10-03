import QtQuick
import qs.Commons
import qs.Ui
import "../../common"
import ".."

// Real page: Microsoft sign-in / sign-out.
SettingsPage {
  id: page

  property bool isAuthenticated: false

  signal loginRequested()
  signal logoutRequested()

  title: "Account"
  description: "Sign in with your Microsoft account to sync mail, calendar, people and tasks."

  Column {
    width: parent.width
    spacing: Style.space(8)

    PanelSectionHeader { text: "MICROSOFT ACCOUNT" }

    UiText {
      width: parent.width
      text: page.isAuthenticated ? "Signed in — mail sync is active." : "Signed out — start device-code sign-in below."
      foreground: page.isAuthenticated ? Color.accent : Color.foreground
      dim: !page.isAuthenticated
      wrapMode: Text.WordWrap
    }

    Button {
      width: parent.width
      bordered: true
      iconText: page.isAuthenticated ? "\uf2f5" : "\uf090"
      text: page.isAuthenticated ? "Log out" : "Log in with Microsoft"
      onClicked: page.isAuthenticated ? page.logoutRequested() : page.loginRequested()
    }
  }
}
