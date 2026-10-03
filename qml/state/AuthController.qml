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

  // Set when a sign-in was for a mailbox that is already signed in:
  // { pending_id, account_id, email } — the UI must ask before anything is replaced.
  property var reauthPrompt: null

  function answerReauth(decision) {
    var prompt = root.reauthPrompt
    if (!prompt) return
    root.reauthPrompt = null
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState === XMLHttpRequest.DONE) root.accountsChanged()
    }
    xhr.open("POST", root.backendUrl + "/auth/confirm?pending=" + encodeURIComponent(prompt.pending_id)
                     + "&decision=" + decision)
    xhr.send()
  }
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

  // Log in an existing account: the backend reuses its kept token, or says a device
  // flow is needed (then we run the normal login for that provider).
  function loginAccount(accountId, provider) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      var res = {}
      try { res = JSON.parse(xhr.responseText) } catch (e) {}
      if (res.result === "login_required") root.startLogin(res.provider || provider)
      else root.accountsChanged()
    }
    xhr.open("POST", root.backendUrl + "/accounts/login?account=" + encodeURIComponent(accountId))
    xhr.send()
  }

  // Log one account out (sync stops; its token and cached data are kept).
  function logout(accountId) {
    postAccountAction("/auth/logout", accountId)
  }

  // Delete an account: its keyring token and everything cached for it.
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
      if (data.confirm_reauth) {
        root.reauthPrompt = data.confirm_reauth
        root.showModal = false
        countdown.stop()
        root.userCode = ""
      } else {
        root.reauthPrompt = null
      }
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
