import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../../common"
import ".."

// Accounts: add a mail account of any provider, then manage every signed-in
// account below. Only the Exchange/Microsoft sign-in is backed by the daemon
// today; the other providers are listed so the flow is in place for them.
SettingsPage {
  id: page

  // [{ id, provider, email, signed_in }] from GET /accounts
  property var accounts: []
  property bool isAuthenticated: false

  property string newProvider: "exchange"
  property string notice: ""

  signal loginRequested()
  signal logoutRequested()

  editing: providerDropdown.popupOpen

  readonly property var providerOptions: [
    { value: "exchange", label: "Exchange" },
    { value: "outlook",  label: "Outlook" },
    { value: "gmail",    label: "Gmail" },
    { value: "yahoo",    label: "Yahoo Mail" },
    { value: "icloud",   label: "iCloud Mail" },
    { value: "aol",      label: "AOL Mail" },
    { value: "zoho",     label: "Zoho Mail" },
    { value: "fastmail", label: "Fastmail" },
    { value: "gmx",      label: "GMX Mail" },
    { value: "proton",   label: "Proton Mail (Bridge)" },
    { value: "imap",     label: "IMAP account" },
    { value: "smtp",     label: "SMTP account" }
  ]

  function providerLabel(id) {
    for (var i = 0; i < providerOptions.length; i++)
      if (providerOptions[i].value === id) return providerOptions[i].label
    return id
  }

  function addAccount() {
    var microsoft = page.newProvider === "exchange" || page.newProvider === "outlook"
    if (!microsoft) {
      page.notice = page.providerLabel(page.newProvider) + " sign-in isn't supported by the backend yet."
    } else if (page.accounts.length > 0 || page.isAuthenticated) {
      page.notice = "Only one Microsoft account can be signed in right now — multi-account support is still to come."
    } else {
      page.notice = ""
      page.loginRequested()
    }
  }

  title: "Accounts"
  description: "Add mail accounts and manage the ones you're signed in to."

  Column {
    width: parent.width
    spacing: Style.space(8)

    PanelSectionHeader { text: "ADD ACCOUNT" }

    RowLayout {
      width: parent.width
      spacing: Style.spacing.lg

      Dropdown {
        id: providerDropdown
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        showLabel: false
        value: page.newProvider
        options: page.providerOptions
        onChanged: function(v) { page.newProvider = v; page.notice = "" }
      }

      Button {
        Layout.alignment: Qt.AlignVCenter
        bordered: true
        iconText: "\uf067"
        text: "Add"
        onClicked: page.addAccount()
      }
    }

    UiText {
      visible: page.notice !== ""
      width: parent.width
      text: page.notice
      dim: true
      wrapMode: Text.WordWrap
    }

    PanelSeparator { width: parent.width }

    UiText {
      visible: page.accounts.length === 0
      width: parent.width
      text: "No accounts signed in."
      dim: true
    }

    Repeater {
      model: page.accounts
      delegate: Column {
        required property var modelData
        width: parent.width
        spacing: Style.space(4)

        PanelSectionHeader { text: page.providerLabel(modelData.provider).toUpperCase() + " ACCOUNT" }

        RowLayout {
          width: parent.width
          spacing: Style.spacing.lg

          UiText {
            Layout.fillWidth: true
            text: modelData.email !== "" ? modelData.email : "loading…"
            dim: modelData.email === ""
            elide: Text.ElideRight
          }
          UiText {
            text: modelData.signed_in ? "signed in" : "signed out"
            foreground: modelData.signed_in ? Color.accent : Color.foreground
            dim: !modelData.signed_in
          }
          Button {
            bordered: true
            iconText: "\uf2f5"
            text: "Log out"
            onClicked: page.logoutRequested()
          }
        }
      }
    }
  }
}
