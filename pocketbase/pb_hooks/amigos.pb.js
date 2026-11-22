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
      friends.push(perfil.publicProfile(e.app.findRecordById("users", row.getString("friend"))))
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
  const other = String(e.request.pathValue("id") || "")
  e.app.runInTransaction((tx) => {
    const rows = tx.findRecordsByFilter(
      "friendships",
      "(owner = {:me} && friend = {:other}) || (owner = {:other} && friend = {:me})",
      "", 2, 0, { me: e.auth.id, other }
    )
    for (const row of rows) tx.delete(row)
  })
  return e.noContent(204)
}, $apis.requireAuth("users"))

// O perfil de um amigo: o público, os números por jogo e as 20 partidas mais
// recentes (`pb_migrations/1760950000_partidas.js`). Só para amigo; para os
// outros, 404, como se a conta não existisse.
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
  const recent = e.app.findRecordsByFilter("matches", "owner = {:id}", "-played_at", 20, 0, { id }).map((row) => ({
    game: row.getString("game"),
    mode: row.getString("mode"),
    result: row.getString("result"),
    against: row.getString("against"),
    detail: row.getString("detail"),
    at: row.getInt("played_at"),
  }))
  return e.json(200, { profile: perfil.publicProfile(user), stats, recent })
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
