/// <reference path="../pb_data/types.d.ts" />

// Amigos (ver `pb_migrations/1760750000_amizades.js`) e pedidos de amizade
// (`1760900000_pedidos_amizade.js`). As rotas falam só da conta que chama:
// ninguém lê nem mexe na lista ou nos pedidos de outro.

// A lista de amigos, com o perfil público de cada um, mais antigos primeiro.
routerAdd("GET", "/api/cascapp/friends", (e) => {
  const perfil = require(`${__hooks}/perfil.js`)
  const rows = e.app.findRecordsByFilter(
    "friendships", "owner = {:me}", "created", 500, 0, { me: e.auth.id }
  )
  const friends = []
  for (const row of rows) {
    try {
      const profile = perfil.publicProfile(e.app.findRecordById("users", row.getString("friend")))
      friends.push(Object.assign(profile, { muted: row.getBool("muted") }))
    } catch (_) {}
  }
  return e.json(200, { items: friends })
}, $apis.requireAuth("users"))

// Pede amizade pelo código. Responde o perfil do outro com `status`:
// - "requested": o pedido foi feito (ou já estava feito) e espera o outro;
// - "friends": já eram amigos, ou o outro já tinha pedido — os dois querem, e
//   a amizade nasce aqui.
// A versão até a 1.58 lê só o perfil e diz "adicionado"; para ela, o amigo
// aparece quando o outro aceitar.
routerAdd("POST", "/api/cascapp/friends/{code}", (e) => {
  const perfil = require(`${__hooks}/perfil.js`)
  const amizade = require(`${__hooks}/amizade.js`)
  const code = String(e.request.pathValue("code") || "").toUpperCase()
  let other
  try {
    other = e.app.findFirstRecordByData("users", "friend_code", code)
  } catch (_) {
    return e.json(404, { message: "Nenhuma conta com esse código." })
  }
  const me = e.auth.id
  if (other.id === me) {
    return e.json(400, { message: "Esse é o seu próprio código." })
  }
  const reply = (status) => Object.assign(perfil.publicProfile(other), { status })
  if (amizade.findBlock(e.app, me, other.id)) {
    return e.json(409, { message: "Você bloqueou essa conta. Desbloqueie no painel de amigos." })
  }
  // Quem foi bloqueado não fica sabendo: o pedido "vai", e nada é gravado.
  if (amizade.findBlock(e.app, other.id, me)) {
    return e.json(200, reply("requested"))
  }
  if (amizade.areFriends(e.app, me, other.id)) {
    return e.json(200, reply("friends"))
  }
  if (amizade.findRequest(e.app, other.id, me)) {
    e.app.runInTransaction((tx) => amizade.befriend(tx, me, other.id))
    return e.json(200, reply("friends"))
  }
  if (!amizade.findRequest(e.app, me, other.id)) {
    if (e.app.countRecords("friend_requests", $dbx.hashExp({ from: me })) >= amizade.MAX_PENDING) {
      return e.json(429, { message: "Pedidos demais esperando resposta." })
    }
    const row = new Record(e.app.findCollectionByNameOrId("friend_requests"))
    row.set("from", me)
    row.set("to", other.id)
    e.app.save(row)
  }
  return e.json(200, reply("requested"))
}, $apis.requireAuth("users"))

// Desfaz a amizade, nos dois sentidos. Quem não era amigo: 204 do mesmo jeito.
routerAdd("DELETE", "/api/cascapp/friends/{id}", (e) => {
  const amizade = require(`${__hooks}/amizade.js`)
  const other = String(e.request.pathValue("id") || "")
  e.app.runInTransaction((tx) => amizade.unfriend(tx, e.auth.id, other))
  return e.noContent(204)
}, $apis.requireAuth("users"))

// Silencia (`{muted: true}`) ou reativa as notificações das mensagens de um
// amigo. Só o meu lado da amizade; quem não é amigo: 404.
routerAdd("PUT", "/api/cascapp/friends/{id}/mute", (e) => {
  const muted = (e.requestInfo().body || {}).muted
  if (typeof muted !== "boolean") {
    return e.json(400, { message: "Diga se é para silenciar." })
  }
  let row
  try {
    row = e.app.findFirstRecordByFilter(
      "friendships", "owner = {:me} && friend = {:friend}",
      { me: e.auth.id, friend: String(e.request.pathValue("id") || "") }
    )
  } catch (_) {
    return e.json(404, { message: "Amigo não encontrado." })
  }
  row.set("muted", muted)
  e.app.save(row)
  return e.noContent(204)
}, $apis.requireAuth("users"))

// As contas que eu bloqueei, mais novas primeiro, com o perfil público.
routerAdd("GET", "/api/cascapp/blocks", (e) => {
  const perfil = require(`${__hooks}/perfil.js`)
  const items = []
  for (const row of e.app.findRecordsByFilter("blocks", "owner = {:me}", "-created", 500, 0, { me: e.auth.id })) {
    try {
      items.push(perfil.publicProfile(e.app.findRecordById("users", row.getString("blocked"))))
    } catch (_) {}
  }
  return e.json(200, { items })
}, $apis.requireAuth("users"))

