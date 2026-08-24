// Pure helpers for the Anki Status panel. Kept side-effect free so the QML
// stays declarative and every transform here is unit-testable in isolation.

// Bar pill text: " 18872" — icon + total due. Empty hides the widget.
function barLabel(report) {
  if (!report || report.error) return ""
  var due = intVal(report.due)
  if (due <= 0) return ""
  return "󰀭 " + due
}

function icon(report) {
  if (!report) return "󰀭"
  return report.running ? "󰀭" : "󰀬"
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

// Parse the collector's JSON, tolerating trailing noise from stdout.
function parseReport(raw) {
  if (!raw) return null
  var text = String(raw).trim()
  var start = text.indexOf("{")
  var end = text.lastIndexOf("}")
  if (start < 0 || end <= start) return null
  try {
    return JSON.parse(text.slice(start, end + 1))
  } catch (e) {
    return null
  }
}
