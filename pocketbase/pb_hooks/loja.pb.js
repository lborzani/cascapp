/// <reference path="../pb_data/types.d.ts" />

// A loja e as moedas (ver `pb_migrations/1763300000_loja.js`). Cada handler
// roda num contexto isolado: o que é comum mora em `loja.js` e entra por
// `require` dentro do handler, não no topo deste arquivo.
//
// As rotas que mexem no saldo devolvem a carteira inteira, `{coins, owned,
// look}`, mais `granted` (moedas ganhas no pedido) quando é o caso. Leitura e
// escrita do saldo andam numa transação só, para dois pedidos ao mesmo tempo
// não pagarem nem gastarem duas vezes.

// Conta nova nasce sem moedas e sem itens, por cima do que vier no corpo: a
// criação é aberta, e sem isto uma conta nasceria rica.
onRecordCreate((e) => {
  e.record.set("coins", 0)
  e.record.set("owned", [])
  e.record.set("look", {})
  e.record.set("daily_day", "")
  e.record.set("earned_day", "")
  e.record.set("earned_today", 0)
  e.next()
}, "users")

// O app equipa pelo update normal da conta; aqui só se confere que todo item
// pago do visual foi comprado.
onRecordUpdateRequest((e) => {
  const loja = require(`${__hooks}/loja.js`)
  if (e.requestInfo().body.look !== undefined) {
    // O corpo traz o campo JSON em bytes crus; o registro já tem ele carregado.
    const look = loja.jsonOf(e.record, "look", null)
    const stored = e.app.findRecordById("users", e.record.id)
    const problem = loja.lookProblem(look, loja.jsonOf(stored, "owned", []))
    if (problem === null) {
      throw new BadRequestError("Visual inválido.")
    }
    if (problem !== "") {
      throw new ForbiddenError("Item não comprado: " + problem)
    }
  }
  e.next()
}, "users")

// Os preços, o bônus diário e o prêmio por partida. Aberta: não diz nada de
// ninguém.
routerAdd("GET", "/api/cascapp/shop", (e) => {
  const loja = require(`${__hooks}/loja.js`)
  return e.json(200, {
    items: loja.PRICES,
    daily: loja.DAILY,
    rewards: loja.REWARDS,
    reward_cap: loja.REWARD_CAP,
  })
})

// O bônus do dia, uma vez por dia de Brasília. Pedir de novo no mesmo dia
// devolve a carteira com `granted` 0.
routerAdd("POST", "/api/cascapp/daily", (e) => {
  const loja = require(`${__hooks}/loja.js`)
  const today = loja.brDay(Date.now())
  let reply = null
  e.app.runInTransaction((tx) => {
    const user = tx.findRecordById("users", e.auth.id)
    let granted = 0
    if (user.getString("daily_day") !== today) {
      granted = loja.DAILY
      user.set("coins", user.getInt("coins") + granted)
      user.set("daily_day", today)
      tx.saveNoValidate(user)
    }
    reply = Object.assign(loja.wallet(user), { granted: granted })
  })
  return e.json(200, reply)
}, $apis.requireAuth("users"))

// Uma partida terminada: `{game, result: "win"|"draw"|"loss"}`. Paga dentro do
// teto do dia; acima dele, `granted` 0.
routerAdd("POST", "/api/cascapp/reward", (e) => {
  const loja = require(`${__hooks}/loja.js`)
  const body = e.requestInfo().body
  const today = loja.brDay(Date.now())
  let reply = null
  e.app.runInTransaction((tx) => {
    const user = tx.findRecordById("users", e.auth.id)
    const earned = user.getString("earned_day") === today ? user.getInt("earned_today") : 0
    const granted = loja.rewardFor(String(body.game || ""), String(body.result || ""), earned)
    if (granted === null) {
      return
    }
    user.set("coins", user.getInt("coins") + granted)
    user.set("earned_day", today)
    user.set("earned_today", earned + granted)
    tx.saveNoValidate(user)
    reply = Object.assign(loja.wallet(user), { granted: granted })
  })
  if (reply === null) {
    return e.json(400, { message: "Partida inválida." })
  }
  return e.json(200, reply)
}, $apis.requireAuth("users"))

// Compra: `{item}`. O preço é o daqui, nunca o do app.
routerAdd("POST", "/api/cascapp/buy", (e) => {
  const loja = require(`${__hooks}/loja.js`)
  const item = String(e.requestInfo().body.item || "")
  const price = loja.PRICES[item]
  if (price === undefined) {
    return e.json(404, { message: "Item inexistente." })
  }
  let status = 200
  let reply = null
  e.app.runInTransaction((tx) => {
    const user = tx.findRecordById("users", e.auth.id)
    const owned = loja.jsonOf(user, "owned", [])
    if (owned.includes(item)) {
      status = 409
      reply = { message: "Item já comprado." }
      return
    }
    if (user.getInt("coins") < price) {
      status = 402
      reply = { message: "Moedas insuficientes." }
      return
    }
    owned.push(item)
    user.set("coins", user.getInt("coins") - price)
    user.set("owned", owned)
    tx.saveNoValidate(user)
    reply = loja.wallet(user)
  })
  return e.json(status, reply)
}, $apis.requireAuth("users"))
