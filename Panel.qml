import QtQuick
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

  property var report: null
  property string label: Model.barLabel(report)

  function refresh() {
    if (collectorProc.running) return
    collectorProc.command = [root.collector, "--forecast-days", String(root.forecastDays)]
    collectorProc.running = true
  }

  function syncNow() {
    if (syncProc.running) return
    syncProc.running = true
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

  visible: root.label !== ""
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    slotSize: Style.bar.iconSlot * 2
    tooltipText: root.report && !root.report.error
      ? "Anki — " + Model.intVal(root.report.due) + " due · " + root.report.studiedToday + " studied"
      : "Anki"
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
    contentWidth: panel.fittedContentWidth(Style.space(560))
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
        if (t === "r" || t === "R") root.refresh()
        else if (t === "s" || t === "S") root.syncNow()
        else if (t === "o" || t === "O") root.launchAnki()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: icon · title/status · action buttons ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroActions.implicitHeight)

          Text {
            id: heroIcon
            text: Model.icon(root.report)
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
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
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: Model.heroStatus(root.report).toUpperCase()
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
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
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              enabled: !syncProc.running
              onClicked: root.syncNow()
            }
            PanelActionButton {
              iconText: "󰑓"
              tooltipText: "Refresh"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.refresh()
            }
            PanelActionButton {
              iconText: "󰣆"
              tooltipText: "Open Anki"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              onClicked: root.launchAnki()
            }
          }
        }

        // ---------- Today's queues ----------
        PanelSeparator { foreground: root.bar.foreground }

        // Item wrapper so inner widths anchor against something that never
        // goes through a positioner — a Row child reporting implicitWidth
        // from content children can't feed those children's own widths.
        Item {
          width: parent.width
          implicitHeight: Math.max(queueLeft.implicitHeight, queueRight.implicitHeight)

          Column {
            id: queueLeft
            anchors.left: parent.left
            width: Math.round(parent.width * 0.4)
            spacing: Style.space(10)
            InfoPair { label: "New"; value: root.report ? String(Model.intVal(root.report.new)) : "—" }
            InfoPair { label: "Learning"; value: root.report ? String(Model.intVal(root.report.learn)) : "—" }
          }
          Column {
            id: queueRight
            anchors.left: queueLeft.right
            anchors.leftMargin: Style.space(24)
            anchors.right: parent.right
            spacing: Style.space(10)
            InfoPair { label: "Review"; value: root.report ? String(Model.intVal(root.report.review)) : "—" }
            InfoPair {
              label: "Studied today"
              value: root.report
                ? root.report.studiedToday + " cards · " + Model.formatMinutes(root.report.timeTodaySec)
                : "—"
            }
            InfoPair {
              label: "Mature retention (30d)"
              value: root.report && root.report.retention >= 0 ? Model.formatRetention(root.report.retention) : "—"
            }
          }
        }

        // ---------- Forecast ----------
        PanelSeparator {
          visible: forecastColumn.visible
          foreground: root.bar.foreground
        }

        Column {
          id: forecastColumn
          visible: root.report && root.report.forecast && root.report.forecast.length > 0
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "NEXT " + (root.report ? root.report.forecast.length - 1 : 0) + " DAYS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

                    Row {
            id: forecastRow
            width: parent.width
            height: Style.space(64)
            spacing: Style.space(6)

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

                // Bar centered in the cell, rising off the baseline above
                // the weekday letter; count label floats at the bar tip.
                Rectangle {
                  id: barRect
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: weekdayLetter.top
                  anchors.bottomMargin: Style.space(2)
                  width: Math.max(Style.space(8), Math.min(parent.width * 0.72, Style.space(28)))
                  height: Math.max(
                    Style.space(2),
                    (forecastDay.count / forecastDay.maxCount) * Style.space(34)
                  )
                  radius: Math.min(Style.space(3), width / 2)
                  color: forecastDay.index === 0 ? Color.accent : root.bar.foreground
                  opacity: forecastDay.index === 0 ? 1.0 : 0.45
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: barRect.top
                  anchors.bottomMargin: Style.space(2)
                  visible: forecastDay.count > 0
                  text: forecastDay.count
                  color: Qt.darker(root.bar.foreground, 1.3)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  id: weekdayLetter
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  text: Model.weekdayLetter(modelData.day)
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        // ---------- Decks ----------
        PanelSeparator {
          visible: deckList.model && deckList.model.length > 0
          foreground: root.bar.foreground
        }

        Column {
          visible: deckList.model && deckList.model.length > 0
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "DECKS"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          ListView {
            id: deckList
            width: parent.width
            height: Math.min(contentHeight, Style.space(160))
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            model: root.report ? root.report.decks : []
            spacing: Style.space(8)

            delegate: Row {
              required property var modelData
              width: ListView.view.width
              spacing: Style.space(10)

              Text {
                width: parent.width - parent.spacing - dueText.implicitWidth
                text: modelData.name
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                id: dueText
                text: modelData.new + " · " + modelData.learn + " · " + modelData.review
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        // ---------- Error / not-running notice ----------
        Text {
          visible: root.report && root.report.error
          width: parent.width
          text: root.report ? root.report.error : ""
          color: root.bar.urgent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  function launchAnki() {
    Quickshell.execDetached(["anki"])
  }

  // ---------- row helpers ----------
  // Label over value. Text widths anchor against pairColumn (anchors don't
  // feed implicit size back the way `width: parent.width` would — that
  // binding loops Item.width → implicitWidth → pairColumn.implicitWidth →
  // Text.implicitWidth → Text.width and the pair collapses to 0×0).
  component InfoPair: Item {
    property string label: ""
    property string value: ""
    implicitWidth: Math.max(labelText.implicitWidth, valueText.implicitWidth)
    implicitHeight: pairColumn.implicitHeight

    Column {
      id: pairColumn
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(1)

      Text {
        id: labelText
        anchors.left: parent.left
        anchors.right: parent.right
        text: label
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
      Text {
        id: valueText
        anchors.left: parent.left
        anchors.right: parent.right
        text: value
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
  }
}
