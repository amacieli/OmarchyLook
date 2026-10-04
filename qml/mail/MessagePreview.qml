import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../common"
import "format.js" as Fmt

// Reading pane. `message` is the model row (or null for the empty state).
Item {
  id: root

  property var message: null

  signal replyRequested()
  signal forwardRequested()
  signal toggleReadRequested()
  signal toggleHtmlRequested()
  signal viewAsHtmlRequested(string scope)   // "message" | "sender"
  signal unblockRequested(string scope)   // "message" | "sender"
  signal focusRequested()                 // give the keyboard back to the shell

  // Body of `message`: { state: idle|loading|ready|error, type: html|text, content }.
  property var body: ({ state: "idle", type: "", content: "" })
  property bool htmlMode: false
  // True when this message (or its sender) may load remote images.
  property bool imagesAllowed: false
  // Offer "view as HTML" above the system-font body.
  property bool htmlOffer: false
  // The image dropdown owns the keyboard while its popup is open.
  readonly property bool editing: imageChoice.popupOpen || htmlChoice.popupOpen

  // A different message starts at the top of both views.
  readonly property string bodyId: root.body ? String(root.body.id || "") : ""
  onBodyIdChanged: {
    imageChoice.value = "message"
    htmlChoice.value = "message"
    scroll.ScrollBar.vertical.position = 0
    htmlScroll.ScrollBar.vertical.position = 0
  }

  readonly property bool bodyReady: !!root.body && root.body.state === "ready"
  // System view: always plain text, in the system font.
  readonly property string plainText: !bodyReady ? ""
    : (root.body.type === "html" ? Fmt.htmlToText(root.body.content) : root.body.content)
  readonly property string statusText: !root.body ? ""
    : (root.body.state === "loading" ? "loading message…"
      : (root.body.state === "error" ? String(root.body.reason || "could not load the message body") : ""))
  // What is shown under a load error: the cached preview, if there is one.
  readonly property string fallbackText: !!root.body && root.body.state === "error" ? String(root.body.preview || "") : ""
  // HTML view: only built while it is the one showing.
  readonly property var rendered: {
    if (!root.htmlMode || !root.bodyReady) return { html: "", blocked: 0 }
    if (root.body.type !== "html") return { html: Fmt.textToHtml(root.body.content), blocked: 0 }
    return Fmt.sanitizeHtml(root.body.content, Math.max(0, htmlScroll.width - Style.spacing.huge * 2), root.imagesAllowed)
  }

  // ---- empty state
  ColumnLayout {
    anchors.centerIn: parent
    visible: !root.message
    spacing: Style.spacing.md

    UiText {
      Layout.alignment: Qt.AlignHCenter
      text: "\uf0e0"
      dim: true
      opacity: 0.5
      font.pixelSize: Style.font.displayLarge
    }
    UiText {
      Layout.alignment: Qt.AlignHCenter
      text: "select a message"
      dim: true
      opacity: 0.5
      font.pixelSize: Style.font.bodySmall
    }
  }

  // ---- message
  ColumnLayout {
    anchors.fill: parent
    visible: !!root.message
    spacing: 0

    // header
    ColumnLayout {
      Layout.fillWidth: true
      Layout.margins: Style.spacing.huge
      spacing: Style.spacing.md

      UiText {
        text: (root.message && root.message.subject) || "(no subject)"
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.md

        BorderSurface {
          implicitWidth: chip.implicitWidth + Style.spacing.lg * 2
          implicitHeight: chip.implicitHeight + Style.spacing.sm * 2
          radius: Style.cornerRadius
          color: Style.selectedFillFor(Color.accent, Color.accent)
          borderSpec: Border.flat(Color.accent, Style.normalBorderWidth)

          UiText {
            id: chip
            anchors.centerIn: parent
            text: Fmt.senderName(root.message)
            foreground: Color.accent
            font.pixelSize: Style.font.caption
          }
        }

        UiText {
          text: root.message && root.message.from_email ? "<" + root.message.from_email + ">" : ""
          Layout.fillWidth: true
          elide: Text.ElideRight
          dim: true
          font.pixelSize: Style.font.caption
        }

        UiText {
          text: Fmt.fullDate(root.message ? root.message.received_at : "")
          dim: true
          font.pixelSize: Style.font.caption
        }
      }

      UiText {
        visible: text.length > 0
        text: Fmt.recipients(root.message)
        Layout.fillWidth: true
        elide: Text.ElideRight
        dim: true
        font.pixelSize: Style.font.caption
      }
    }

    PanelSeparator { Layout.fillWidth: true }

    // actions
    RowLayout {
      Layout.fillWidth: true
      Layout.margins: Style.spacing.lg
      spacing: Style.spacing.md

      Button {
        text: "reply"
        iconText: "\uf112"
        bordered: true
        onClicked: root.replyRequested()
      }
      Button {
        text: "forward"
        iconText: "\uf064"
        bordered: true
        onClicked: root.forwardRequested()
      }

      Item { Layout.fillWidth: true }

      Button {
        bordered: true
        text: root.htmlMode ? "System" : "HTML"
        iconText: root.htmlMode ? "\uf031" : "\uf121"
        onClicked: root.toggleHtmlRequested()
      }
      Button {
        bordered: true
        text: root.message && root.message.is_read ? "mark unread" : "mark read"
        iconText: root.message && root.message.is_read ? "\uf2b6" : "\uf2b7"
        onClicked: root.toggleReadRequested()
      }
    }

    PanelSeparator { Layout.fillWidth: true }

    // body: two sub-views, one shown at a time.
    StackLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      currentIndex: root.htmlMode ? 1 : 0

      // System view — an offer to view the message as HTML, then plain text in the
      // shell font.
      ColumnLayout {
        spacing: 0

        RowLayout {
          visible: root.htmlOffer
          Layout.fillWidth: true
          Layout.margins: Style.spacing.lg
          spacing: Style.spacing.md

          UiText {
            Layout.fillWidth: true
            text: "This message has HTML formatting"
            dim: true
            elide: Text.ElideRight
          }

          Dropdown {
            id: htmlChoice
            Layout.preferredWidth: Style.space(260)
            Layout.alignment: Qt.AlignVCenter
            showLabel: false
            value: "message"
            options: [
              { value: "message", label: "View as HTML for this message" },
              { value: "sender",  label: "Always view this sender as HTML" }
            ]
            onPopupOpenChanged: if (!popupOpen) root.focusRequested()
          }

          Button {
            Layout.alignment: Qt.AlignVCenter
            bordered: true
            iconText: "\uf121"
            text: "View"
            onClicked: root.viewAsHtmlRequested(htmlChoice.value)
          }
        }

        ScrollView {
          id: scroll
          clip: true
          Layout.fillWidth: true
          Layout.fillHeight: true
          // Sized by the StackLayout, never by its content (that made a binding loop).
          implicitWidth: 0
          implicitHeight: 0
          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
          // A ScrollView does not place a bar it is handed, so pin it to the right edge.
          ScrollBar.vertical: ThemedScrollBar {
            parent: scroll
            x: scroll.width - width
            y: 0
            height: scroll.height
          }

          UiText {
            width: scroll.availableWidth
            leftPadding: Style.spacing.huge
            rightPadding: Style.spacing.huge
            topPadding: Style.spacing.xxxl
            bottomPadding: Style.spacing.huge * 1.3
            text: root.statusText !== ""
              ? root.statusText + (root.fallbackText !== "" ? "\n\n" + root.fallbackText : "")
              : root.plainText
            dim: root.statusText !== ""
            wrapMode: Text.WordWrap
            lineHeight: 1.4
          }
        }
      }

      // HTML view — a bar for blocked images, then the message on a white page, as
      // Outlook's reading pane shows it.
      ColumnLayout {
        spacing: 0

        RowLayout {
          visible: root.bodyReady && !root.imagesAllowed && root.rendered.blocked > 0
          Layout.fillWidth: true
          Layout.margins: Style.spacing.lg
          spacing: Style.spacing.md

          UiText {
            Layout.fillWidth: true
            text: "Remote images were blocked (" + root.rendered.blocked + ")"
            dim: true
            elide: Text.ElideRight
          }

          Dropdown {
            id: imageChoice
            Layout.preferredWidth: Style.space(230)
            Layout.alignment: Qt.AlignVCenter
            showLabel: false
            value: "message"
            options: [
              { value: "message", label: "Unblock for this message" },
              { value: "sender",  label: "Unblock for this sender" }
            ]
            // The popup takes keyboard focus; hand it back when it closes.
            onPopupOpenChanged: if (!popupOpen) root.focusRequested()
          }

          Button {
            Layout.alignment: Qt.AlignVCenter
            bordered: true
            iconText: "\uf03e"
            text: "Unblock"
            onClicked: root.unblockRequested(imageChoice.value)
          }
        }

        ScrollView {
          id: htmlScroll
          clip: true
          Layout.fillWidth: true
          Layout.fillHeight: true
          // Sized by the StackLayout, never by its content (that made a binding loop).
          implicitWidth: 0
          implicitHeight: 0
          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
          // A ScrollView does not place a bar it is handed, so pin it to the right edge.
          ScrollBar.vertical: ThemedScrollBar {
            parent: htmlScroll
            tint: "#000000"
            x: htmlScroll.width - width
            y: 0
            height: htmlScroll.height
          }

          contentWidth: availableWidth
          contentHeight: page.height

          Rectangle {
            id: page
            width: htmlScroll.availableWidth
            height: Math.max(htmlScroll.height, pageColumn.implicitHeight + Style.spacing.huge * 2)
            color: "#ffffff"

            ColumnLayout {
              id: pageColumn
              x: Style.spacing.huge
              y: Style.spacing.huge
              width: parent.width - Style.spacing.huge * 2
              spacing: Style.spacing.lg

              Text {
                id: htmlText
                Layout.fillWidth: true
                visible: root.statusText === ""
                textFormat: Text.RichText
                wrapMode: Text.Wrap
                color: "#000000"
                linkColor: "#0563c1"
                font.family: "Calibri"   // fontconfig maps it to Carlito if installed, else a sans
                font.pixelSize: 15
                text: root.rendered.html
                onLinkActivated: function(link) { Qt.openUrlExternally(link) }
              }

              Text {
                visible: root.statusText !== ""
                Layout.fillWidth: true
                text: root.statusText + (root.fallbackText !== "" ? "\n\n" + root.fallbackText : "")
                color: "#777777"
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }
          }
        }
      }
    }
  }
}
