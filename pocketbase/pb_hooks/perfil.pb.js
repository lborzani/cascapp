/// <reference path="../pb_data/types.d.ts" />

// Perfil público da conta (ver `pb_migrations/1760650000_perfil.js`).
//
// Cada handler roda num contexto isolado: o que é comum mora em `perfil.js` e
// entra por `require` dentro do handler, não no topo deste arquivo.

// Conta nova: código de amigo sorteado e Elo inicial, por cima do que vier no
// corpo. É hook do registro, e não do pedido, para valer também para conta
// criada pelo painel.
onRecordCreate((e) => {
  const perfil = require(`${__hooks}/perfil.js`)
  e.record.set("friend_code", perfil.newFriendCode(e.app))
  e.record.set("elo_chess", perfil.START_ELO)
  e.record.set("games_chess", 0)
  e.next()
}, "users")

// Acha uma conta pelo código de amigo. Rota própria porque a listagem da
// coleção continua fechada: com ela aberta, qualquer conta baixaria todas.
routerAdd("GET", "/api/cascapp/by-code/{code}", (e) => {
  const perfil = require(`${__hooks}/perfil.js`)
  const code = String(e.request.pathValue("code") || "").toUpperCase()
  let record
  try {
    record = e.app.findFirstRecordByData("users", "friend_code", code)
  } catch (_) {
    return e.json(404, { message: "Nenhuma conta com esse código." })
  }
  return e.json(200, perfil.publicProfile(record))
}, $apis.requireAuth("users"))
