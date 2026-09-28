import assert from "node:assert/strict"
import { validateLinkGroups } from "./link-groups.ts"

const speech = "В пятницу вебинар, отправить заявку, чтобы попасть на этот вебинар"
const group = { members: [0, 1], confidence: "high", evidence: "отправить заявку, чтобы попасть на этот вебинар" }
assert.equal(validateLinkGroups([group], 2, speech).length, 1)
for (const value of [null, {}, [7], [], [{ ...group, confidence: "medium" }],
  [{ ...group, members: [0, 2] }], [{ ...group, members: [0, 0] }],
  [{ ...group, evidence: "придуманная цитата" }], [group, group]]) {
  assert.deepEqual(validateLinkGroups(value, 2, speech), [])
}
assert.equal(validateLinkGroups([group, { ...group, members: [2, 3] }], 4, speech).length, 2)
assert.deepEqual(validateLinkGroups([group], 1, speech), [])
console.log("PASS: voice link metadata validation (12 cases)")
