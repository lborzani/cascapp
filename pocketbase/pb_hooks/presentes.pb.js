/// <reference path="../pb_data/types.d.ts" />

// Presentes entre amigos (ver `pb_migrations/1764200000_presentes.js`). Regras
// em `presentes.js`; o catálogo e a carteira, em `loja.js`; a amizade, em
// `amizade.js`; a notificação, em `conversa.js`. Tudo por `require` no handler.

// A caixa: os presentes fechados que chegaram, os amigos que já ganharam o meu
// presentinho de hoje e quanto ele vale.
routerAdd("GET", "/api/cascapp/gifts", (e) => {
  const loja = require(`${__hooks}/loja.js`)
  const presentes = require(`${__hooks}/presentes.js`)
  const me = e.auth.id
  const today = loja.brDay(Date.now())
  const rows = e.app.findRecordsByFilter("gifts", "to = {:me} && opened = false", "-created", presentes.INBOX, 0, { me })
  const gifts = []
  for (const row of rows) {
    try {
      gifts.push(presentes.toJson(row, e.app.findRecordById("users", row.getString("from"))))
    } catch (_) {
      // Quem mandou apagou a conta no meio: o `cascadeDelete` leva o presente já já.
    }
  }
  const sent = e.app.findRecordsByFilter("gifts", "from = {:me} && day = {:today} && coins > 0", "", 200, 0, { me, today })
  return e.json(200, {
    gifts: gifts,
    sent_today: sent.map((row) => row.getString("to")),
    daily_coins: presentes.DAILY_COINS,
  })
}, $apis.requireAuth("users"))

// Presente de item: `{to, item}`. Quem manda paga o preço da loja e o item entra
// no `owned` do amigo agora. 404 sem amizade ou item fora de venda, 409 o amigo
// já tem, 402 sem saldo. Devolve a carteira de quem mandou.
routerAdd("POST", "/api/cascapp/gifts", (e) => {
  const loja = require(`${__hooks}/loja.js`)
  const presentes = require(`${__hooks}/presentes.js`)
  const amizade = require(`${__hooks}/amizade.js`)
  const conversa = require(`${__hooks}/conversa.js`)
  const me = e.auth.id
  const body = e.requestInfo().body || {}
  const to = String(body.to || "")
  const item = String(body.item || "")
  if (to === me || !amizade.areFriends(e.app, me, to)) {
    return e.json(404, { message: "Amigo não encontrado." })
  }
  const price = loja.loadCatalog(e.app).prices[item]
  let status = 200
  let reply = null
  e.app.runInTransaction((tx) => {
    const sender = tx.findRecordById("users", me)
    const friend = tx.findRecordById("users", to)
    const owned = loja.jsonOf(friend, "owned", [])
    const problem = presentes.itemProblem(price, owned.includes(item), sender.getInt("coins"))
    if (problem) {
      status = problem.status
      reply = { message: problem.message }
      return
    }
    sender.set("coins", sender.getInt("coins") - price)
    tx.saveNoValidate(sender)
    owned.push(item)
    friend.set("owned", owned)
    tx.saveNoValidate(friend)
    const gift = new Record(tx.findCollectionByNameOrId("gifts"))
    gift.set("from", me)
    gift.set("to", to)
    gift.set("item", item)
    gift.set("coins", 0)
    gift.set("day", loja.brDay(Date.now()))
    gift.set("opened", false)
    tx.save(gift)
    reply = loja.wallet(sender)
  })
  if (status === 200) {
    conversa.push(e.app, to, me, "Te mandou um presente 🎁")
  }
  return e.json(status, reply)
}, $apis.requireAuth("users"))

// O presentinho do dia: `{to}`. De graça; as moedas entram quando o amigo abre.
// 404 sem amizade, 409 já mandou hoje para ele, 429 ele já ganhou demais hoje.
routerAdd("POST", "/api/cascapp/gifts/daily", (e) => {
  const loja = require(`${__hooks}/loja.js`)
  const presentes = require(`${__hooks}/presentes.js`)
  const amizade = require(`${__hooks}/amizade.js`)
  const conversa = require(`${__hooks}/conversa.js`)
  const me = e.auth.id
  const to = String((e.requestInfo().body || {}).to || "")
  if (to === me || !amizade.areFriends(e.app, me, to)) {
    return e.json(404, { message: "Amigo não encontrado." })
  }
  const today = loja.brDay(Date.now())
  let problem = null
  e.app.runInTransaction((tx) => {
    const coins = $dbx.exp("coins > 0")
    const sent = tx.countRecords("gifts", $dbx.hashExp({ from: me, to: to, day: today }), coins)
    const received = tx.countRecords("gifts", $dbx.hashExp({ to: to, day: today }), coins)
    problem = presentes.dailyProblem(sent > 0, received)
    if (problem) {
      return
    }
    const gift = new Record(tx.findCollectionByNameOrId("gifts"))
    gift.set("from", me)
    gift.set("to", to)
    gift.set("item", "")
    gift.set("coins", presentes.DAILY_COINS)
    gift.set("day", today)
    gift.set("opened", false)
    tx.save(gift)
  })
  if (problem) {
    return e.json(problem.status, { message: problem.message })
  }
  conversa.push(e.app, to, me, "Te mandou um presentinho de " + presentes.DAILY_COINS + " moedas 🎁")
  return e.json(200, { sent: true })
}, $apis.requireAuth("users"))

// Abrir: marca aberto e, se forem moedas, elas entram agora. 404 para presente
// que não é meu ou já foi aberto. Devolve a carteira, mais `item` e `coins`.
routerAdd("POST", "/api/cascapp/gifts/{id}/open", (e) => {
  const loja = require(`${__hooks}/loja.js`)
  const me = e.auth.id
  const id = String(e.request.pathValue("id") || "")
  let reply = null
  e.app.runInTransaction((tx) => {
    let gift = null
    try {
      gift = tx.findFirstRecordByFilter("gifts", "id = {:id} && to = {:me} && opened = false", { id, me })
    } catch (_) {
      return
    }
    gift.set("opened", true)
    tx.save(gift)
    const user = tx.findRecordById("users", me)
    const coins = gift.getInt("coins")
    if (coins > 0) {
      user.set("coins", user.getInt("coins") + coins)
      tx.saveNoValidate(user)
    }
    reply = Object.assign(loja.wallet(user), { item: gift.getString("item"), coins: coins })
  })
  if (reply === null) {
    return e.json(404, { message: "Presente não encontrado." })
  }
  return e.json(200, reply)
}, $apis.requireAuth("users"))
