// As regras puras dos presentes (`pb_hooks/presentes.js`), sem PocketBase:
//
//   node --test pocketbase/presentes.test.js
//
// Rotas, amizade e transação ficam no `tests/gifts_probe.gd`.
const test = require("node:test")
const assert = require("node:assert")
const presentes = require("./pb_hooks/presentes.js")

test("presente de item: à venda, amigo sem o item e saldo que cobre", () => {
  assert.strictEqual(presentes.itemProblem(150, false, 150), null)
  assert.strictEqual(presentes.itemProblem(undefined, false, 999).status, 404)
  assert.strictEqual(presentes.itemProblem(150, true, 999).status, 409)
  assert.strictEqual(presentes.itemProblem(150, false, 149).status, 402)
})

test("presentinho: um por amigo por dia, teto de recebidos", () => {
  assert.strictEqual(presentes.dailyProblem(false, 0), null)
  assert.strictEqual(presentes.dailyProblem(false, presentes.MAX_RECEIVED - 1), null)
  assert.strictEqual(presentes.dailyProblem(true, 0).status, 409)
  assert.strictEqual(presentes.dailyProblem(false, presentes.MAX_RECEIVED).status, 429)
})
