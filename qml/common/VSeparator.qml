import QtQuick
import qs.Commons

// Vertical twin of qs.Ui.PanelSeparator (1px rule, same tint). The kit only
// ships the horizontal one.
Rectangle {
  property color foreground: Color.foreground
  property real strength: 0.12

  implicitWidth: 1
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, strength)
}
