import QtQuick
import Quickshell
import Quickshell.Io

// Microsoft device-code login state. The Rust backend writes auth_state.json
// and device_code.json into the config dir; we watch those files (no polling)
// and POST login/logout intents to the backend.
Item {
  id: root

  property string backendUrl: ""
  property string configDir: ""

  property bool isAuthenticated: false
  property bool showModal: false
  property string userCode: ""
  property string verificationUri: ""
  property int secondsRemaining: 0
  property string errorMessage: ""

  // Bumped by the backend after each completed login/sign-out (also while another
  // account is already signed in, when isAuthenticated doesn't change).
  property double loginSerial: 0
  signal accountsChanged()

  function startLogin(provider) {
    userCode = ""
    verificationUri = ""
    secondsRemaining = 0
    errorMessage = ""
    showModal = true

    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (xhr.status === 200) codeFile.reload()
      else root.errorMessage = "Failed to start authentication (backend not ready?)"
    }
    xhr.open("POST", root.backendUrl + "/auth/login?provider=" + encodeURIComponent(provider || "exchange"))
    xhr.send()
  }

  // Sign one account out (tokens removed, cached data kept).
  function logout(accountId) {
    postAccountAction("/auth/logout", accountId)
  }

  // Delete an account and everything cached for it.
  function removeAccount(accountId) {
    postAccountAction("/accounts/remove", accountId)
  }

  function postAccountAction(path, accountId) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.DONE) root.accountsChanged()
    }
    xhr.open("POST", root.backendUrl + path + "?account=" + encodeURIComponent(accountId))
    xhr.send()
    // authFile watcher picks up the resulting state change.
  }

  function cancel() {
    showModal = false
    countdown.stop()
  }

  function applyAuthState(raw) {
    try {
      var data = JSON.parse(raw)
      var was = root.isAuthenticated
      root.isAuthenticated = data.is_authenticated === true
      if (data.error) root.errorMessage = data.error
      var serial = data.login_serial || 0
      if (serial !== root.loginSerial) {
        root.loginSerial = serial
        if (serial > 0) {
          if (root.isAuthenticated && !data.error) { root.showModal = false; countdown.stop(); root.userCode = "" }
          root.accountsChanged()
        }
      }
      if (!was && root.isAuthenticated) {
        root.showModal = false
        countdown.stop()
        root.userCode = ""
        root.errorMessage = ""
      }
    } catch (e) { /* partial write; the next change event re-reads */ }
  }

  function applyDeviceCode(raw) {
    if (!root.showModal) return
    try {
      var data = JSON.parse(raw)
      if (data.user_code && data.user_code !== root.userCode) {
        root.userCode = data.user_code
        root.verificationUri = data.verification_uri || "https://microsoft.com/devicelogin"
        root.secondsRemaining = data.expires_in || 900
        countdown.restart()
      }
    } catch (e) { /* not ready yet */ }
  }

  FileView {
    id: authFile
    path: root.configDir + "/auth_state.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyAuthState(text())
    onFileChanged: reload()
    onLoadFailed: root.isAuthenticated = false
  }

  FileView {
    id: codeFile
    path: root.configDir + "/device_code.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyDeviceCode(text())
    onFileChanged: reload()
  }

  Timer {
    id: countdown
    interval: 1000
    repeat: true
    onTriggered: {
      if (root.secondsRemaining > 0) {
        root.secondsRemaining -= 1
      } else {
        root.errorMessage = "Device code expired. Please try again."
        stop()
      }
    }
  }
}
