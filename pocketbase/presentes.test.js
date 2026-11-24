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

test("kit: o admin só salva ids que estão no catálogo", () => {
  const shop = ["frame_pioneer", "title_pioneer"]
  assert.strictEqual(presentes.kitProblem(null, shop), "")
  assert.strictEqual(presentes.kitProblem(["frame_pioneer", "title_pioneer"], shop), "")
  assert.strictEqual(presentes.kitProblem([], shop), "")
  assert.match(presentes.kitProblem(["frame_pioneerr"], shop), /frame_pioneerr/)
  assert.match(presentes.kitProblem("frame_pioneer", shop), /lista/)
  assert.match(presentes.kitProblem([7], shop), /fora/)
  assert.match(presentes.kitProblem(Array(presentes.MAX_KIT + 1).fill("frame_pioneer"), shop), /máximo/)
})

test("kit: o campo cru vira lista, e o inválido não passa como vazio", () => {
  assert.strictEqual(presentes.parseItems(""), null)
  assert.strictEqual(presentes.parseItems("null"), null)
  assert.deepStrictEqual(presentes.parseItems('["a","b"]'), ["a", "b"])
  assert.strictEqual(presentes.parseItems("[a"), undefined)
  assert.notStrictEqual(presentes.kitProblem(presentes.parseItems("[a"), []), "")
})

test("kit: abrir soma ao owned sem repetir", () => {
  assert.deepStrictEqual(presentes.kitItems(["a", "b", "a", 3, "", null]), ["a", "b"])
  assert.deepStrictEqual(presentes.kitItems(null), [])
  assert.deepStrictEqual(presentes.withItems(["x", "a"], ["a", "b"]), ["x", "a", "b"])
  assert.deepStrictEqual(presentes.withItems([], []), [])
})

test("testador: o kit sai uma vez, só para quem é testador", () => {
  assert.strictEqual(presentes.owesTesterKit(true, false), true)
  assert.strictEqual(presentes.owesTesterKit(true, true), false)
  assert.strictEqual(presentes.owesTesterKit(false, false), false)
  assert.ok(presentes.TESTER_KIT.length > 1 && presentes.TESTER_KIT.length <= presentes.MAX_KIT)
  assert.ok(presentes.TESTER_MESSAGE.length <= 200)
})

test("kit: a notificação fala por quem mandou, ou pelo app", () => {
  assert.strictEqual(presentes.kitPushText(""), "Você ganhou um presente 🎁")
  assert.strictEqual(presentes.kitPushText("abc"), "Te mandou um presente 🎁")
})
