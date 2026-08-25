import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import vm from "node:vm"

const context = {}
vm.createContext(context)
vm.runInContext(readFileSync(new URL("../Model.js", import.meta.url), "utf8"), context)

const report = {
  running: true,
  due: 12,
  studiedToday: 34,
  timeTodaySec: 3900,
}

test("barLabel uses the configured daily metric", () => {
  assert.equal(context.barLabel(report, "Due cards"), "12")
  assert.equal(context.barLabel(report, "Cards studied"), "34")
  assert.equal(context.barLabel(report, "Study time"), "1h 5m")
})

test("barLabel omits text for icon-only and zero-due states", () => {
  assert.equal(context.barLabel(report, "Icon only"), "")
  assert.equal(context.barLabel({ running: true, due: 0 }, "Due cards"), "")
})

test("parseReport reads a report and tolerates surrounding noise", () => {
  const parsed = context.parseReport('warning: ignore me\n{"due": 7, "decks": []}\n')
  assert.equal(parsed.due, 7)
})

test("parseReport drops output too large to be a status report", () => {
  const bloat = '{"due": 1, "pad": "' + "x".repeat(600 * 1024) + '"}'
  assert.equal(context.parseReport(bloat), null)
})

test("parseReport caps the deck rows it hands the panel", () => {
  const decks = Array.from({ length: 500 }, (_, i) => ({ name: "d" + i, due: i }))
  const parsed = context.parseReport(JSON.stringify({ due: 1, decks }))
  assert.equal(parsed.decks.length, 200)
  assert.equal(parsed.decksTruncated, true)
})
