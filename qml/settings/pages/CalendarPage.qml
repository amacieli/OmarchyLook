import QtQuick
import qs.Commons
import qs.Ui
import "../../common"
import ".."

// Only "Recurring meeting windows" is wired to the backend; the other values are still
// placeholders and are not persisted.
SettingsPage {
  id: page

  property var app: null

  property string weekStart: "mon"
  property bool weekNumbers: false
  property int dayStartHour: 8
  property string reminder: "15"

  editing: reminderDropdown.popupOpen || backYears.field.activeFocus || aheadYears.field.activeFocus

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

  PanelSeparator { width: parent.width }

  // ── wired to the daemon ──────────────────────────────────────
  Column {
    width: parent.width
    spacing: Style.space(6)

    PanelSectionHeader { text: "RECURRING MEETING WINDOWS" }

    UiText {
      width: parent.width
      text: "How far recurring meetings are expanded into individual occurrences, either side of today. "
          + "Applied on the next sync cycle (within a couple of minutes); narrowing the window removes "
          + "the occurrences outside it."
      dim: true
      wrapMode: Text.WordWrap
      font.pixelSize: Style.font.caption
    }

    Row {
      spacing: Style.space(16)

      NumberField {
        id: backYears
        label: "Years back"
        value: page.app ? page.app.recurrenceYearsBack : 5
        from: 0
        to: page.app ? page.app.maxYearsBack : 20
        stepSize: 1
        onModified: function(v) { if (page.app) page.app.setRecurrenceWindow(v, page.app.recurrenceYearsAhead) }
      }

      NumberField {
        id: aheadYears
        label: "Years forward"
        value: page.app ? page.app.recurrenceYearsAhead : 10
        from: 1
        to: page.app ? page.app.maxYearsAhead : 30
        stepSize: 1
        onModified: function(v) { if (page.app) page.app.setRecurrenceWindow(page.app.recurrenceYearsBack, v) }
      }
    }
  }
}
