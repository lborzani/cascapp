/// <reference path="../pb_data/types.d.ts" />

// Amigos (ver `pb_migrations/1760750000_amizades.js`). As três rotas falam só
// da conta que chama: ninguém lê nem mexe na lista de outro.

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

// Adiciona pelo código de amigo, nos dois sentidos. Já amigos: responde igual,
// sem erro — ler o mesmo QR duas vezes não é falha de ninguém.
routerAdd("POST", "/api/cascapp/friends/{code}", (e) => {
  const perfil = require(`${__hooks}/perfil.js`)
  const code = String(e.request.pathValue("code") || "").toUpperCase()
  let other
  try {
    other = e.app.findFirstRecordByData("users", "friend_code", code)
  } catch (_) {
    return e.json(404, { message: "Nenhuma conta com esse código." })
  }
  if (other.id === e.auth.id) {
    return e.json(400, { message: "Esse é o seu próprio código." })
  }
  e.app.runInTransaction((tx) => {
    const collection = tx.findCollectionByNameOrId("friendships")
    for (const [owner, friend] of [[e.auth.id, other.id], [other.id, e.auth.id]]) {
      try {
        tx.findFirstRecordByFilter("friendships", "owner = {:owner} && friend = {:friend}", { owner, friend })
      } catch (_) {
        const row = new Record(collection)
        row.set("owner", owner)
        row.set("friend", friend)
        tx.save(row)
      }
    }
  })
  return e.json(200, perfil.publicProfile(other))
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
