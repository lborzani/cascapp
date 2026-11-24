// As regras puras da loja (`pb_hooks/loja.js`), sem PocketBase:
//
//   node --test pocketbase/loja.test.js
//
// O resto (rotas, regra de atualização, transação) é coberto pelo
// `tests/shop_probe.gd` contra um PocketBase de verdade.
const test = require("node:test")
const assert = require("node:assert")
const loja = require("./pb_hooks/loja.js")

test("o dia vira à meia-noite de Brasília", () => {
  assert.strictEqual(loja.brDay(Date.parse("2026-11-16T02:59:59Z")), "2026-11-15")
  assert.strictEqual(loja.brDay(Date.parse("2026-11-16T03:00:00Z")), "2026-11-16")
})

test("prêmio por desfecho, dentro do teto do dia", () => {
  assert.strictEqual(loja.rewardFor("bowling", "win", 0), 25)
  assert.strictEqual(loja.rewardFor("chess", "draw", 0), 15)
  assert.strictEqual(loja.rewardFor("uno", "loss", 0), 10)
  assert.strictEqual(loja.rewardFor("uno", "win", loja.REWARD_CAP - 7), 7)
  assert.strictEqual(loja.rewardFor("uno", "win", loja.REWARD_CAP), 0)
  assert.strictEqual(loja.rewardFor("xadrez", "win", 0), null)
  assert.strictEqual(loja.rewardFor("uno", "victory", 0), null)
})

test("catálogo: à venda só o ativo e não exclusivo; pago é todo registro", () => {
  const catalog = loja.catalogOf([
    { item: "ball_wood", price: 150, exclusive: false, active: true },
    { item: "ball_old", price: 90, exclusive: false, active: false },
    { item: "title_mission", price: 0, exclusive: true, active: true },
  ])
  assert.deepStrictEqual(catalog.prices, { ball_wood: 150 })
  assert.deepStrictEqual(catalog.paid, ["ball_wood", "ball_old", "title_mission"])
  assert.deepStrictEqual(catalog.exclusive, ["title_mission"])
})

test("visual: item pago só equipado se comprado", () => {
  const paid = ["ball_galaxy", "title_mission"]
  assert.strictEqual(loja.lookProblem({ ball: "ball_galaxy" }, [], paid), "ball_galaxy")
  assert.strictEqual(loja.lookProblem({ ball: "ball_galaxy" }, ["ball_galaxy"], paid), "")
  assert.strictEqual(loja.lookProblem({ title: "title_mission" }, [], paid), "title_mission")
  assert.strictEqual(loja.lookProblem({ skin: "skin_3", hair_color: "hc_red" }, [], paid), "")
  assert.strictEqual(loja.lookProblem({}, [], paid), "")
  assert.strictEqual(loja.lookProblem([], [], paid), null)
  assert.strictEqual(loja.lookProblem("ball_galaxy", [], paid), null)
  assert.strictEqual(loja.lookProblem({ ball: 3 }, [], paid), null)
  const many = {}
  for (let i = 0; i < 13; i++) many["s" + i] = "x"
  assert.strictEqual(loja.lookProblem(many, [], paid), null)
})
