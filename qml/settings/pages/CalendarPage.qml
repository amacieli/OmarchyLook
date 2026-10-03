import QtQuick
import qs.Commons
import qs.Ui
import "../../common"
import ".."

// Placeholder: none of these values are persisted yet.
SettingsPage {
  id: page

  property string weekStart: "mon"
  property bool weekNumbers: false
  property int dayStartHour: 8
  property string reminder: "15"

  editing: reminderDropdown.popupOpen

  title: "Calendar"
  description: "Week layout and default reminders."
  placeholder: true

  Column {
    width: parent.width
    spacing: Style.space(6)

    PanelSectionHeader { text: "WEEK STARTS ON" }
    ButtonGroup {
      options: [{ value: "sun", label: "Sun" }, { value: "mon", label: "Mon" }, { value: "sat", label: "Sat" }]
      value: page.weekStart
      onChanged: function(v) { page.weekStart = v }
    }
  }

  Toggle {
    width: parent.width
    label: "Show week numbers"
    description: page.weekNumbers ? "ISO week numbers visible" : "Week numbers hidden"
    checked: page.weekNumbers
    onClicked: page.weekNumbers = !page.weekNumbers
  }

  Column {
    width: parent.width
    spacing: Style.space(6)

    Row {
      width: parent.width
      PanelSectionHeader { text: "DAY STARTS AT"; width: parent.width - hourReadout.implicitWidth }
      UiText {
        id: hourReadout
        text: (slider.dragging ? Math.round(slider.liveValue) : page.dayStartHour) + ":00"
        dim: true
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    PanelSlider {
      id: slider
      bar: page.sliderBar
      width: parent.width
      minimum: 0
      maximum: 12
      step: 1
      integer: true
      value: page.dayStartHour
      onReleased: function(v) { page.dayStartHour = Math.round(v) }
    }
  }

  Dropdown {
    id: reminderDropdown
    width: parent.width
    label: "Default reminder"
    value: page.reminder
    options: [
      { value: "0",  label: "At time of event" },
      { value: "15", label: "15 minutes before" },
      { value: "60", label: "1 hour before" }
    ]
    onChanged: function(v) { page.reminder = v }
  }
}