// Bloqueia uma conta pelo id: desfaz a amizade e os pedidos entre os dois, e o
// outro não consegue mais pedir. Já bloqueada: 204 do mesmo jeito.
routerAdd("POST", "/api/cascapp/blocks/{id}", (e) => {
  const amizade = require(`${__hooks}/amizade.js`)
  const me = e.auth.id
  const other = String(e.request.pathValue("id") || "")
  if (other === me) {
    return e.json(400, { message: "Não dá para bloquear a si mesmo." })
  }
  try {
    e.app.findRecordById("users", other)
  } catch (_) {
    return e.json(404, { message: "Conta não encontrada." })
  }
  e.app.runInTransaction((tx) => {
    amizade.unfriend(tx, me, other)
    if (!amizade.findBlock(tx, me, other)) {
      const row = new Record(tx.findCollectionByNameOrId("blocks"))
      row.set("owner", me)
      row.set("blocked", other)
      tx.save(row)
    }
  })
  return e.noContent(204)
}, $apis.requireAuth("users"))

// Desbloqueia. A amizade não volta sozinha: precisa de pedido novo.
routerAdd("DELETE", "/api/cascapp/blocks/{id}", (e) => {
  const amizade = require(`${__hooks}/amizade.js`)
  const row = amizade.findBlock(e.app, e.auth.id, String(e.request.pathValue("id") || ""))
  if (row) e.app.delete(row)
  return e.noContent(204)
}, $apis.requireAuth("users"))

// O perfil de um amigo: o público e os números por jogo
// (`pb_migrations/1760950000_partidas.js`). As partidas uma a uma não saem daqui:
// o perfil mostra só o total por jogo. Só para amigo; para os outros, 404, como
// se a conta não existisse.
routerAdd("GET", "/api/cascapp/friends/{id}/profile", (e) => {
  const perfil = require(`${__hooks}/perfil.js`)
  const amizade = require(`${__hooks}/amizade.js`)
  const id = String(e.request.pathValue("id") || "")
  if (!amizade.areFriends(e.app, e.auth.id, id)) {
    return e.json(404, { message: "Amigo não encontrado." })
  }
  let user
  try {
    user = e.app.findRecordById("users", id)
  } catch (_) {
    return e.json(404, { message: "Amigo não encontrado." })
  }
  const counts = arrayOf(new DynamicModel({ game: "", result: "", n: 0 }))
  e.app.db()
    .newQuery("SELECT game, result, COUNT(*) AS n FROM matches WHERE owner = {:id} GROUP BY game, result")
    .bind({ id })
    .all(counts)
  const stats = {}
  for (const row of counts) {
    const game = stats[row.game] || (stats[row.game] = { played: 0, won: 0, lost: 0, draw: 0 })
    game.played += row.n
    if (row.result === "win") game.won += row.n
    if (row.result === "loss") game.lost += row.n
    if (row.result === "draw") game.draw += row.n
  }
  // `recent` vazio, e não ausente: até a 1.77 o app recusa a resposta sem a lista
  // e mostraria "Não deu para carregar" no perfil inteiro.
  return e.json(200, { profile: perfil.publicProfile(user), stats, recent: [] })
}, $apis.requireAuth("users"))

// Os pedidos que esperam resposta: `incoming` (para mim) e `outgoing` (meus),
// mais novos primeiro. Cada um é `{id, created, profile}`, com o perfil público
// da outra conta.
routerAdd("GET", "/api/cascapp/friends/requests", (e) => {
  const perfil = require(`${__hooks}/perfil.js`)
  const me = e.auth.id
  const list = (filter, otherField) => {
    const out = []
    for (const row of e.app.findRecordsByFilter("friend_requests", filter, "-created", 100, 0, { me })) {
      try {
        out.push({
          id: row.id,
          created: row.getString("created"),
          profile: perfil.publicProfile(e.app.findRecordById("users", row.getString(otherField))),
        })
      } catch (_) {}
    }
    return out
  }
  return e.json(200, { incoming: list("to = {:me}", "from"), outgoing: list("from = {:me}", "to") })
}, $apis.requireAuth("users"))

// Aceita um pedido recebido. Pedido de outro, ou que não existe mais: 404.
routerAdd("POST", "/api/cascapp/friends/requests/{id}/accept", (e) => {
  const perfil = require(`${__hooks}/perfil.js`)
  const amizade = require(`${__hooks}/amizade.js`)
  let row
  try {
    row = e.app.findRecordById("friend_requests", String(e.request.pathValue("id") || ""))
  } catch (_) {
    return e.json(404, { message: "Pedido não encontrado." })
  }
  if (row.getString("to") !== e.auth.id) {
    return e.json(404, { message: "Pedido não encontrado." })
  }
  const from = row.getString("from")
  e.app.runInTransaction((tx) => amizade.befriend(tx, e.auth.id, from))
  try {
    return e.json(200, perfil.publicProfile(e.app.findRecordById("users", from)))
  } catch (_) {
    return e.json(404, { message: "Pedido não encontrado." })
  }
}, $apis.requireAuth("users"))

// Recusa (quem recebeu) ou cancela (quem mandou) um pedido. Pedido de outros
// dois: 404, como se não existisse.
routerAdd("DELETE", "/api/cascapp/friends/requests/{id}", (e) => {
  let row
  try {
    row = e.app.findRecordById("friend_requests", String(e.request.pathValue("id") || ""))
  } catch (_) {
    return e.json(404, { message: "Pedido não encontrado." })
  }
  if (row.getString("to") !== e.auth.id && row.getString("from") !== e.auth.id) {
    return e.json(404, { message: "Pedido não encontrado." })
  }
  e.app.delete(row)
  return e.noContent(204)
}, $apis.requireAuth("users"))
