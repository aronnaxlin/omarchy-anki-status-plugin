// Pure helpers for the Anki Status panel. Kept side-effect free so the QML
// stays declarative and every transform here is unit-testable in isolation.

// Text placed beside the separately rendered Anki SVG in the bar. Empty is
// intentional for icon-only and zero-due states; Panel.qml keeps the icon
// visible whenever a valid report is available.
function barLabel(report, metric) {
  if (!report || report.error || metric === "Icon only") return ""
  if (metric === "Cards studied") return String(intVal(report.studiedToday))
  if (metric === "Study time") return formatMinutes(report.timeTodaySec)
  var due = intVal(report.due)
  return due > 0 ? String(due) : ""
}

function intVal(v) {
  var n = parseInt(v)
  return isFinite(n) ? n : 0
}

// Hero status line, uppercased by the view.
function heroStatus(report) {
  if (!report) return "Loading"
  if (report.error) return "Collection unreadable"
  if (!report.running) return "Anki not running"
  var due = intVal(report.due)
  if (due === 0) return "All caught up"
  return due + " card" + (due === 1 ? "" : "s") + " due today"
}

function formatMinutes(totalSec) {
  var m = Math.round(intVal(totalSec) / 60)
  if (m < 60) return m + "m"
  var h = Math.floor(m / 60)
  return h + "h " + (m % 60) + "m"
}

function formatRetention(retention) {
  var r = Number(retention)
  if (!isFinite(r) || r < 0) return "—"
  return Math.round(r * 100) + "%"
}

// Weekday letters for the forecast chart, e.g. ["M","T",...]. Day strings
// arrive as YYYY-MM-DD in local time.
function weekdayLetter(dayString) {
  var parts = String(dayString || "").split("-")
  if (parts.length !== 3) return ""
  var d = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]))
  var names = ["S", "M", "T", "W", "T", "F", "S"]
  return names[d.getDay()]
}

// Max of the forecast counts, for bar scaling. At least 1 to keep bars sane.
function forecastMax(forecast) {
  var max = 1
  if (!forecast) return max
  for (var i = 0; i < forecast.length; i++) {
    var c = intVal(forecast[i].count)
    if (c > max) max = c
  }
  return max
}

// Ceilings on what we will accept from the collector. bin/anki-status holds
// its own output to 64 KB; this is deliberate slack over that — 8× — so an
// older or hand-rolled collector still works, while output that could only
// come from something malfunctioning is refused.
//
// Note what this does and does not buy: StdioCollector has already read the
// whole stream into a string before we are called, so the real bound on what
// the panel buffers is the collector's budget and Panel.qml's watchdog. What
// the check here avoids is parsing and retaining a runaway document, and the
// deck cap avoids handing the ListView a model no one can scroll.
var MAX_REPORT_CHARS = 512 * 1024
var MAX_DECK_ROWS = 200

// Parse the collector's JSON, tolerating trailing noise from stdout.
// Oversized output is dropped rather than parsed: the panel keeps the last
// good report, which beats spending the UI thread on a document no one
// asked for.
function parseReport(raw) {
  if (!raw) return null
  var text = String(raw)
  if (text.length > MAX_REPORT_CHARS) return null
  text = text.trim()
  var start = text.indexOf("{")
  var end = text.lastIndexOf("}")
  if (start < 0 || end <= start) return null
  var report
  try {
    report = JSON.parse(text.slice(start, end + 1))
  } catch (e) {
    return null
  }
  if (report && report.decks && report.decks.length > MAX_DECK_ROWS) {
    report.decks = report.decks.slice(0, MAX_DECK_ROWS)
    report.decksTruncated = true
  }
  return report
}
