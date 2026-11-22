/// <reference path="../pb_data/types.d.ts" />

// A conversa direta entre amigos (`pb_migrations/1761000000_conversas.js`).
// Só entre amigos, e só da conta que chama: ninguém lê nem escreve no fio de
// outros dois. Quem não é amigo recebe 404, como se a conversa não existisse.

// Não lidas por amigo: `{counts: {id: n}}`. O app pergunta de tempos em tempos
// para acender a bolinha.
routerAdd("GET", "/api/cascapp/chat/unread", (e) => {
  const rows = arrayOf(new DynamicModel({ from: "", n: 0 }))
  e.app.db()
    .newQuery("SELECT [[from]] AS [[from]], COUNT(*) AS n FROM direct_messages WHERE [[to]] = {:me} AND [[read]] = FALSE GROUP BY [[from]]")
    .bind({ me: e.auth.id })
    .all(rows)
  const counts = {}
  for (const row of rows) counts[row.from] = row.n
  return e.json(200, { counts })
}, $apis.requireAuth("users"))

// As últimas mensagens do par, da mais antiga à mais nova. As recebidas viram
// lidas.
routerAdd("GET", "/api/cascapp/chat/{friend}", (e) => {
  const amizade = require(`${__hooks}/amizade.js`)
  const conversa = require(`${__hooks}/conversa.js`)
  const me = e.auth.id
  const friend = String(e.request.pathValue("friend") || "")
  if (!amizade.areFriends(e.app, me, friend)) {
    return e.json(404, { message: "Conversa não encontrada." })
  }
  const rows = e.app.findRecordsByFilter(
    "direct_messages",
    "(from = {:me} && to = {:friend}) || (from = {:friend} && to = {:me})",
    "-created", conversa.PAGE, 0, { me, friend }
  )
  // Sem `rows.reverse()`: o array vem do Go, e inverter no lugar duplica itens
  // (o JSVM troca as referências e perde uma). Um laço de trás para frente.
  const items = []
  for (let i = rows.length - 1; i >= 0; i--) {
    const row = rows[i]
    if (row.getString("to") === me && !row.getBool("read")) {
      row.set("read", true)
      e.app.saveNoValidate(row)
    }
    items.push(conversa.toJson(row))
  }
  return e.json(200, { items })
}, $apis.requireAuth("users"))

// Manda uma mensagem: `{kind: "text", text}`, `{kind: "emote", emote}` ou
// `{kind: "invite", game, room}`. 400 para o que não passa na limpeza, 429 para
// quem manda rápido demais.
routerAdd("POST", "/api/cascapp/chat/{friend}", (e) => {
  const amizade = require(`${__hooks}/amizade.js`)
  const conversa = require(`${__hooks}/conversa.js`)
  const me = e.auth.id
  const friend = String(e.request.pathValue("friend") || "")
  if (!amizade.areFriends(e.app, me, friend)) {
    return e.json(404, { message: "Conversa não encontrada." })
  }
  const body = e.requestInfo().body || {}
  const fields = conversa.validate(body)
  if (!fields) {
    return e.json(400, { message: "Mensagem inválida." })
  }
  const since = new DateTime().add(-60 * 1000 * 1000 * 1000)
  const recent = e.app.countRecords(
    "direct_messages",
    $dbx.and($dbx.hashExp({ from: me }), $dbx.exp("created > {:since}", { since: since.string() }))
  )
  if (recent >= conversa.PER_MINUTE) {
    return e.json(429, { message: "Calma: muitas mensagens seguidas." })
  }
  const row = new Record(e.app.findCollectionByNameOrId("direct_messages"))
  row.set("from", me)
  row.set("to", friend)
  row.set("read", false)
  for (const key of Object.keys(fields)) row.set(key, fields[key])
  e.app.save(row)
  conversa.trim(e.app, me, friend)
  conversa.notify(e.app, row)
  return e.json(200, conversa.toJson(row))
}, $apis.requireAuth("users"))

// O token do Firebase deste aparelho (`pb_migrations/1761050000_tokens_push.js`).
// O mesmo token que estava em outra conta passa para esta: o aparelho é um só.
routerAdd("PUT", "/api/cascapp/push-token", (e) => {
  const token = String((e.requestInfo().body || {}).token || "")
  if (token.length < 10 || token.length > 500 || /\s/.test(token)) {
    return e.json(400, { message: "Token inválido." })
  }
  let row
  try {
    row = e.app.findFirstRecordByData("push_tokens", "token", token)
  } catch (_) {
    row = new Record(e.app.findCollectionByNameOrId("push_tokens"))
    row.set("token", token)
  }
  row.set("owner", e.auth.id)
  e.app.save(row)
  return e.noContent(204)
}, $apis.requireAuth("users"))
