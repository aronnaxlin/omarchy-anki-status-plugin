import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Anki Status: bar pill with the due count, popup with today's queues, the
// week-ahead forecast, per-deck breakdown, and sync/review shortcuts.
// Data comes from bin/anki-status (read-only, immutable-mode SQLite) on a
// refresh timer and on every panel open.
Panel {
  id: root
  moduleName: "aronnax.anki-status"
  ipcTarget: "aronnax.anki-status"
  // This panel owns its target's IpcHandler itself (refresh shortcut below),
  // so the base must not register one.
  manageIpc: false

  readonly property string collector: Quickshell.env("HOME") + "/.config/omarchy/plugins/aronnax.anki-status/bin/anki-status"
  readonly property int refreshIntervalSec: setting("refreshIntervalSec", 300)
  readonly property int forecastDays: setting("forecastDays", 7)
  readonly property string barMetric: String(setting("barMetric", "Due cards"))

  // Theme-independent aliases so deep children don't repeat the `bar ?` dance.
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color dimmer: Qt.darker(foreground, 1.75)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property var report: null
  property string label: Model.barLabel(report, barMetric)
  // Stats scope: "" = whole profile; otherwise a top-level deck name from
  // report.decks. A stale name (deck renamed/deleted) falls back to
  // profile-wide stats in statsSource.
  property string scopeDeck: ""

  function deckNames() {
    if (!root.report || !root.report.decks) return []
    var names = []
    for (var i = 0; i < root.report.decks.length; i++)
      names.push(root.report.decks[i].name)
    return names
  }

  readonly property var scopeOptions: {
    var options = [{ value: "", label: "All decks" }]
    if (!root.report || !root.report.decks) return options
    for (var i = 0; i < root.report.decks.length; i++) {
      var name = root.report.decks[i].name
      options.push({ value: name, label: name })
    }
    return options
  }

  readonly property var barMetricOptions: [
    { value: "Due cards", label: "Due cards" },
    { value: "Cards studied", label: "Cards studied" },
    { value: "Study time", label: "Study time" },
    { value: "Icon only", label: "Icon only" }
  ]

  // The object the stats grid reads: the profile report, or the selected
  // deck row when its name still exists in the report.
  readonly property var statsSource: {
    if (!root.report || !root.report.decks) return root.report
    if (root.scopeDeck === "") return root.report
    for (var i = 0; i < root.report.decks.length; i++) {
      if (root.report.decks[i].name === root.scopeDeck)
        return root.report.decks[i]
    }
    return root.report
  }

  function cycleScope(direction) {
    var options = [""].concat(deckNames())
    var i = options.indexOf(root.scopeDeck)
    if (i < 0) i = 0
    i = (i + direction + options.length) % options.length
    root.scopeDeck = options[i]
  }

  // Persist interactive bar preferences through the shell's inline widget
  // settings. Applying locally keeps the label responsive before shell.json
  // notifies the bar back with the same value.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings)
      if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setBarMetric(value) {
    if (value !== root.barMetric) root.persistSettings({ barMetric: value })
  }

  onScopeDeckChanged: scopeSelector.value = root.scopeDeck
  onBarMetricChanged: barDisplaySelector.value = root.barMetric

  function refresh() {
    if (collectorProc.running) return
    collectorProc.command = [root.collector, "--forecast-days", String(root.forecastDays)]
    collectorProc.running = true
  }

  function syncNow() {
    if (syncProc.running) return
    syncProc.running = true
  }

  function launchAnki() {
    Quickshell.execDetached(["anki"])
  }

  Process {
    id: collectorProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseReport(text)
        if (parsed) root.report = parsed
      }
    }
  }

  Process {
    id: syncProc
    command: ["anki", "--sync"]
  }

  Timer {
    interval: Math.max(30, root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Refresh on open so the panel never shows stale numbers.
  onOpenedChanged: if (opened) root.refresh()

  IpcHandler {
    target: "aronnax.anki-status"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function refresh() { root.refresh() }
    function sync() { root.syncNow() }
  }

  // ------------------------------------------------------------ bar pill

  visible: root.report && !root.report.error
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: root.report && !root.report.error
    fixedWidth: button.vertical ? Style.bar.iconSlot : barContent.implicitWidth + Style.space(12)
    tooltipText: root.report && !root.report.error
      ? "Anki — " + Model.intVal(root.report.due) + " due · " + root.report.studiedToday + " studied"
      : "Anki"

    Row {
      id: barContent
      anchors.centerIn: parent
      spacing: Style.space(4)

      AnkiIcon {
        iconSize: Style.bar.iconCanvas
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        visible: root.label !== ""
        text: root.label
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.bar.iconFont
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    onPressed: function(b) {
      if (b === Qt.RightButton) root.syncNow()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  // ------------------------------------------------------------ popup

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // fittedContentWidth caps against the screen at any scale; 420px logical
    // is the design width, scaled by the theme's spacing scale.
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        // No cursor rows in this panel; arrows scroll the deck list.
        if (dy !== 0) deckList.flick(0, -dy * Style.space(600))
      }
      onActivateRequested: root.refresh()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (scopeSelector.popupOpen || barDisplaySelector.popupOpen) return
        if (t === "r" || t === "R") root.refresh()
        else if (t === "s" || t === "S") root.syncNow()
        else if (t === "o" || t === "O") root.launchAnki()
        else if (t === "d" || t === "D") root.cycleScope(1)
        else if (t === "a" || t === "A") root.scopeDeck = ""
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(16)

        // ---------- Hero: icon · title/status · action buttons ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroActions.implicitHeight)

          AnkiIcon {
            id: heroIcon
            iconSize: Style.font.display
            color: root.foreground
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.report && root.report.running ? 1.0 : 0.5
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroActions.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Anki"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: Model.heroStatus(root.report).toUpperCase()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Row {
            id: heroActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            PanelActionButton {
              iconText: "󰓦"
              tooltipText: "Sync now"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !syncProc.running
              onClicked: root.syncNow()
            }
            PanelActionButton {
              iconText: "󰑓"
              tooltipText: "Refresh"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.refresh()
            }
            PanelActionButton {
              iconText: "󰣆"
              tooltipText: "Open Anki"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.launchAnki()
            }
          }
        }

        // ---------- Today's queues ----------
        PanelSeparator { foreground: root.foreground }

        // Scope selector: the native dropdown keeps long deck names clipped
        // in the trigger while showing the complete name in its themed popup.
        // It is only shown when there is a real choice to make.
        Row {
          visible: root.report && root.report.decks && root.report.decks.length > 1
          width: parent.width
          height: visible ? Math.max(scopeTitle.implicitHeight, scopeSelector.implicitHeight) : 0
          spacing: Style.space(8)

          Text {
            id: scopeTitle
            text: "SCOPE"
            color: root.dimmer
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            anchors.verticalCenter: parent.verticalCenter
          }

          Dropdown {
            id: scopeSelector
            width: Math.max(0, parent.width - scopeTitle.implicitWidth - parent.spacing)
            anchors.verticalCenter: parent.verticalCenter
            showLabel: false
            value: root.scopeDeck
            options: root.scopeOptions
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(value) { root.scopeDeck = value }
          }
        }

        // GridLayout, not paired Columns: equal cells at any width, and the
        // StatCell values align on a shared baseline per row. Third row only
        // exists when there's retention data — GridLayout skips invisible
        // cells without leaving a hole.
        GridLayout {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(24)
          rowSpacing: Style.space(14)

          StatCell {
            Layout.fillWidth: true
            label: "New"
            value: root.statsSource ? String(Model.intVal(root.statsSource.new)) : "—"
          }
          StatCell {
            Layout.fillWidth: true
            label: "Review"
            value: root.statsSource ? String(Model.intVal(root.statsSource.review)) : "—"
          }
          StatCell {
            Layout.fillWidth: true
            label: "Learning"
            value: root.statsSource ? String(Model.intVal(root.statsSource.learn)) : "—"
          }
          StatCell {
            Layout.fillWidth: true
            label: "Studied today"
            value: root.statsSource
              ? Model.intVal(root.statsSource.studiedToday) + " cards · " + Model.formatMinutes(root.statsSource.timeTodaySec)
              : "—"
          }
          StatCell {
            Layout.fillWidth: true
            visible: root.statsSource && root.statsSource.retention >= 0
            label: "Retention 30d"
            value: root.statsSource && root.statsSource.retention >= 0 ? Model.formatRetention(root.statsSource.retention) : ""
          }
          StatCell {
            Layout.fillWidth: true
            visible: root.scopeDeck === "" && root.report && root.report.todayLimit > 0
            label: "New card cap"
            value: root.report && root.report.todayLimit > 0
              ? Model.intVal(root.report.newRemaining) + " / " + root.report.todayLimit
              : ""
          }
        }

        // ---------- Bar display ----------
        PanelSeparator { foreground: root.foreground }

        Dropdown {
          id: barDisplaySelector
          width: parent.width
          label: "BAR DISPLAY"
          value: root.barMetric
          options: root.barMetricOptions
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(value) { root.setBarMetric(value) }
        }

        // ---------- Forecast ----------
        PanelSeparator {
          visible: forecastColumn.visible
          foreground: root.foreground
        }

        Column {
          id: forecastColumn
          visible: root.report && root.report.forecast && root.report.forecast.length > 0
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "NEXT " + (root.report ? root.report.forecast.length - 1 : 0) + " DAYS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: forecastRow
            width: parent.width
            // Track height covers the tallest bar + count + weekday letter.
            height: Style.space(72)
            spacing: Style.space(8)

            Repeater {
              model: root.report ? root.report.forecast : []
              delegate: Item {
                id: forecastDay
                required property var modelData
                required property int index
                width: (forecastRow.width - forecastRow.spacing * (forecastRow.children.length - 1)) / forecastRow.children.length
                height: forecastRow.height

                readonly property int count: Model.intVal(modelData.count)
                readonly property int maxCount: Model.forecastMax(root.report ? root.report.forecast : [])

                // Count label sits at the bar tip; bar rises off the
                // baseline above the weekday letter. Column-of-three keeps
                // the geometry in one place, and the count label's slot is
                // reserved even when the count is zero so bars stay aligned.
                Column {
                  anchors.bottom: parent.bottom
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(2)

                  Item {
                    width: Math.max(countText.implicitWidth, barRect.width)
                    height: countText.implicitHeight
                    anchors.horizontalCenter: parent.horizontalCenter
                    Text {
                      id: countText
                      anchors.centerIn: parent
                      visible: forecastDay.count > 0
                      text: forecastDay.count
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Rectangle {
                    id: barRect
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.max(Style.space(10), Math.min(forecastDay.width * 0.7, Style.space(24)))
                    height: Math.max(
                      Style.space(3),
                      (forecastDay.count / forecastDay.maxCount) * Style.space(36)
                    )
                    radius: Math.min(Style.space(3), width / 2)
                    color: forecastDay.index === 0 ? Color.accent : root.foreground
                    opacity: forecastDay.index === 0 ? 1.0 : 0.45
                  }

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Model.weekdayLetter(modelData.day)
                    color: root.dimmer
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }

        // ---------- Decks ----------
        PanelSeparator {
          visible: deckList.count > 0
          foreground: root.foreground
        }

        Column {
          visible: deckList.count > 0
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "DECKS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ListView {
            id: deckList
            width: parent.width
            height: Math.min(contentHeight, Style.space(170))
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            model: root.report ? root.report.decks : []
            spacing: Style.space(8)

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            // Deck name left, counts right-aligned in fixed-width slots so
            // the · separators stack vertically down the list.
            delegate: Item {
              required property var modelData
              width: ListView.view.width
              implicitHeight: deckRow.implicitHeight

              Row {
                id: deckRow
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Style.space(10)

                Text {
                  width: Math.max(0, parent.width - countsRow.implicitWidth - parent.spacing)
                  text: modelData.name
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                Row {
                  id: countsRow
                  spacing: 0

                  CountSlot { value: modelData.new; strong: modelData.new > 0 }
                  Text {
                    text: " · "
                    color: root.dimmer
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  CountSlot { value: modelData.learn; strong: modelData.learn > 0 }
                  Text {
                    text: " · "
                    color: root.dimmer
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  CountSlot { value: modelData.review; strong: modelData.review > 0 }
                }
              }
            }
          }
        }

        // ---------- Error / not-running notice ----------
        Text {
          visible: root.report && root.report.error
          width: parent.width
          text: root.report ? root.report.error : ""
          color: root.bar ? root.bar.urgent : Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  // ---------- components ----------

  // Stat grid cell: small-caps label over a bold value. Text widths anchor
  // against the inner column (a `width: parent.width` binding would loop
  // Item.width → implicitWidth → column.implicitWidth → Text.implicitWidth
  // → Text.width and collapse the cell to 0×0 inside the Layout).
  component StatCell: Item {
    property string label: ""
    property string value: ""
    implicitHeight: statColumn.implicitHeight

    Column {
      id: statColumn
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(3)

      Text {
        anchors.left: parent.left
        anchors.right: parent.right
        text: label.toUpperCase()
        color: root.dimmer
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
        elide: Text.ElideRight
      }
      Text {
        anchors.left: parent.left
        anchors.right: parent.right
        text: value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }
    }
  }

  // Right-aligned number in a 4-digit slot: digits line up down the deck
  // list regardless of count width.
  component CountSlot: Text {
    property int value: 0
    property bool strong: false
    width: Math.max(implicitWidth, Style.space(34))
    horizontalAlignment: Text.AlignRight
    text: value
    color: strong ? root.foreground : root.dimmer
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: strong
  }
}
