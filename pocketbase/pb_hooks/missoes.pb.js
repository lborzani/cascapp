/// <reference path="../pb_data/types.d.ts" />

// As missões (ver `pb_migrations/1764100000_missoes.js`). O progresso anda no
// `/api/cascapp/reward` (`loja.pb.js`), na mesma transação do prêmio; aqui só se
// lista e se resgata. Regras comuns em `missoes.js`, por `require` no handler.

// O admin salva uma missão: confere o evento e o item do prêmio.
onRecordValidate((e) => {
  const missoes = require(`${__hooks}/missoes.js`)
  const r = e.record
  const shop = e.app.findAllRecords("shop_items").map((row) => row.getString("item"))
  const problem = missoes.missionProblem({
    track: r.getString("track"),
    event: r.getString("event"),
    reward_coins: r.getInt("reward_coins"),
    reward_item: r.getString("reward_item"),
  }, shop)
  if (problem !== "") {
    throw new BadRequestError(problem)
  }
  e.next()
}, "missions")

// As missões valendo agora para quem pede, com o progresso, e os eventos no ar.
routerAdd("GET", "/api/cascapp/missions", (e) => {
  const loja = require(`${__hooks}/loja.js`)
  const missoes = require(`${__hooks}/missoes.js`)
  const now = Date.now()
  const day = loja.brDay(now)
  const user = e.app.findRecordById("users", e.auth.id)
  const data = missoes.load(e.app)
  const live = missoes.liveMissions(data.missions, data.events, user.id, day, now)
  const state = loja.jsonOf(user, "missions_state", {})
  const open = data.events.filter((ev) => live.some((m) => m.eventKey === ev.key))
  return e.json(200, {
    day: day,
    missions: missoes.view(state, live),
    events: open.map((ev) => ({ key: ev.key, name: ev.name, ends: Math.floor(ev.ends / 1000) })),
  })
}, $apis.requireAuth("users"))

// Resgate: `{key}`. 404 para missão que não vale agora, 409 incompleta ou já
// resgatada. Paga as moedas e o item numa transação e devolve a carteira, mais
// `granted` e `item`.
routerAdd("POST", "/api/cascapp/missions/claim", (e) => {
  const loja = require(`${__hooks}/loja.js`)
  const missoes = require(`${__hooks}/missoes.js`)
  const key = String(e.requestInfo().body.key || "")
  const now = Date.now()
  const day = loja.brDay(now)
  let status = 200
  let reply = null
  e.app.runInTransaction((tx) => {
    const user = tx.findRecordById("users", e.auth.id)
    const data = missoes.load(tx)
    const live = missoes.liveMissions(data.missions, data.events, user.id, day, now)
    const mission = live.find((m) => m.key === key)
    if (!mission) {
      status = 404
      reply = { message: "Missão fora do ar." }
      return
    }
    const state = loja.jsonOf(user, "missions_state", {})
    if (missoes.claimedOf(state, mission)) {
      status = 409
      reply = { message: "Missão já resgatada." }
      return
    }
    if (missoes.progressOf(state, mission) < mission.target) {
      status = 409
      reply = { message: "Missão incompleta." }
      return
    }
    missoes.slot(state, mission.period).c.push(key)
    user.set("missions_state", missoes.prune(state, live))
    user.set("coins", user.getInt("coins") + mission.reward_coins)
    const owned = loja.jsonOf(user, "owned", [])
    if (mission.reward_item !== "" && !owned.includes(mission.reward_item)) {
      owned.push(mission.reward_item)
      user.set("owned", owned)
    }
    tx.saveNoValidate(user)
    reply = Object.assign(loja.wallet(user), { granted: mission.reward_coins, item: mission.reward_item })
  })
  return e.json(status, reply)
}, $apis.requireAuth("users"))
