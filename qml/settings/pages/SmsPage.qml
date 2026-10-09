import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../../common"
import ".."

// SMS settings (placeholder). Detects KDE Connect and walks through:
//   missing    -> offer to install it
//   unpaired   -> offer to pair (no reachable device / device not paired)
//   paired     -> ready
// Detection shells out to kdeconnect-cli; install/pair actions are stubs that hand off
// to a terminal / kdeconnect-cli and then re-check.
SettingsPage {
  id: page

  // checking | missing | unpaired | paired | error
  property string kcState: "checking"
  // [{ id, name, paired, reachable }]
  property var devices: []
  property string notice: ""

  title: "SMS"
  description: "Read and send text messages through your phone using KDE Connect."
  placeholder: true

  Component.onCompleted: recheck()

  function recheck() {
    page.kcState = "checking"
    page.notice = ""
    which.running = true
  }

  // Parse `kdeconnect-cli -l` lines: "- Name: <id> (paired and reachable)"
  function parseDevices(text) {
    var out = []
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^- (.*): ([0-9a-f_]+)(?: \((.*)\))?\s*$/)
      if (!m) continue
      var flags = m[3] || ""
      out.push({
        name: m[1], id: m[2],
        paired: flags.indexOf("paired") >= 0 && flags.indexOf("unpaired") < 0,
        reachable: flags.indexOf("reachable") >= 0
      })
    }
    return out
  }

  Process {
    id: which
    command: ["sh", "-c", "command -v kdeconnect-cli"]
    onExited: function(code) {
      if (code === 0) list.running = true
      else { page.devices = []; page.kcState = "missing" }
    }
  }

  Process {
    id: list
    command: ["kdeconnect-cli", "-l"]
    stdout: StdioCollector {
      onStreamFinished: {
        page.devices = page.parseDevices(text)
        var anyPaired = page.devices.some(function(d) { return d.paired })
        page.kcState = anyPaired ? "paired" : "unpaired"
      }
    }
    onExited: function(code) { if (code !== 0) page.kcState = "error" }
  }

  Process {
    id: pairProc
    property string deviceId: ""
    command: ["kdeconnect-cli", "-d", deviceId, "--pair"]
    onExited: { page.notice = "Pair request sent. Accept it on your phone, then press Re-check."; }
  }

  Column {
    width: parent.width
    spacing: Style.space(8)

    PanelSectionHeader { text: "KDE CONNECT" }

    UiText {
      width: parent.width
      wrapMode: Text.WordWrap
      font.pixelSize: Style.font.bodySmall
      text: page.kcState === "checking" ? "Checking for KDE Connect\u2026"
          : page.kcState === "missing"  ? "KDE Connect is not installed."
          : page.kcState === "unpaired" ? "KDE Connect is installed, but no phone is paired."
          : page.kcState === "paired"   ? "KDE Connect is installed and a phone is paired."
          : "Could not query KDE Connect (is kdeconnectd running?)."
    }

    // ---- missing: offer install (placeholder: opens a terminal; sudo prompts there)
    Button {
      visible: page.kcState === "missing"
      bordered: true
      iconText: "\uf019"
      text: "Install KDE Connect\u2026"
      tooltipText: "Opens a terminal running: sudo pacman -S --needed kdeconnect"
      onClicked: {
        Quickshell.execDetached(["xdg-terminal-exec", "sh", "-c",
          "sudo pacman -S --needed kdeconnect; echo; read -n1 -p 'Done. Press any key to close.'"])
        page.notice = "Finish the install in the terminal, then press Re-check."
      }
    }

    // ---- unpaired: offer to pair with reachable, unpaired devices
    UiText {
      visible: page.kcState === "unpaired" && page.devices.length === 0
      width: parent.width
      wrapMode: Text.WordWrap
      dim: true
      font.pixelSize: Style.font.bodySmall
      text: "No devices found. Install KDE Connect on your phone, join the same network, then Re-check."
    }

    Repeater {
      model: page.kcState === "unpaired" ? page.devices : []

      Row {
        required property var modelData
        spacing: Style.spacing.lg
        UiText {
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.name + (modelData.reachable ? "" : "  (offline)")
        }
        Button {
          visible: modelData.reachable
          bordered: true
          iconText: "\uf0c1"
          text: "Pair"
          onClicked: { pairProc.deviceId = modelData.id; pairProc.running = true }
        }
      }
    }

    // ---- paired: list devices
    Repeater {
      model: page.kcState === "paired" ? page.devices.filter(function(d) { return d.paired }) : []

      UiText {
        required property var modelData
        text: "\u2713 " + modelData.name + (modelData.reachable ? "  (connected)" : "  (offline)")
      }
    }

    UiText {
      visible: page.notice !== ""
      width: parent.width
      text: page.notice
      wrapMode: Text.WordWrap
      dim: true
      font.pixelSize: Style.font.bodySmall
    }

    Button {
      bordered: true
      iconText: "\uf021"
      text: "Re-check"
      onClicked: page.recheck()
    }
  }
}
