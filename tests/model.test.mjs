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
  assert.equal(context.barLabel(report, "Due cards"), "󰀭 12")
  assert.equal(context.barLabel(report, "Cards studied"), "󰀭 34")
  assert.equal(context.barLabel(report, "Study time"), "󰀭 1h 5m")
})

test("barLabel keeps the interactive icon reachable with no cards due", () => {
  assert.equal(context.barLabel(report, "Icon only"), "󰀭")
  assert.equal(context.barLabel({ running: true, due: 0 }, "Due cards"), "󰀭")
})
